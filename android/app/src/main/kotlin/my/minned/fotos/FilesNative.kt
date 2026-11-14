package my.minned.fotos

import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.ImageDecoder
import android.graphics.pdf.PdfRenderer
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.os.StatFs
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

/** File-manager work for the Files tab. Needs All files access. */
object FilesNative {
    fun root(): String = Environment.getExternalStorageDirectory().absolutePath

    fun hasAllFilesAccess(): Boolean = Environment.isExternalStorageManager()

    fun openAllFilesAccessSettings(activity: Activity) {
        val intent = Intent(
            Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
            Uri.parse("package:${activity.packageName}"),
        )
        activity.startActivity(intent)
    }

    fun storage(): Map<String, Long> {
        val s = StatFs(Environment.getExternalStorageDirectory().absolutePath)
        return mapOf("total" to s.totalBytes, "free" to s.availableBytes)
    }

    /**
     * Tells MediaStore about files fotos created, renamed or deleted, so they
     * appear in (or leave) Photos, Videos and Albums straight away. Waits for
     * the scanner so the caller can refresh afterwards.
     */
    fun scan(activity: Activity, paths: List<String>) {
        if (paths.isEmpty()) return
        val latch = CountDownLatch(paths.size)
        MediaScannerConnection.scanFile(activity, paths.toTypedArray(), null) { _, _ ->
            latch.countDown()
        }
        latch.await(30, TimeUnit.SECONDS)
    }

    fun mimeOf(path: String): String {
        val ext = path.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "*/*"
    }

