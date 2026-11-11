package my.minned.fotos

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.os.StatFs
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.zip.ZipFile

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

    /** A frame from the video at [path] as a JPEG about [px] across, or null. */
    fun videoFrame(path: String, px: Int): ByteArray? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val frame = retriever.getScaledFrameAtTime(
                -1, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, px, px,
            ) ?: return null
            ByteArrayOutputStream().also { frame.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
        } catch (_: Exception) {
            null
        } finally {
            retriever.release()
        }
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
