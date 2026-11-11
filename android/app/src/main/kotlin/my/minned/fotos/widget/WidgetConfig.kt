package my.minned.fotos.widget

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * One photo widget's settings, chosen on its setup screen
 * (lib/features/home_widget) and kept per widget id.
 */
data class WidgetConfig(
    /** "photos", "videos" or "both". */
    val show: String = "photos",
    /** "all", "albums", "favourites" or "day". */
    val source: String = "all",
    /** Bucket ids shown when [source] is "albums". */
    val albums: List<String> = emptyList(),
    /** Bucket ids skipped otherwise. */
    val leaveOut: List<String> = emptyList(),
    /** "shuffle", "years" or "newest". */
    val order: String = "shuffle",
    /** Seconds between pictures: 10, 60, 900 or 3600. */
    val every: Int = 10,
    /** "fill" or "whole". */
    val fit: String = "whole",
    /** "date", "ago", "album" or "none". */
    val caption: String = "date",
    val skip: Boolean = true,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "show" to show, "source" to source, "albums" to albums, "leaveOut" to leaveOut,
        "order" to order, "every" to every, "fit" to fit, "caption" to caption, "skip" to skip,
    )

    private fun toJson(): String = JSONObject().apply {
        put("show", show); put("source", source)
        put("albums", JSONArray(albums)); put("leaveOut", JSONArray(leaveOut))
        put("order", order); put("every", every); put("fit", fit)
        put("caption", caption); put("skip", skip)
    }.toString()

    companion object {
        private const val PREFS = "fotos_widgets"

        fun fromMap(m: Map<*, *>): WidgetConfig {
            fun str(k: String, d: String) = m[k] as? String ?: d
            fun list(k: String) = (m[k] as? List<*>)?.mapNotNull { it as? String } ?: emptyList()
            return WidgetConfig(
                show = str("show", "photos"), source = str("source", "all"),
                albums = list("albums"), leaveOut = list("leaveOut"),
                order = str("order", "shuffle"), every = (m["every"] as? Number)?.toInt() ?: 10,
                fit = str("fit", "whole"), caption = str("caption", "date"),
                skip = m["skip"] as? Boolean ?: true,
            )
        }

        private fun fromJson(s: String): WidgetConfig {
            val o = JSONObject(s)
            fun list(k: String): List<String> {
                val a = o.optJSONArray(k) ?: return emptyList()
                return (0 until a.length()).map { a.getString(it) }
            }
            return WidgetConfig(
                show = o.optString("show", "photos"), source = o.optString("source", "all"),
                albums = list("albums"), leaveOut = list("leaveOut"),
                order = o.optString("order", "shuffle"), every = o.optInt("every", 10),
                fit = o.optString("fit", "whole"), caption = o.optString("caption", "date"),
                skip = o.optBoolean("skip", true),
            )
        }

        fun load(context: Context, id: Int): WidgetConfig? =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("w$id", null)
                ?.let { runCatching { fromJson(it) }.getOrNull() }

        fun save(context: Context, id: Int, config: WidgetConfig) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("w$id", config.toJson()).apply()
        }

        fun delete(context: Context, id: Int) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove("w$id").apply()
        }
    }
}
