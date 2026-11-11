package my.minned.fotos

import android.content.Context
import android.media.ExifInterface
import android.media.MediaScannerConnection
import android.provider.MediaStore
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Gives imported media a capture date that Android will index.
 *
 * MediaProvider ignores a DATE_TAKEN an app supplies and works the date out
 * from the file when it scans it. Measured on the Pixel 9 Pro (Android 17,
 * 11/11/2026): a photo is dated only when its EXIF has DateTimeOriginal and
 * either an offset tag or a file modified time within a day of that date.
 * Imported files were written "now", so photos without the offset tag came
 * out undated however their date had been supplied. Writing the EXIF date
 * where it is missing, setting the file's modified time to the capture time
 * and rescanning is what makes the date stick.
 *
 * A Takeout export is split across ZIPs and a photo's sidecar is often in a
 * different part from the photo, so every sidecar date seen is remembered
 * and applied to undated imports whenever a later part brings it.
 */
object TakeoutDates {
    private const val EXIF_FORMAT = "yyyy:MM:dd HH:mm:ss"

    private fun datesFile(context: Context) = File(TakeoutImporter.stateDir(context), "sidecar-dates.tsv")

    /** Every sidecar date seen so far: "dir/title" -> taken, in ms. */
    fun known(context: Context): MutableMap<String, Long> {
        val out = mutableMapOf<String, Long>()
        val f = datesFile(context)
        if (!f.exists()) return out
        f.forEachLine { line ->
            val tab = line.lastIndexOf('\t')
            if (tab > 0) line.substring(tab + 1).toLongOrNull()?.let { out[line.substring(0, tab)] = it }
        }
        return out
    }

    /** Adds [sidecars] to the remembered dates and returns all of them. */
    fun remember(context: Context, sidecars: Map<String, Long>): Map<String, Long> {
        val all = known(context)
        val fresh = sidecars.filter { all[it.key] != it.value }
        if (fresh.isNotEmpty()) {
            all.putAll(fresh)
            datesFile(context).writeText(all.entries.joinToString("\n") { "${it.key}\t${it.value}" })
        }
        return all
    }

    /** The date a file carries itself: its EXIF, else its name. */
    fun dateFor(file: File, name: String): Long? = exifDate(file) ?: dateInName(name)

    private fun exifDate(file: File): Long? = try {
        val exif = ExifInterface(file.path)
        val stamp = exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)
        if (stamp == null) {
            null
        } else {
            val offset = exif.getAttribute(ExifInterface.TAG_OFFSET_TIME_ORIGINAL)
            val format = SimpleDateFormat(EXIF_FORMAT, Locale.US)
            if (offset != null) format.timeZone = TimeZone.getTimeZone("GMT$offset")
            format.parse(stamp)?.time?.takeIf { it > 0 }
        }
    } catch (_: Exception) {
        null
    }

    /**
     * Camera and messenger apps put the date in the name: "20220115_094620",
     * "IMG_20180713_162830_125", "PXL_20261108_142020445" (Pixel names are in
     * UTC), and "IMG-20180720-WA0010", which has a day but no time and is
     * placed at midday.
     */
    fun dateInName(name: String): Long? {
        val full = Regex("(?<!\\d)(20\\d{2})(\\d{2})(\\d{2})[_-](\\d{2})(\\d{2})(\\d{2})").find(name)
        val day = Regex("(?<!\\d)(20\\d{2})(\\d{2})(\\d{2})(?!\\d)").find(name)
        val digits = (full ?: day ?: return null).groupValues.drop(1).map { it.toInt() }
        val (y, mo, d) = digits
        val (h, mi, s) = if (full != null) digits.drop(3) else listOf(12, 0, 0)
        if (mo !in 1..12 || d !in 1..31 || h > 23 || mi > 59 || s > 59) return null
        val format = SimpleDateFormat(EXIF_FORMAT, Locale.US)
        format.isLenient = false
        if (name.startsWith("PXL_")) format.timeZone = TimeZone.getTimeZone("UTC")
        return try {
            format.parse("%04d:%02d:%02d %02d:%02d:%02d".format(y, mo, d, h, mi, s))?.time
        } catch (_: Exception) {
            null
        }
    }

    /** Writes the date into a photo that has none of its own. */
    fun writeExifDate(file: File, taken: Long) {
        try {
            val exif = ExifInterface(file.path)
            if (exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL) != null) return
            val stamp = SimpleDateFormat(EXIF_FORMAT, Locale.US).format(taken)
            exif.setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL, stamp)
            exif.setAttribute(ExifInterface.TAG_DATETIME, stamp)
            exif.saveAttributes()
        } catch (_: Exception) {
            // Not a format EXIF can be written to; the modified time still
            // carries the date.
        }
    }

    /**
     * Dates every imported item Android has left undated, from a remembered
     * sidecar, else the file's own EXIF, else its name. Returns how many
     * were given a date ("fixed") and how many have none anywhere ("left").
     */
    fun repair(context: Context): Map<String, Int> {
        // Imports are known by file name here, not by their folder in the
        // ZIP. A name with two different dates could be either, so skip it.
        val byName = mutableMapOf<String, Long?>()
        for ((key, taken) in known(context)) {
            val name = TakeoutImporter.normaliseName(key.substringAfterLast('/'))
            byName[name] = if (name in byName && byName[name] != taken) null else taken
        }

        val stamped = mutableListOf<String>()
        var left = 0
        val projection = arrayOf(
            MediaStore.MediaColumns.DATA,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.MIME_TYPE,
        )
        context.contentResolver.query(
            MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            projection,
            "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ? AND " +
                "(${MediaStore.MediaColumns.DATE_TAKEN} IS NULL OR ${MediaStore.MediaColumns.DATE_TAKEN} = 0) AND " +
                "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (?, ?)",
            arrayOf(
                "%/Takeout/%",
                MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString(),
                MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString(),
            ),
            null,
        )?.use { c ->
            while (c.moveToNext()) {
                val file = File(c.getString(0) ?: continue)
                val name = c.getString(1) ?: file.name
                val taken = byName[name] ?: dateFor(file, name)
                if (taken == null || !file.exists()) {
                    left++
                    continue
                }
                // A video takes its date from its own metadata; only its
                // modified time can be set from here.
                if (c.getString(2)?.startsWith("image/") == true) writeExifDate(file, taken)
                if (file.setLastModified(taken)) stamped.add(file.path) else left++
            }
        }
        rescan(context, stamped)
        return mapOf("fixed" to stamped.size, "left" to left)
    }

    /** Has Android read the files again, and waits until it has. */
    private fun rescan(context: Context, paths: List<String>) {
        if (paths.isEmpty()) return
        val pending = CountDownLatch(paths.size)
        MediaScannerConnection.scanFile(context, paths.toTypedArray(), null) { _, _ -> pending.countDown() }
        pending.await(2L * paths.size + 30, TimeUnit.SECONDS)
    }
}
