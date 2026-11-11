package my.minned.fotos.widget

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The setup screen Android opens when a photo widget is placed, and again
 * from the widget's long-press menu. The screen itself is fotos' Flutter
 * page (lib/features/home_widget); this activity starts it on its own route
 * and keeps the widget only if the user taps Done.
 */
class WidgetSetupActivity : FlutterActivity() {
    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        widgetId = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        // Leaving without Done must not place a widget.
        setResult(Activity.RESULT_CANCELED, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
        super.onCreate(savedInstanceState)
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) finish()
    }

    override fun getInitialRoute(): String = "/widget-setup/$widgetId"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "load" -> result.success(WidgetConfig.load(this, widgetId)?.toMap())
                "save" -> {
                    val args = call.arguments as? Map<*, *>
                    if (args == null) {
                        result.error("bad_args", "Expected the widget's settings", null)
                    } else {
                        WidgetConfig.save(this, widgetId, WidgetConfig.fromMap(args))
                        FotosWidgetProvider.update(this, widgetId)
                        setResult(Activity.RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
                        result.success(null)
                        finish()
                    }
                }
                "cancel" -> {
                    result.success(null)
                    finish()
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        const val CHANNEL = "my.minned.fotos/widget"
    }
}
