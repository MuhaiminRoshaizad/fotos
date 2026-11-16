package my.minned.fotos

import android.content.Context
import android.content.ContentUris
import android.content.ContentValues
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.container.Mp4TimestampData
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.InAppMp4Muxer
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit

/**
 * Cuts parts out of a video and saves what is left beside the original.
 *
 * Nothing touches the original until the new video is complete:
 *  1. Media3 Transformer encodes the kept parts into a hidden file in the
 *     original's own folder (so the save is a rename, never a copy across
 *     folders or disks).
 *  2. The file is flushed to disk and checked: it must open, hold video
 *     (and audio if the original had it) and last as long as the parts kept.
 *  3. Only then is it named, as a copy ("Trip (edited).mp4"). To replace,
 *     the original then goes to Android's trash, recoverable for 30 days,
 *     and the copy takes its name. Each step leaves both videos safe if
 *     fotos is stopped right after it; if the trash refuses, the copy stays.
 *
 * Writing beside the original needs All files access: MediaStore only lets
 * an app create videos in DCIM, Movies and Pictures, and a video from
 * Download or a messaging app must not land anywhere else. The same access
 * lets fotos trash the original itself, with no screen to ask from, which
 * a save running in the background needs (MediaProvider's update allows
 * IS_TRASHED from an app that manages external storage, and renames the
 * file and sets its 30 days just as the system's own trash request does).
 *
 * Runs on any Context, so [SaveService] can hold it with no screen open.
 */