    /** Android's "Open with" chooser for a file fotos does not open itself. */
    fun openWith(activity: Activity, path: String) {
        val uri = FileProvider.getUriForFile(
            activity,
            "${activity.packageName}.files",
            File(path),
        )
        val view = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, mimeOf(path))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        activity.startActivity(Intent.createChooser(view, null))
    }

    fun zipInfo(path: String): Map<String, Any> {
        ZipFile(path).use { zip ->
            var files = 0
            var bytes = 0L
            var takeout = false
            for (e in zip.entries()) {
                if (e.isDirectory) continue
                files++
                if (e.size > 0) bytes += e.size
                if (e.name.startsWith("Takeout/")) takeout = true
            }
            return mapOf("files" to files, "bytes" to bytes, "takeout" to takeout)
        }
    }

    /**
     * A picture from inside the ZIP at [path], as a JPEG about [px] across,
     * to stand for the archive in a list: the first image by name, which for
     * a comic is its cover or first page. Null when the ZIP holds no image
     * Android can decode.
     */
    fun zipCover(path: String, px: Int): ByteArray? = try {
        ZipFile(path).use { zip ->
            val entry = pages(zip).minByOrNull { it.name.lowercase() } ?: return@use null
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            zip.getInputStream(entry).use { BitmapFactory.decodeStream(it, null, bounds) }
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return@use null
            // Decode at a fraction of the page's size: a cover is drawn small.
            var sample = 1
            while (minOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= px) sample *= 2
            val options = BitmapFactory.Options().apply { inSampleSize = sample }
            val bitmap = zip.getInputStream(entry).use { BitmapFactory.decodeStream(it, null, options) }
                ?: return@use null
            ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
        }
    } catch (_: Exception) {
        null
    }

    private val pictureTypes = setOf("jpg", "jpeg", "png", "webp", "gif", "bmp", "heic", "avif")

    /**
     * The pictures in [zip] that count as pages: skips macOS resource forks
     * and anything too large to be a page.
     */
    private fun pages(zip: ZipFile): Sequence<ZipEntry> = zip.entries().asSequence().filter {
        !it.isDirectory &&
            !it.name.startsWith("__MACOSX/") &&
            it.name.substringAfterLast('.', "").lowercase() in pictureTypes &&
            it.size in 1..40_000_000
    }

    /**
     * How many pages the ZIP at [path] holds when it reads as a comic, or
     * null when it doesn't: a comic is pictures but for a few extras such as
     * ComicInfo.xml, while a Takeout or backup ZIP is full of other files.
     * Reads only the archive's index.
     */
    fun zipPageCount(path: String): Int? = try {
        ZipFile(path).use { zip ->
            val pictures = pages(zip).count()
            val others = zip.entries().asSequence().count {
                !it.isDirectory && !it.name.startsWith("__MACOSX/")
            } - pictures
            pictures.takeIf { it > 0 && others <= maxOf(3, it / 10) }
        }
    } catch (_: Exception) {
        null
    }

    /**
     * Extracts [zipPath] into [targetDir], reporting progress after each file.
     * Entries that would land outside the target (a "zip slip") are skipped.
     * Returns the paths written.
     */
    fun extract(
        zipPath: String,
        targetDir: String,
        progress: (done: Int, total: Int) -> Unit,
    ): List<String> {
        val target = File(targetDir).canonicalFile
        val written = mutableListOf<String>()
        ZipFile(zipPath).use { zip ->
            val entries = zip.entries().toList().filter { !it.isDirectory }
            val needed = entries.sumOf { maxOf(it.size, 0L) }
            if (needed > StatFs(target.parentFile?.path ?: targetDir).availableBytes) {
                throw IllegalStateException("not_enough_space:$needed")
            }
            target.mkdirs()
            entries.forEachIndexed { i, e ->
                val out = File(target, e.name).canonicalFile
                if (!out.path.startsWith(target.path + File.separator)) return@forEachIndexed
                out.parentFile?.mkdirs()
                zip.getInputStream(e).use { input ->
                    out.outputStream().use { input.copyTo(it) }
                }
                if (e.time > 0) out.setLastModified(e.time)
                written.add(out.path)
                progress(i + 1, entries.size)
            }
        }
        return written
    }

    /**
     * The non-directory entries of the ZIP at [path]: each entry's name, its
     * uncompressed size, and whether it is an image Android can likely show.
     * Skips macOS resource forks, as [zipCover] does.
     */
    fun zipEntries(path: String): List<Map<String, Any>> {
        ZipFile(path).use { zip ->
            return zip.entries().asSequence()
                .filter { !it.isDirectory && !it.name.startsWith("__MACOSX/") }
                .map { e ->
                    mapOf(
                        "name" to e.name,
                        "size" to maxOf(e.size, 0L),
                        "isImage" to (e.name.substringAfterLast('.', "").lowercase() in pictureTypes),
                    )
                }
                .toList()
        }
    }

    /**
     * A thumbnail for the entry [name] inside the ZIP at [path], a JPEG about
     * [px] across, or null when it is not an image Android can decode. Decodes
     * at a fraction of the page's size, like [zipCover].
     */
    fun zipPageThumb(path: String, name: String, px: Int): ByteArray? = try {
        ZipFile(path).use { zip ->
            val entry = zip.getEntry(name) ?: return@use null
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            zip.getInputStream(entry).use { BitmapFactory.decodeStream(it, null, bounds) }
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return@use null
            var sample = 1
            while (minOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= px) sample *= 2
            val options = BitmapFactory.Options().apply { inSampleSize = sample }
            val bitmap = zip.getInputStream(entry).use {
                BitmapFactory.decodeStream(it, null, options)
            } ?: return@use null
            ByteArrayOutputStream().also {
                bitmap.compress(Bitmap.CompressFormat.JPEG, 80, it)
            }.toByteArray()
        }
    } catch (_: Exception) {
        null
    }

    /**
     * Rewrites the ZIP at [path] without the entries named in [names], to a
     * temp file in the same folder that then atomically replaces the original.
     * Pictures go in stored as they are, without a second round of
     * compression; see [storesAsIs].
     * An interrupted run leaves the archive untouched. Reports progress after
     * each kept entry, and returns how many files remain inside. Throws with
     * "not_enough_space:<bytes>" before writing anything when the disk is full.
     */
    fun zipRemove(
        path: String,
        names: Set<String>,
        progress: (done: Int, total: Int) -> Unit,
    ): Int {
        val source = File(path)
        val dir = source.parentFile ?: throw IllegalStateException("no_parent")
        val tmp = File.createTempFile("ziprm", ".tmp", dir)
        var files = 0
        try {
            ZipFile(path).use { zip ->
                val keepers = zip.entries().toList().filter { it.name !in names }
                val need = keepers.sumOf {
                    when {
                        storesAsIs(it) -> it.size
                        it.compressedSize >= 0 -> it.compressedSize
                        else -> maxOf(it.size, 0L)
                    }
                }
                if (need > StatFs(dir.path).availableBytes) {
                    throw IllegalStateException("not_enough_space:$need")
                }
                ZipOutputStream(BufferedOutputStream(tmp.outputStream())).use { out ->
                    keepers.forEachIndexed { i, e ->
                        out.putNextEntry(
                            ZipEntry(e.name).apply {
                                time = e.time
                                if (storesAsIs(e)) {
                                    method = ZipEntry.STORED
                                    size = e.size
                                    compressedSize = e.size
                                    crc = e.crc
                                }
                            },
                        )
                        if (!e.isDirectory) {
                            zip.getInputStream(e).use { it.copyTo(out) }
                            files++
                        }
                        out.closeEntry()
                        progress(i + 1, keepers.size)
                    }
                }
            }
            try {
                Files.move(
                    tmp.toPath(), source.toPath(),
                    StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE,
                )
            } catch (_: Exception) {
                // Atomic move may be unsupported on some volumes; replace plainly.
                Files.move(tmp.toPath(), source.toPath(), StandardCopyOption.REPLACE_EXISTING)
            }
        } catch (e: Exception) {
            tmp.delete()
            throw e
        }
        return files
    }

    /** Picture formats that are compressed already; zipping them again saves little. */
    private val alreadyCompressed = setOf("jpg", "jpeg", "png", "webp", "gif", "avif", "heic", "heif")

    /**
     * Whether a kept ZIP entry goes into the rewritten archive stored as it
     * is rather than compressed a second time: a picture, whose size and
     * checksum the archive records (a stored entry needs both up front).
     * Anything else, such as text, is still compressed.
     */
    private fun storesAsIs(e: ZipEntry): Boolean =
        !e.isDirectory && e.size >= 0 && e.crc >= 0 &&
            e.name.substringAfterLast('.', "").lowercase() in alreadyCompressed

    /** A frame from the video at [path] as a JPEG about [px] across, or null. */
    fun videoFrame(path: String, px: Int): ByteArray? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            frameAt(retriever, -1, px)
        } catch (_: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    /**
     * [count] frames spread evenly through the video at [path], each a JPEG
     * about [px] across, or null where one can't be read. Each is the
     * keyframe nearest its slot. Four readers share the slots, as Glide's
     * four decode threads did: reading them one after another took over
     * three seconds on a 500 MB 1080p file.
     */
    fun videoFrames(path: String, count: Int, px: Int): List<ByteArray?> {
        val frames = arrayOfNulls<ByteArray>(count)
        val readers = minOf(4, count)
        val pool = Executors.newFixedThreadPool(readers)
        try {
            (0 until readers).map { r ->
                pool.submit {
                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(path)
                        val ms = retriever.extractMetadata(
                            MediaMetadataRetriever.METADATA_KEY_DURATION,
                        )?.toLongOrNull() ?: 0L
                        for (i in r until count step readers) {
                            val us = (ms * 1000.0 * (i + 0.5) / count).toLong()
                            frames[i] = try {
                                frameAt(retriever, us, px)
                            } catch (_: Exception) {
                                null
                            }
                        }
                    } catch (_: Exception) {
                        // This reader's slots stay empty; the strip shows the
                        // cover there.
                    } finally {
                        retriever.release()
                    }
                }
            }.forEach { it.get() }
        } finally {
            pool.shutdown()
        }
        return frames.toList()
    }

    /**
     * Frames of the video at [path] at each of [times] (ms), as JPEGs about
     * [px] across, null where one can't be read: the editor's timeline asks
     * for the stretch on screen at its current zoom. The nearest keyframe
     * stands in for each moment, which is quick and close enough for a
     * thumbnail.
     */
    fun videoFramesAt(path: String, times: List<Long>, px: Int): List<ByteArray?> {
        val frames = arrayOfNulls<ByteArray>(times.size)
        val readers = minOf(3, times.size)
        if (readers == 0) return emptyList()
        val pool = Executors.newFixedThreadPool(readers)
        try {
            (0 until readers).map { r ->
                pool.submit {
                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(path)
                        for (i in r until times.size step readers) {
                            frames[i] = try {
                                frameAt(retriever, times[i] * 1000, px)
                            } catch (_: Exception) {
                                null
                            }
                        }
                    } catch (_: Exception) {
                        // This reader's frames stay empty; the timeline keeps
                        // showing its nearest neighbours there.
                    } finally {
                        retriever.release()
                    }
                }
            }.forEach { it.get() }
        } finally {
            pool.shutdown()
        }
        return frames.toList()
    }

    /**
     * A picture or video file's thumbnail as a JPEG about [px] across, or
     * null. Android keeps its own thumbnails for every file MediaStore
     * knows, as the Photos tab uses; decoding the original instead read
     * every byte of 4 to 20 MB camera files for a tile 120 points wide.
     * A file MediaStore doesn't know is decoded at about that size.
     */
    fun thumbnail(context: Context, path: String, px: Int): ByteArray? {
        val bitmap = storeThumbnail(context, path, px) ?: decodeSmall(path, px) ?: return null
        return ByteArrayOutputStream()
            .also { bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it) }
            .toByteArray()
    }

    private fun storeThumbnail(context: Context, path: String, px: Int): Bitmap? {
        val files = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
        val columns = arrayOf(MediaStore.Files.FileColumns._ID, MediaStore.Files.FileColumns.MEDIA_TYPE)
        @Suppress("DEPRECATION") // DATA is still the only way to look a path up.
        val where = "${MediaStore.MediaColumns.DATA}=?"
        context.contentResolver.query(files, columns, where, arrayOf(path), null)?.use { c ->
            if (!c.moveToFirst()) return null
            val base = when (c.getInt(1)) {
                MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE ->
                    MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
                MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO ->
                    MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
                else -> return null
            }
            return try {
                context.contentResolver.loadThumbnail(
                    ContentUris.withAppendedId(base, c.getLong(0)), Size(px, px), null,
                )
            } catch (_: Exception) {
                null
            }
        }
        return null
    }

    private fun decodeSmall(path: String, px: Int): Bitmap? = try {
        ImageDecoder.decodeBitmap(ImageDecoder.createSource(File(path))) { decoder, info, _ ->
            val shorter = minOf(info.size.width, info.size.height)
            decoder.setTargetSampleSize(maxOf(1, shorter / px))
        }
    } catch (_: Exception) {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            retriever.getScaledFrameAtTime(-1, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, px, px)
        } catch (_: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    private fun frameAt(retriever: MediaMetadataRetriever, us: Long, px: Int): ByteArray? {
        val frame = retriever.getScaledFrameAtTime(
            us, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, px, px,
        ) ?: return null
        return ByteArrayOutputStream()
            .also { frame.compress(Bitmap.CompressFormat.JPEG, 80, it) }
            .toByteArray()
    }

    fun pdfPageCount(path: String): Int =
        ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
            PdfRenderer(fd).use { it.pageCount }
        }

    /** One page as a PNG [width] pixels wide, on white like paper. */
    fun pdfPage(path: String, index: Int, width: Int): ByteArray =
        ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
            PdfRenderer(fd).use { renderer ->
                renderer.openPage(index).use { page ->
                    val height = (width.toDouble() * page.height / page.width).toInt()
                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    bitmap.eraseColor(Color.WHITE)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    val bytes = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes)
                    bitmap.recycle()
                    bytes.toByteArray()
                }
            }
        }
}
