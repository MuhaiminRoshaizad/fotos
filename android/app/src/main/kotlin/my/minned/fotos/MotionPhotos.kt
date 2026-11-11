package my.minned.fotos

import android.content.Context
import java.io.File
import java.io.RandomAccessFile

/**
 * Finds and extracts the short video inside a Motion Photo.
 *
 * A Motion Photo (Pixel "Top Shot", Samsung "Motion photo") is a JPEG or
 * HEIC with an MP4 appended after the picture. Its XMP says where: the
 * current format lists the file's parts in order as Container items, each
 * with a Semantic and a Length, and the video is the part whose Semantic
 * is "MotionPhoto"; the older format gives GCamera:MicroVideoOffset, the
 * video's length counted back from the end of the file.
 */
object MotionPhotos {
    private const val HEAD = 512 * 1024

    /** Where the video sits in [path]: (offset, length), or null if none. */
    fun locate(path: String): Pair<Long, Long>? = try {
        RandomAccessFile(path, "r").use { file ->
            val size = file.length()
            val head = ByteArray(minOf(HEAD.toLong(), size).toInt())
            file.readFully(head)
            val xmp = String(head, Charsets.ISO_8859_1)
            val fromEnd = lengthFromEnd(xmp) ?: return@use null
            val offset = size - fromEnd.first
            if (offset <= 0 || fromEnd.second <= 0 || offset + fromEnd.second > size) return@use null
            // An MP4 opens with a box size and then "ftyp".
            val box = ByteArray(8)
            file.seek(offset)
            file.readFully(box)
            if (String(box, 4, 4, Charsets.ISO_8859_1) != "ftyp") return@use null
            offset to fromEnd.second
        }
    } catch (_: Exception) {
        null
    }

    /** (bytes from the video's start to the end of the file, video length). */
    private fun lengthFromEnd(xmp: String): Pair<Long, Long>? {
        val items = Regex("<Container:Item\\b[^>]*>").findAll(xmp).map { it.value }.toList()
        val at = items.indexOfFirst { it.contains("Item:Semantic=\"MotionPhoto\"") }
        if (at >= 0) {
            fun attr(item: String, name: String) =
                Regex("Item:$name=\"(\\d+)\"").find(item)?.groupValues?.get(1)?.toLongOrNull() ?: 0L
            val length = attr(items[at], "Length")
            if (length <= 0) return null
            // Anything listed after the video sits between it and the end.
            val after = items.drop(at + 1).sumOf { attr(it, "Length") + attr(it, "Padding") }
            return (length + after) to length
        }
        val micro = Regex("MicroVideoOffset=\"(\\d+)\"").find(xmp)?.groupValues?.get(1)?.toLongOrNull()
        return micro?.takeIf { it > 0 }?.let { it to it }
    }

    /**
     * Copies the video out of [path] into fotos' cache and returns the copy's
     * path, or null when the file is not a Motion Photo. Only the most
     * recent few are kept.
     */
    fun extract(context: Context, path: String): String? {
        val (offset, length) = locate(path) ?: return null
        val source = File(path)
        val dir = File(context.cacheDir, "motion").apply { mkdirs() }
        val out = File(dir, "${source.name.hashCode()}-${source.length()}-${source.lastModified()}.mp4")
        if (out.exists() && out.length() == length) return out.path
        return try {
            RandomAccessFile(source, "r").use { input ->
                input.seek(offset)
                out.outputStream().use { output ->
                    val buffer = ByteArray(1 shl 16)
                    var left = length
                    while (left > 0) {
                        val n = input.read(buffer, 0, minOf(buffer.size.toLong(), left).toInt())
                        if (n < 0) break
                        output.write(buffer, 0, n)
                        left -= n
                    }
                }
            }
            dir.listFiles()?.sortedByDescending { it.lastModified() }?.drop(6)?.forEach { it.delete() }
            out.path
        } catch (_: Exception) {
            out.delete()
            null
        }
    }
}
