package my.minned.fotos.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ImageDecoder
import android.graphics.LightingColorFilter
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.media.MediaMetadataRetriever
import android.util.Size
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import my.minned.fotos.R
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/** Hands a widget its pictures, one at a time, as the home screen asks. */
class FotosWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = Factory(
        applicationContext,
        intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID),
    )

    private class Factory(private val context: Context, private val id: Int) : RemoteViewsFactory {
        private var items: List<WidgetItem> = emptyList()
        private var config = WidgetConfig()

        override fun onCreate() {}
        override fun onDestroy() { items = emptyList() }

        override fun onDataSetChanged() {
            config = WidgetConfig.load(context, id) ?: WidgetConfig()
            items = runCatching { WidgetMedia.list(context, config) }.getOrDefault(emptyList())
        }

        override fun getCount() = items.size
        override fun getViewTypeCount() = 1
        override fun hasStableIds() = true
        override fun getItemId(position: Int) = items.getOrNull(position)?.id ?: position.toLong()
        override fun getLoadingView(): RemoteViews? = null

        override fun getViewAt(position: Int): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.fotos_widget_item)
            val item = items.getOrNull(position) ?: return views
            val (w, h) = pixelSize()
            runCatching { render(item, w, h) }.getOrNull()?.let { views.setImageViewBitmap(R.id.picture, it) }

            val text = caption(item)
            views.setTextViewText(R.id.caption, text)
            views.setViewVisibility(R.id.caption, if (text.isEmpty()) View.GONE else View.VISIBLE)
            val badge = when {
                item.video -> "▶ " + duration(item.durationMs)
                item.motion -> "◎ MOTION"
                else -> ""
            }
            views.setTextViewText(R.id.badge, badge)
            views.setViewVisibility(R.id.badge, if (badge.isEmpty()) View.GONE else View.VISIBLE)
            // On the picture, not the item's root: a fill-in on the root of a
            // flipper's item is only stored as a tag, and the tap then opens
            // fotos without saying which photo.
            views.setOnClickFillInIntent(R.id.picture, Intent().setData(item.uri))
            return views
        }

        /** The widget's size on screen, in pixels, capped to keep each picture small. */
        private fun pixelSize(): Pair<Int, Int> {
            val o = AppWidgetManager.getInstance(context).getAppWidgetOptions(id)
            val density = context.resources.displayMetrics.density
            // Portrait: the width is the narrower measure and the height the taller.
            val wDp = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH).takeIf { it > 0 } ?: 320
            val hDp = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT).takeIf { it > 0 } ?: 160
            var w = wDp * density
            var h = hDp * density
            val k = minOf(1f, 900f / maxOf(w, h))
            w *= k; h *= k
            return Pair(w.toInt().coerceAtLeast(1), h.toInt().coerceAtLeast(1))
        }

        private fun render(item: WidgetItem, w: Int, h: Int): Bitmap {
            val whole = config.fit == "whole"
            val source = if (item.video) videoFrame(item, w, h) else photo(item, w, h, cover = !whole)
            // RGB_565 holds half the bytes of full colour, so twice as many
            // pictures fit in the memory Android allows a widget, and a photo
            // shows no visible difference at this size. Corners are clipped
            // by the widget's frame, so no transparency is needed.
            val out = Bitmap.createBitmap(w, h, Bitmap.Config.RGB_565)
            val canvas = Canvas(out)
            val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
            val src = Rect(0, 0, source.width, source.height)
            fun fitted(cover: Boolean): RectF {
                val k = if (cover) maxOf(w / source.width.toFloat(), h / source.height.toFloat())
                else minOf(w / source.width.toFloat(), h / source.height.toFloat())
                val dw = source.width * k
                val dh = source.height * k
                return RectF((w - dw) / 2, (h - dh) / 2, (w + dw) / 2, (h + dh) / 2)
            }
            if (whole) {
                // A blurred, dimmed copy fills the edges: shrinking to a few
                // dozen pixels and stretching back is the blur.
                val tiny = Bitmap.createScaledBitmap(
                    source, 24, (24f * source.height / source.width).toInt().coerceAtLeast(1), true,
                )
                val dim = Paint(paint).apply { colorFilter = LightingColorFilter(0x8C8C8C, 0) }
                canvas.drawBitmap(tiny, Rect(0, 0, tiny.width, tiny.height), fitted(true), dim)
                canvas.drawBitmap(source, src, fitted(false), paint)
            } else {
                canvas.drawBitmap(source, src, fitted(true), paint)
            }
            return out
        }

        /**
         * The photo decoded from its own file at no less than the size it is
         * drawn at. Android's thumbnail store was tried first and gave
         * pictures as small as 128 x 160 for a widget 873 x 468 across, which
         * then had to be stretched. ImageDecoder turns the photo upright from
         * its EXIF orientation.
         */
        private fun photo(item: WidgetItem, w: Int, h: Int, cover: Boolean): Bitmap =
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, item.uri)) { decoder, info, _ ->
                val iw = info.size.width.toFloat()
                val ih = info.size.height.toFloat()
                val scale = if (cover) maxOf(w / iw, h / ih) else minOf(w / iw, h / ih)
                // Whole steps of halving, never below the size needed.
                decoder.setTargetSampleSize(maxOf(1, (1 / scale).toInt()))
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }

        /** A frame near the start of the video, large enough to cover the widget. */
        private fun videoFrame(item: WidgetItem, w: Int, h: Int): Bitmap {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(context, item.uri)
                // The frame is fitted inside this box with its shape kept, so a
                // square twice the widget's longer side covers it either way up.
                val side = 2 * maxOf(w, h)
                return retriever.getScaledFrameAtTime(-1, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, side, side)
                    ?: context.contentResolver.loadThumbnail(item.uri, Size(w, h), null)
            } finally {
                retriever.release()
            }
        }

        private fun caption(item: WidgetItem): String = when (config.caption) {
            "none" -> ""
            "album" -> item.album
            "ago" -> {
                val now = Calendar.getInstance()
                val then = Calendar.getInstance().apply { timeInMillis = item.taken }
                when (val years = now.get(Calendar.YEAR) - then.get(Calendar.YEAR)) {
                    in Int.MIN_VALUE..0 -> "This year"
                    1 -> "1 year ago"
                    else -> "$years years ago"
                }
            }
            else -> SimpleDateFormat("dd/MM/yyyy", Locale.US).format(item.taken)
        }

        private fun duration(ms: Long): String {
            val s = ms / 1000
            return if (s >= 3600) String.format(Locale.US, "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            else String.format(Locale.US, "%d:%02d", s / 60, s % 60)
        }
    }
}
