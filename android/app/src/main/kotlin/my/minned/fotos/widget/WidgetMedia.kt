package my.minned.fotos.widget

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.provider.BaseColumns
import android.provider.MediaStore
import android.provider.MediaStore.Files.FileColumns as F
import android.provider.MediaStore.MediaColumns as M
import java.util.Calendar

/** One picture the widget can show. */
data class WidgetItem(
    val id: Long,
    val video: Boolean,
    val taken: Long,
    val album: String,
    val name: String,
    val durationMs: Long,
) {
    val uri: Uri
        get() = ContentUris.withAppendedId(
            if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            id,
        )

    /** Pixel Motion Photos, as the grid marks them: by name. */
    val motion: Boolean
        get() = !video && Regex("(?i)(\\.mp\\.(jpe?g|heic)$)|(^mvimg_.*\\.(jpe?g|heic)$)").containsMatchIn(name)
}

/** Builds the list a widget flips through, in the order its settings ask for. */
object WidgetMedia {
    /** Enough for days of 10-second changes; the list is rebuilt daily. */
    private const val LIMIT = 2000

    /** Shots this close together in one album count as one burst. */
    private const val BURST_MS = 3000L

    fun list(context: Context, c: WidgetConfig, now: Long = System.currentTimeMillis()): List<WidgetItem> {
        val all = query(context, c)
        var items = when (c.source) {
            "day" -> onThisDay(all, now).ifEmpty { all }
            else -> all
        }
        items = dropBursts(items)
        val ordered = when (c.order) {
            "newest" -> items.sortedByDescending { it.taken }
            "years" -> spreadAcrossYears(items)
            else -> items.shuffled()
        }
        return ordered.take(LIMIT)
    }

    private fun query(context: Context, c: WidgetConfig): List<WidgetItem> {
        val where = StringBuilder()
        val args = mutableListOf<String>()
        where.append(
            when (c.show) {
                "videos" -> "${F.MEDIA_TYPE} = ${F.MEDIA_TYPE_VIDEO}"
                "both" -> "${F.MEDIA_TYPE} IN (${F.MEDIA_TYPE_IMAGE}, ${F.MEDIA_TYPE_VIDEO})"
                else -> "${F.MEDIA_TYPE} = ${F.MEDIA_TYPE_IMAGE}"
            },
        )
        fun inList(column: String, ids: List<String>, not: Boolean) {
            if (ids.isEmpty()) return
            where.append(" AND $column ${if (not) "NOT IN" else "IN"} (${ids.joinToString(",") { "?" }})")
            args.addAll(ids)
        }
        when (c.source) {
            "albums" -> if (c.albums.isEmpty()) return emptyList() else inList(M.BUCKET_ID, c.albums, false)
            "favourites" -> { where.append(" AND ${M.IS_FAVORITE} = 1"); inList(M.BUCKET_ID, c.leaveOut, true) }
            else -> inList(M.BUCKET_ID, c.leaveOut, true)
        }
        where.append(" AND ${M.IS_TRASHED} = 0 AND ${M.IS_PENDING} = 0")
        val projection = arrayOf(
            BaseColumns._ID, F.MEDIA_TYPE, M.DATE_TAKEN, M.DATE_ADDED, M.BUCKET_DISPLAY_NAME, M.DISPLAY_NAME, M.DURATION,
        )
        val out = mutableListOf<WidgetItem>()
        context.contentResolver.query(
            MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL),
            projection, where.toString(), args.toTypedArray(), null,
        )?.use { cur ->
            while (cur.moveToNext()) {
                val taken = cur.getLong(2).takeIf { it > 0 } ?: cur.getLong(3) * 1000
                out.add(
                    WidgetItem(
                        id = cur.getLong(0),
                        video = cur.getInt(1) == F.MEDIA_TYPE_VIDEO,
                        taken = taken,
                        album = cur.getString(4) ?: "",
                        name = cur.getString(5) ?: "",
                        durationMs = cur.getLong(6),
                    ),
                )
            }
        }
        return out
    }

    /** Taken on today's date in an earlier year. */
    private fun onThisDay(items: List<WidgetItem>, now: Long): List<WidgetItem> {
        val today = Calendar.getInstance().apply { timeInMillis = now }
        val cal = Calendar.getInstance()
        return items.filter {
            cal.timeInMillis = it.taken
            cal.get(Calendar.DAY_OF_MONTH) == today.get(Calendar.DAY_OF_MONTH) &&
                cal.get(Calendar.MONTH) == today.get(Calendar.MONTH) &&
                cal.get(Calendar.YEAR) < today.get(Calendar.YEAR)
        }
    }

    /** Keeps the first of each run of shots taken seconds apart in one album. */
    private fun dropBursts(items: List<WidgetItem>): List<WidgetItem> {
        val kept = mutableListOf<WidgetItem>()
        val lastByAlbum = HashMap<String, Long>()
        for (it in items.sortedBy { i -> i.taken }) {
            val last = lastByAlbum[it.album]
            if (!it.video && last != null && it.taken - last < BURST_MS) continue
            lastByAlbum[it.album] = it.taken
            kept.add(it)
        }
        return kept
    }

    /** Takes turns between years, each in random order, so every year comes up as often. */
    private fun spreadAcrossYears(items: List<WidgetItem>): List<WidgetItem> {
        val cal = Calendar.getInstance()
        val years = items.groupBy { cal.timeInMillis = it.taken; cal.get(Calendar.YEAR) }
            .values.map { it.shuffled().toMutableList() }.shuffled()
        val out = mutableListOf<WidgetItem>()
        while (years.any { it.isNotEmpty() }) {
            for (y in years) if (y.isNotEmpty()) out.add(y.removeAt(0))
        }
        return out
    }
}
