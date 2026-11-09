package my.minned.fotos

import android.content.ContentValues
import android.content.Context
import android.media.ExifInterface
import android.net.Uri
import android.os.StatFs
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipFile

/**
 * Copies every photo and video in a Google Takeout ZIP into MediaStore with
 * its real date, skipping exact duplicates and setting aside anything that
 * might be one for the user to decide.
 *
 * Two passes over the archive, because a sidecar JSON is not guaranteed to
 * sit next to its media: the first reads only the small sidecars, the second
 * streams each media file. Finished entries are recorded, so a crash or a
 * killed app resumes where it stopped.
 */
class TakeoutImporter(
    private val context: Context,
    private val progress: (Map<String, Any?>) -> Unit,
) {
    @Volatile var cancelled = false

    private val mediaExtensions = setOf(
        "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "dng", "bmp", "avif",
        "mp4", "mov", "m4v", "3gp", "mkv", "webm", "avi", "mp",
    )

    private val counts = mutableMapOf(
        "imported" to 0, "duplicates" to 0, "review" to 0, "locked" to 0, "failed" to 0,
    )

    fun run(zipPath: String): Map<String, Any?> {
        val zipFile = File(zipPath)
        val key = "${zipFile.name}-${zipFile.length()}"
        val doneFile = File(stateDir(context), "$key.done")
        val done = if (doneFile.exists()) doneFile.readLines().toMutableSet() else mutableSetOf()
        restoreCounts(key)

        ZipFile(zipFile).use { zip ->
            val entries = zip.entries().toList().filter { !it.isDirectory }
            val sidecars = readSidecars(zip, entries)
            val media = entries.filter { isMedia(it.name) }
            val remaining = media.filter { it.name !in done }

            val needed = remaining.sumOf { maxOf(it.size, 0L) }
            val free = StatFs(context.getExternalFilesDir(null)!!.path).availableBytes
            if (needed > free) throw IllegalStateException("not_enough_space:$needed")

            media.forEachIndexed { i, entry ->
                if (cancelled) return summary(key, media.size, i, cancelled = true)
                if (entry.name in done) return@forEachIndexed
                report(i, media.size, entry.name)
                val outcome = try {
                    importEntry(zip, entry, sidecars, key)
                } catch (e: Exception) {
                    "failed"
                }
                counts[outcome] = counts.getValue(outcome) + 1
                done.add(entry.name)
                doneFile.appendText(entry.name + "\n")
                saveCounts(key)
            }
            return summary(key, media.size, media.size, cancelled = false)
        }
    }

    private fun report(i: Int, total: Int, name: String) {
        progress(counts + mapOf("done" to i, "total" to total, "current" to name.substringAfterLast('/')))
    }

    private fun summary(key: String, total: Int, done: Int, cancelled: Boolean): Map<String, Any?> =
        counts + mapOf("total" to total, "done" to done, "cancelled" to cancelled, "key" to key)

    // ---- pass 1: sidecars -------------------------------------------------

    /** dir/originalTitle -> taken time in ms. */
    private fun readSidecars(zip: ZipFile, entries: List<ZipEntry>): Map<String, Long> {
        val out = mutableMapOf<String, Long>()
        for (e in entries) {
            if (!e.name.endsWith(".json") || e.size > 1_000_000) continue
            try {
                val json = JSONObject(zip.getInputStream(e).bufferedReader().use { it.readText() })
                val title = json.optString("title").takeIf { it.isNotEmpty() } ?: continue
                val ts = json.optJSONObject("photoTakenTime")?.optString("timestamp")?.toLongOrNull()
                    ?: continue
                out["${e.name.substringBeforeLast('/')}/$title"] = ts * 1000
            } catch (_: Exception) {
                // Album metadata and other JSON files are not sidecars.
            }
        }
        return out
    }

    // ---- pass 2: one media file -------------------------------------------

    private fun importEntry(
        zip: ZipFile,
        entry: ZipEntry,
        sidecars: Map<String, Long>,
        key: String,
    ): String {
        if (entry.name.split('/').any { it == "Locked Folder" }) return "locked"

        val dir = entry.name.substringBeforeLast('/')
        val rawName = entry.name.substringAfterLast('/')
        val name = normaliseName(rawName)
        val taken = sidecars["$dir/$rawName"] ?: sidecars["$dir/$name"]
        val mime = mimeOf(name)
        val isVideo = mime.startsWith("video/") || name.endsWith(".MP", ignoreCase = true)

        val temp = File(context.cacheDir, "takeout-current")
        val hash = zip.getInputStream(entry).use { copyHashing(it, temp) }

        try {
            // Pixel Motion Photo video halves: unconfirmed, so the user decides.
            if (rawName.startsWith("PXL_") && rawName.endsWith(".MP", ignoreCase = true)) {
                stage(temp, rawName, name, taken, isVideo, "motion", null, key)
                return "review"
            }
            val match = findMatch(name, taken, temp.length(), hash, isVideo)
            when (match.first) {
                "same" -> return "duplicates"
                "maybe" -> {
                    stage(temp, rawName, name, taken, isVideo, match.third!!, match.second, key)
                    return "review"
                }
            }
            if (taken != null && !isVideo && (mime == "image/jpeg")) writeExifDate(temp, taken)
            insert(temp, name, mime, isVideo, taken, yearFolder(taken, dir))
            return "imported"
        } finally {
            temp.delete()
        }
    }

    /**
     * ("same", id) for identical bytes already on the phone, ("maybe", id,
     * reason) for a same-name or same-time item with different bytes, or
     * ("none") when nothing on the phone resembles it.
     */
    private fun findMatch(
        name: String,
        taken: Long?,
        size: Long,
        hash: String,
        isVideo: Boolean,
    ): Triple<String, String?, String?> {
        val resolver = context.contentResolver
        val files = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.SIZE,
            MediaStore.Files.FileColumns.MEDIA_TYPE,
        )
        fun candidates(selection: String, args: Array<String>): List<Triple<Long, Long, Int>> {
            val out = mutableListOf<Triple<Long, Long, Int>>()
            resolver.query(files, projection, selection, args, null)?.use { c ->
                while (c.moveToNext()) out.add(Triple(c.getLong(0), c.getLong(1), c.getInt(2)))
            }
            return out
        }
        val byName = candidates(
            "${MediaStore.MediaColumns.DISPLAY_NAME} = ? COLLATE NOCASE",
            arrayOf(name),
        )
        for ((id, s, type) in byName) {
            if (s == size && hashOf(uriFor(id, type)) == hash) return Triple("same", id.toString(), null)
        }
        if (byName.isNotEmpty()) return Triple("maybe", byName.first().first.toString(), "name")

        if (taken != null) {
            val type = if (isVideo) MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
            else MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE
            val byTime = candidates(
                "${MediaStore.MediaColumns.DATE_TAKEN} BETWEEN ? AND ? AND " +
                    "${MediaStore.Files.FileColumns.MEDIA_TYPE} = ?",
                arrayOf((taken - 1000).toString(), (taken + 1000).toString(), type.toString()),
            )
            for ((id, s, t) in byTime) {
                if (s == size && hashOf(uriFor(id, t)) == hash) return Triple("same", id.toString(), null)
            }
            if (byTime.isNotEmpty()) return Triple("maybe", byTime.first().first.toString(), "time")
        }
        return Triple("none", null, null)
    }

    private fun uriFor(id: Long, mediaType: Int): Uri {
        val base = if (mediaType == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO) {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        return Uri.withAppendedPath(base, id.toString())
    }

    private fun hashOf(uri: Uri): String? = try {
        context.contentResolver.openInputStream(uri)?.use { sha256(it) }
    } catch (_: Exception) {
        null
    }

    // ---- writing ----------------------------------------------------------

    private fun insert(file: File, name: String, mime: String, isVideo: Boolean, taken: Long?, year: Int): Uri {
        val resolver = context.contentResolver
        val collection = if (isVideo) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(
                MediaStore.MediaColumns.RELATIVE_PATH,
                "${if (isVideo) "Movies" else "Pictures"}/Takeout/$year",
            )
            put(MediaStore.MediaColumns.IS_PENDING, 1)
            taken?.let { put(MediaStore.MediaColumns.DATE_TAKEN, it) }
        }
        val uri = resolver.insert(collection, values) ?: throw IllegalStateException("insert_failed")
        try {
            resolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) } }
                ?: throw IllegalStateException("open_failed")
            val publish = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
                // Set again after publishing, in case the media scan replaced it.
                taken?.let { put(MediaStore.MediaColumns.DATE_TAKEN, it) }
            }
            resolver.update(uri, publish, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        return uri
    }

    /** Only when the photo has no capture date of its own. */
    private fun writeExifDate(file: File, taken: Long) {
        try {
            val exif = ExifInterface(file.path)
            if (exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL) != null) return
            val stamp = SimpleDateFormat("yyyy:MM:dd HH:mm:ss", Locale.US).format(taken)
            exif.setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL, stamp)
            exif.setAttribute(ExifInterface.TAG_DATETIME, stamp)
            exif.saveAttributes()
        } catch (_: Exception) {
            // DATE_TAKEN in MediaStore still carries the date.
        }
    }

    // ---- review staging ---------------------------------------------------

    private fun stage(
        file: File,
        rawName: String,
        name: String,
        taken: Long?,
        isVideo: Boolean,
        reason: String,
        phoneId: String?,
        key: String,
    ) {
        val dir = File(reviewDir(context), key).apply { mkdirs() }
        val id = "${System.currentTimeMillis()}-${rawName.hashCode().toUInt()}"
        val staged = File(dir, "$id-$rawName")
        file.copyTo(staged, overwrite = true)
        val item = JSONObject()
            .put("id", id)
            .put("path", staged.path)
            .put("name", name)
            .put("taken", taken ?: JSONObject.NULL)
            .put("video", isVideo)
            .put("mime", mimeOf(name))
            .put("reason", reason)
            .put("phoneId", phoneId ?: JSONObject.NULL)
            .put("size", staged.length())
        synchronized(TakeoutImporter::class.java) {
            val all = readReviews(context)
            all.put(item)
            reviewsFile(context).writeText(all.toString())
        }
    }

    // ---- small helpers ----------------------------------------------------

    private fun restoreCounts(key: String) {
        val f = File(stateDir(context), "$key.counts")
        if (!f.exists()) return
        val json = JSONObject(f.readText())
        for (k in counts.keys.toList()) counts[k] = json.optInt(k, 0)
    }

    private fun saveCounts(key: String) {
        File(stateDir(context), "$key.counts").writeText(JSONObject(counts as Map<*, *>).toString())
    }

    private fun isMedia(path: String): Boolean =
        path.substringAfterLast('.', "").lowercase() in mediaExtensions

    private fun yearFolder(taken: Long?, dir: String): Int {
        if (taken != null) return Calendar.getInstance().apply { timeInMillis = taken }.get(Calendar.YEAR)
        Regex("Photos from (\\d{4})").find(dir)?.let { return it.groupValues[1].toInt() }
        return Calendar.getInstance().get(Calendar.YEAR)
    }

    private fun copyHashing(input: InputStream, to: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        to.outputStream().use { out ->
            val buf = ByteArray(1 shl 16)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                digest.update(buf, 0, n)
                out.write(buf, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    companion object {
        /** "IMG_0300 (1).MOV" -> "IMG_0300.MOV": Takeout's clash suffix. */
        fun normaliseName(name: String): String =
            Regex("^(.*) \\(\\d+\\)(\\.[^.]+)$").replace(name, "$1$2")

        fun mimeOf(name: String): String {
            val ext = name.substringAfterLast('.', "").lowercase()
            return when (ext) {
                "mp" -> "video/mp4"
                "heic" -> "image/heic"
                "heif" -> "image/heif"
                else -> MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
            }
        }

        fun sha256(input: InputStream): String {
            val digest = MessageDigest.getInstance("SHA-256")
            val buf = ByteArray(1 shl 16)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                digest.update(buf, 0, n)
            }
            return digest.digest().joinToString("") { "%02x".format(it) }
        }

        fun stateDir(context: Context) = File(context.filesDir, "takeout").apply { mkdirs() }

        fun reviewDir(context: Context) =
            File(context.getExternalFilesDir(null), "takeout_review").apply { mkdirs() }

        fun reviewsFile(context: Context) = File(stateDir(context), "reviews.json")

        fun readReviews(context: Context): JSONArray {
            val f = reviewsFile(context)
            return if (f.exists()) JSONArray(f.readText()) else JSONArray()
        }

        /** Keep the Takeout copy: publish the staged file like any import. */
        fun publishStaged(context: Context, item: JSONObject) {
            val file = File(item.getString("path"))
            val importer = TakeoutImporter(context) {}
            val taken = if (item.isNull("taken")) null else item.getLong("taken")
            importer.insert(
                file,
                item.getString("name"),
                item.getString("mime"),
                item.getBoolean("video"),
                taken,
                importer.yearFolder(taken, ""),
            )
        }

        /** Removes a review item and its staged file. */
        fun dropReview(context: Context, id: String) {
            synchronized(TakeoutImporter::class.java) {
                val all = readReviews(context)
                val kept = JSONArray()
                for (i in 0 until all.length()) {
                    val o = all.getJSONObject(i)
                    if (o.getString("id") == id) File(o.getString("path")).delete() else kept.put(o)
                }
                reviewsFile(context).writeText(kept.toString())
            }
        }

        fun findReview(context: Context, id: String): JSONObject? {
            val all = readReviews(context)
            for (i in 0 until all.length()) {
                val o = all.getJSONObject(i)
                if (o.getString("id") == id) return o
            }
            return null
        }
    }
}
