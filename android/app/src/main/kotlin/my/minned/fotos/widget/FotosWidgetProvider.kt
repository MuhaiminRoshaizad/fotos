package my.minned.fotos.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import my.minned.fotos.MainActivity
import my.minned.fotos.R
import java.util.concurrent.Executors

/**
 * fotos' photo widget on the home screen.
 *
 * The picture changes by itself: the layout is an AdapterViewFlipper, which
 * the home screen runs on its own clock and stops while it isn't visible.
 * fotos never wakes on a timer for it. Android has no way to set that clock
 * on a widget, so there is one layout per interval. Once a day the pictures
 * are drawn again from a fresh shuffle.
 *
 * Drawing takes seconds, so it runs off the main thread while the
 * broadcast is held open ([draw]). Android freezes an app 10 s after it
 * goes to the background, and a reinstall shows the widget's bare layout
 * until fotos answers: drawn the old way, after the broadcast had ended,
 * a slow draw was frozen or killed midway and the widget said "Nothing to
 * show" for up to a day (found on the phone, 17/11/2026).
 */
class FotosWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        draw(context, ids)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        // Resized: the pictures are drawn at the widget's size.
        draw(context, intArrayOf(id))
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        for (id in ids) WidgetConfig.delete(context, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_NEXT -> {
                val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
                if (id != AppWidgetManager.INVALID_APPWIDGET_ID) {
                    val config = WidgetConfig.load(context, id) ?: WidgetConfig()
                    val views = RemoteViews(context.packageName, layoutFor(config.every))
                    views.showNext(R.id.flipper)
                    AppWidgetManager.getInstance(context).partiallyUpdateAppWidget(id, views)
                }
            }
            ACTION_REFRESH -> intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS)?.let { draw(context, it) }
            else -> super.onReceive(context, intent)
        }
    }

    /** Draws widgets [ids] in the background, keeping fotos awake until they are on screen. */
    private fun draw(context: Context, ids: IntArray) {
        val pending = goAsync()
        val app = context.applicationContext
        drawing.execute {
            try {
                for (id in ids) update(app, id)
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        private const val ACTION_NEXT = "my.minned.fotos.widget.NEXT"
        private const val ACTION_REFRESH = "my.minned.fotos.widget.REFRESH"

        /** One at a time: two draws at once would each hold a widget's worth of pictures. */
        private val drawing = Executors.newSingleThreadExecutor()

        /** Draws widgets [ids] again from their saved settings, as their settings or albums change. */
        fun refresh(context: Context, ids: IntArray) {
            if (ids.isEmpty()) return
            context.sendBroadcast(
                Intent(context, FotosWidgetProvider::class.java).setAction(ACTION_REFRESH)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids),
            )
        }

        private fun layoutFor(every: Int) = when {
            every >= 3600 -> R.layout.fotos_widget_hour
            every >= 900 -> R.layout.fotos_widget_15m
            every >= 60 -> R.layout.fotos_widget_1m
            else -> R.layout.fotos_widget_10s
        }

        /** Draws widget [id] from its saved settings. Slow: never on the main thread. */
        @Suppress("DEPRECATION") // setRemoteAdapter(Intent): Android 11 has nothing else.
        private fun update(context: Context, id: Int) {
            val manager = AppWidgetManager.getInstance(context)
            val config = WidgetConfig.load(context, id) ?: WidgetConfig()
            val views = RemoteViews(context.packageName, layoutFor(config.every))

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Every picture up front, drawn here while fotos is held
                // awake. Android 17 turns the older adapter below into this
                // anyway (AppWidgetManager.tryAdapterConversion), but on a
                // thread of its own that nothing waits for.
                views.setRemoteAdapter(R.id.flipper, WidgetPictures(context, id, config).collection())
            } else {
                val service = Intent(context, FotosWidgetService::class.java)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                // A distinct address per widget, or Android shares one list between them.
                service.data = Uri.parse(service.toUri(Intent.URI_INTENT_SCHEME))
                views.setRemoteAdapter(R.id.flipper, service)
            }
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
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) manager.notifyAppWidgetViewDataChanged(id, R.id.flipper)
        }
    }
}