@OptIn(UnstableApi::class)
class VideoCutter(
    private val context: Context,
    private val io: ExecutorService,
    private val onProgress: (Int) -> Unit,
) {
    class CutException(val code: String, message: String) : Exception(message)

    private class Source(
        val id: Long,
        val uri: Uri,
        val file: File,
        val taken: Long?,
        val favourite: Boolean,
        val hasAudio: Boolean,
        val bitrate: Int?,
    )

    private val main = Handler(Looper.getMainLooper())
    private var transformer: Transformer? = null
    private var temp: File? = null
    private var finished = false

    // Set once the encode is checked and saving begins: from there it runs
    // to the end, so a cancel can't leave the trash and the files half done.
    private var committing = false
    private var reply: ((Result<Map<String, Any?>>) -> Unit)? = null

    // The kept parts' lengths, for progress by time (see [byLength]).
    private var lengths: List<Long> = emptyList()

    /**
     * Starts the cut. [keep] lists the parts to keep, in order, as
     * [start, end] in milliseconds. [done] is called once, on the main
     * thread, with the new video's id and name, or the failure.
     */
    fun start(
        id: Long,
        keep: List<Pair<Long, Long>>,
        replace: Boolean,
        done: (Result<Map<String, Any?>>) -> Unit,
    ) {
        reply = done
        lengths = keep.map { it.second - it.first }
        io.execute {
            try {
                if (!Environment.isExternalStorageManager()) {
                    throw CutException("no_access", "All files access is off")
                }
                val src = source(id)
                val dir = src.file.parentFile ?: throw CutException("failed", "No folder")
                val expected = keep.sumOf { it.second - it.first }
                if (keep.isEmpty() || expected <= 0) throw CutException("failed", "Nothing kept")
                // The encode may come out larger than the original; leave
                // room for that and for the system.
                if (dir.usableSpace < src.file.length() * 2 + 64L * 1024 * 1024) {
                    throw CutException("no_space", "Not enough free space")
                }
                clearStale(dir)
                val out = File(dir, ".${src.file.nameWithoutExtension}.fotos-${System.currentTimeMillis()}.mp4")
                temp = out
                main.post { encode(src, keep, out, expected, replace) }
            } catch (e: Exception) {
                fail(e)
            }
        }
    }

    /** Stops the encode and removes its unfinished file. */
    fun cancel() {
        main.post {
            if (finished || committing) return@post
            transformer?.cancel()
            transformer = null
            fail(CutException("cancelled", "Cancelled"))
        }
    }

    private fun source(id: Long): Source {
        val uri = ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id)
        val cols = arrayOf(
            MediaStore.MediaColumns.DATA,
            MediaStore.MediaColumns.DATE_TAKEN,
            MediaStore.MediaColumns.IS_FAVORITE,
            MediaStore.MediaColumns.DATE_ADDED,
        )
        val (path, taken, favourite) = context.contentResolver.query(uri, cols, null, null, null)?.use { c ->
            if (!c.moveToFirst()) null else Triple(
                c.getString(0),
                // The timeline places a video with no date taken by when it
                // was added; the edit gets that as its date taken, so it
                // sits beside the original instead of jumping to today.
                c.getLong(1).takeIf { !c.isNull(1) && it > 0 } ?: (c.getLong(3) * 1000).takeIf { it > 0 },
                c.getInt(2) == 1,
            )
        } ?: throw CutException("failed", "The video is no longer in the library")
        val file = File(path)
        if (!file.isFile) throw CutException("failed", "The video's file is missing")
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(file.path)
            return Source(
                id = id,
                uri = uri,
                file = file,
                taken = taken,
                favourite = favourite,
                hasAudio = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes",
                bitrate = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull(),
            )
        } finally {
            r.release()
        }
    }

    private fun encode(
        src: Source,
        keep: List<Pair<Long, Long>>,
        out: File,
        expected: Long,
        replace: Boolean,
    ) {
        if (finished) return
        val items = keep.map { (a, b) ->
            EditedMediaItem.Builder(
                MediaItem.Builder()
                    .setUri(src.uri)
                    .setClippingConfiguration(
                        MediaItem.ClippingConfiguration.Builder()
                            .setStartPositionMs(a)
                            .setEndPositionMs(b)
                            .build(),
                    )
                    .build(),
            ).build()
        }
        val sequence = if (src.hasAudio) {
            EditedMediaItemSequence.withAudioAndVideoFrom(items)
        } else {
            EditedMediaItemSequence.withVideoFrom(items)
        }
        val encoders = DefaultEncoderFactory.Builder(context)
            .apply {
                // As sharp as the original: without this the encoder picks
                // its own rate from the size, often lower.
                src.bitrate?.let {
                    setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(it).build())
                }
            }
            .build()
        // Android takes a video's date taken from the file and won't let an
        // app set it afterwards ("Ignoring mutation of datetaken"), so the
        // date goes into the file: Transformer copies the original's own,
        // and an original without one (a download) gets the date the
        // timeline already places it by.
        // A file with no date of its own still carries one, set to zero.
        val muxer = InAppMp4Muxer.Factory { entries ->
            val taken = src.taken
            val own = entries.filterIsInstance<Mp4TimestampData>()
            if (taken != null && own.none { it.creationTimestampSeconds > 0 }) {
                entries.removeAll(own.toSet())
                val t = Mp4TimestampData.unixTimeToMp4TimeSeconds(taken)
                entries.add(Mp4TimestampData(t, t))
            }
        }
        val t = Transformer.Builder(context)
            .setEncoderFactory(encoders)
            .setMuxerFactory(muxer)
            // fotos sends nothing anywhere, Android's media metrics included.
            .setUsePlatformDiagnostics(false)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, result: ExportResult) {
                    transformer = null
                    if (finished) return
                    // Encoding is done: past here the save can't be stopped.
                    onProgress(100)
                    io.execute {
                        try {
                            check(out, expected, src.hasAudio)
                            main.post { save(src, out, replace) }
                        } catch (e: Exception) {
                            fail(e)
                        }
                    }
                }

                override fun onError(composition: Composition, result: ExportResult, e: ExportException) {
                    transformer = null
                    fail(CutException("failed", e.message ?: "The video could not be encoded"))
                }
            })
            .build()
        transformer = t
        try {
            t.start(Composition.Builder(sequence).build(), out.path)
        } catch (e: Exception) {
            transformer = null
            fail(e)
            return
        }
        poll()
    }

    private fun poll() {
        val t = transformer ?: return
        val holder = ProgressHolder()
        if (t.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) onProgress(byLength(holder.progress, lengths))
        main.postDelayed({ poll() }, 250)
    }

    /** Flushes [out] to disk and checks it is a whole video of the right length. */
    private fun check(out: File, expected: Long, audio: Boolean) {
        RandomAccessFile(out, "rw").use { it.fd.sync() }
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(out.path)
            val video = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
            val sound = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
            val length = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0
            val slack = 1000 + expected / 100
            if (!video || (audio && !sound) || kotlin.math.abs(length - expected) > slack) {
                throw CutException("failed", "The new video did not check out (${length} ms, expected $expected)")
            }
        } finally {
            r.release()
        }
    }

    /**
     * From the main thread: names the new file as a copy, then, when
     * replacing, trashes the original and gives the copy its name.
     */
    private fun save(src: Source, out: File, replace: Boolean) {
        if (finished) return
        committing = true
        io.execute {
            try {
                var target = File(out.parentFile, copyName(src.file))
                if (!out.renameTo(target)) {
                    throw CutException("failed", "Could not name the new video ${target.name}")
                }
                // Named and visible: from here the edit is kept whatever happens.
                temp = null
                val replaced = replace && trash(src)
                if (replaced) {
                    // The trash renamed the original, which frees its name;
                    // if the rename fails anyway, the copy's name stands.
                    val wanted = File(out.parentFile, replaceName(src.file))
                    if (!wanted.exists() && target.renameTo(wanted)) target = wanted
                }
                publish(src, target, replaced)
            } catch (e: Exception) {
                fail(e)
            }
        }
    }

    /** Moves the original to Android's trash; false, leaving it, if Android refuses. */
    private fun trash(src: Source): Boolean = try {
        val trashed = ContentValues().apply { put(MediaStore.MediaColumns.IS_TRASHED, 1) }
        context.contentResolver.update(src.uri, trashed, null, null) == 1
    } catch (_: Exception) {
        false
    }

    private fun publish(src: Source, target: File, replaced: Boolean) {
        try {
            // The file is in place under its name, so the save stands even
            // if the media scan is slow to list it; the library catches up.
            val uri = scan(target)
            if (uri == null) {
                succeed(mapOf("id" to "", "name" to target.name, "replaced" to replaced))
                return
            }
            if (src.favourite) {
                // A favourite stays one; best effort.
                try {
                    val fav = ContentValues().apply { put(MediaStore.MediaColumns.IS_FAVORITE, 1) }
                    context.contentResolver.update(uri, fav, null, null)
                } catch (_: Exception) {
                }
            }
            succeed(mapOf("id" to ContentUris.parseId(uri).toString(), "name" to target.name, "replaced" to replaced))
        } catch (e: Exception) {
            fail(e)
        }
    }

    private fun scan(file: File): Uri? {
        val latch = CountDownLatch(1)
        var found: Uri? = null
        MediaScannerConnection.scanFile(context, arrayOf(file.path), null) { _, uri ->
            found = uri
            latch.countDown()
        }
        latch.await(30, TimeUnit.SECONDS)
        return found
    }

    private fun succeed(value: Map<String, Any?>) = main.post {
        if (finished) return@post
        finished = true
        reply?.invoke(Result.success(value))
    }

    private fun fail(e: Exception) {
        main.post {
            if (finished) return@post
            finished = true
            transformer?.cancel()
            transformer = null
            // Only an unnamed encode is removed; once named, the edit stays.
            val t = temp
            temp = null
            if (t != null) io.execute { t.delete() }
            reply?.invoke(Result.failure(e))
        }
    }

    /**
     * Removes temp files a save left in [dir] more than a day ago, as one
     * cut short by the app being closed. A recent one may belong to a save
     * still finishing, so it stays.
     */
    private fun clearStale(dir: File) {
        val dayAgo = System.currentTimeMillis() - 24L * 60 * 60 * 1000
        dir.listFiles { f -> f.isFile && staleTemp.matches(f.name) && f.lastModified() < dayAgo }
            ?.forEach { it.delete() }
    }

    companion object {
        private val editedSuffix = Regex(""" \(edited(?: \d+)?\)$""")

        /** The hidden file a save encodes into: ".Trip.fotos-1794628184720.mp4". */
        private val staleTemp = Regex("""^\..*\.fotos-\d+\.mp4$""")

        /**
         * "Trip.mp4" -> "Trip (edited).mp4", then "Trip (edited 2).mp4" and
         * on; an edit of an edit counts on rather than adding another
         * "(edited)".
         */
        fun copyName(original: File): String {
            val base = original.nameWithoutExtension.replace(editedSuffix, "")
            val dir = original.parentFile
            var n = 1
            while (true) {
                val name = if (n == 1) "$base (edited).mp4" else "$base (edited $n).mp4"
                if (dir == null || !File(dir, name).exists()) return name
                n++
            }
        }

        /** The original's own name, as an MP4: the encode is always MP4. */
        fun replaceName(original: File): String =
            if (original.extension.equals("mp4", ignoreCase = true)) original.name else "${original.nameWithoutExtension}.mp4"

        /**
         * Media3's [progress] for a save of parts [lengths] long, as a share
         * of the whole time to encode.
         *
         * Media3 gives every part an equal share of the progress however long
         * it is (SequenceAssetLoader.getProgress in 1.9.2: the parts finished,
         * times 100 over their count, plus the current part's percent over the
         * count). A cut that left half a second before it made a save jump to
         * 50% at once and then crawl through the remaining 54 minutes.
         */
        fun byLength(progress: Int, lengths: List<Long>): Int {
            val n = lengths.size
            if (n <= 1 || progress >= 100) return progress
            val total = lengths.sum()
            if (total <= 0) return progress
            val index = minOf(n - 1, progress * n / 100)
            val within = ((progress - index * 100 / n) * n).coerceIn(0, 100)
            val done = lengths.take(index).sum()
            val share = (done + lengths[index] * within / 100.0) / total
            return kotlin.math.floor(share * 100).toInt().coerceIn(0, 99)
        }
    }
}
