package my.minned.fotos.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import my.minned.fotos.MainActivity
import my.minned.fotos.R

/**
 * fotos' photo widget on the home screen.
 *
 * The picture changes by itself: the layout is an AdapterViewFlipper, which
 * the home screen runs on its own clock and stops while it isn't visible,
 * asking [FotosWidgetService] for one picture at a time. fotos never wakes
 * on a timer for it. Android has no way to set that clock on a widget, so
 * there is one layout per interval. Once a day the list is rebuilt and
 * shuffled again.
 */
class FotosWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) update(context, id)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        // Resized: the pictures are drawn at the widget's size.
        manager.notifyAppWidgetViewDataChanged(id, R.id.flipper)
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        for (id in ids) WidgetConfig.delete(context, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_NEXT) {
            val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            if (id != AppWidgetManager.INVALID_APPWIDGET_ID) {
                val config = WidgetConfig.load(context, id) ?: WidgetConfig()
                val views = RemoteViews(context.packageName, layoutFor(config.every))
                views.showNext(R.id.flipper)
                AppWidgetManager.getInstance(context).partiallyUpdateAppWidget(id, views)
            }
            return
        }
        super.onReceive(context, intent)
    }

    companion object {
        private const val ACTION_NEXT = "my.minned.fotos.widget.NEXT"

        private fun layoutFor(every: Int) = when {
            every >= 3600 -> R.layout.fotos_widget_hour
            every >= 900 -> R.layout.fotos_widget_15m
            every >= 60 -> R.layout.fotos_widget_1m
            else -> R.layout.fotos_widget_10s
        }

        /** Draws widget [id] from its saved settings. */
        @Suppress("DEPRECATION") // setRemoteAdapter(Intent): the replacement sends every picture up front.
        fun update(context: Context, id: Int) {
            val manager = AppWidgetManager.getInstance(context)
            val config = WidgetConfig.load(context, id) ?: WidgetConfig()
            val views = RemoteViews(context.packageName, layoutFor(config.every))

            val service = Intent(context, FotosWidgetService::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            // A distinct address per widget, or Android shares one list between them.
            service.data = Uri.parse(service.toUri(Intent.URI_INTENT_SCHEME))
            views.setRemoteAdapter(R.id.flipper, service)
            views.setEmptyView(R.id.flipper, R.id.empty)

            // Tapping a picture opens it in fotos' viewer, through the same
            // View request the camera uses.
            val open = Intent(context, MainActivity::class.java).setAction(Intent.ACTION_VIEW)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            views.setPendingIntentTemplate(
                R.id.flipper,
                PendingIntent.getActivity(context, id, open, PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
            )

            views.setViewVisibility(R.id.next, if (config.skip) View.VISIBLE else View.GONE)
            val next = Intent(context, FotosWidgetProvider::class.java).setAction(ACTION_NEXT)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
            views.setOnClickPendingIntent(
                R.id.next,
                PendingIntent.getBroadcast(context, id, next, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
            )

            manager.updateAppWidget(id, views)
            manager.notifyAppWidgetViewDataChanged(id, R.id.flipper)
        }
    }
}
