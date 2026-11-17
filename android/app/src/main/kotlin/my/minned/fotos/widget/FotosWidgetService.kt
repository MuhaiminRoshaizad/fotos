package my.minned.fotos.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import my.minned.fotos.R

/**
 * Hands a widget its pictures one at a time as the home screen asks, on
 * Android 11 only. Later versions are given all their pictures at once
 * (FotosWidgetProvider.update).
 */
class FotosWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = Factory(
        applicationContext,
        intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID),
    )

    private class Factory(private val context: Context, private val id: Int) : RemoteViewsFactory {
        private var items: List<WidgetItem> = emptyList()
        private var pictures: WidgetPictures? = null

        override fun onCreate() {}
        override fun onDestroy() { items = emptyList() }

        override fun onDataSetChanged() {
            val p = WidgetPictures(context, id, WidgetConfig.load(context, id) ?: WidgetConfig())
            pictures = p
            items = p.items()
        }

        override fun getCount() = items.size
        override fun getViewTypeCount() = 1
        override fun hasStableIds() = true
        override fun getItemId(position: Int) = items.getOrNull(position)?.id ?: position.toLong()
        override fun getLoadingView(): RemoteViews? = null

        override fun getViewAt(position: Int): RemoteViews {
            val item = items.getOrNull(position)
            val p = pictures
            return if (item == null || p == null) RemoteViews(context.packageName, R.layout.fotos_widget_item)
            else p.view(item)
        }
    }
}
