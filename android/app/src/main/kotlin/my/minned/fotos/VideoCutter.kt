package my.minned.fotos

import android.app.Activity
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
 *  3. Only then is it given its name. To replace, the original goes to
 *     Android's trash first, with the system's own consent dialog, so it
 *     stays recoverable for 30 days; declined, the edit is kept as a copy.
 *
 * Writing beside the original needs All files access: MediaStore only lets
 * an app create videos in DCIM, Movies and Pictures, and a video from
 * Download or a messaging app must not land anywhere else.
 */
@OptIn(UnstableApi::class)
class VideoCutter(
    private val activity: Activity,
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

    // Set once the encode is checked and saving begins: from there a
    // cancel could strand the original in the trash with no edit to show.
    private var committing = false
    private var reply: ((Result<Map<String, Any?>>) -> Unit)? = null

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
        val (path, taken, favourite) = activity.contentResolver.query(uri, cols, null, null, null)?.use { c ->
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
        val encoders = DefaultEncoderFactory.Builder(activity)
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
        val t = Transformer.Builder(activity)
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
        if (t.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) onProgress(holder.progress)
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

    /** On the main thread: trashes the original if replacing, then names the new file. */
    private fun save(src: Source, out: File, replace: Boolean) {
        if (finished) return
        committing = true
        if (!replace) {
            io.execute { publish(src, out, copyName(src.file), replaced = false) }
            return
        }
        try {
            MediaRequests.trash(activity, listOf(src.id.toString()), listOf(true), true) { ok ->
                io.execute {
                    // A declined trash keeps the original, and the edit
                    // becomes a copy beside it.
                    val name = if (ok) replaceName(src.file) else copyName(src.file)
                    publish(src, out, name, replaced = ok)
                }
            }
        } catch (e: Exception) {
            io.execute { publish(src, out, copyName(src.file), replaced = false) }
        }
    }

    private fun publish(src: Source, out: File, name: String, replaced: Boolean) {
        try {
            // The original's name can still be taken if Android has not
            // moved it to the trash yet; a copy's name is better than
            // failing with the original already gone.
            val wanted = File(out.parentFile, name)
            val target = if (wanted.exists()) File(out.parentFile, copyName(src.file)) else wanted
            if (!out.renameTo(target)) {
                throw CutException("failed", "Could not name the new video ${target.name}")
            }
            temp = null
            val uri = scan(target) ?: throw CutException("failed", "Android did not list the new video")
            if (src.favourite) {
                // A favourite stays one; best effort.
                try {
                    val fav = ContentValues().apply { put(MediaStore.MediaColumns.IS_FAVORITE, 1) }
                    activity.contentResolver.update(uri, fav, null, null)
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
        MediaScannerConnection.scanFile(activity, arrayOf(file.path), null) { _, uri ->
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
            val t = temp
            temp = null
            if (t != null) io.execute { t.delete() }
            reply?.invoke(Result.failure(e))
        }
    }

    companion object {
        private val editedSuffix = Regex(""" \(edited(?: \d+)?\)$""")

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
    }
}
