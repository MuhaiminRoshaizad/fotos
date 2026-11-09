package my.minned.fotos

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NativeChannel.NAME)
        channel.setMethodCallHandler(NativeChannel(this, channel))
        this.channel = channel
    }

    /** A View or camera Review request while fotos is already running. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        viewUri(intent)?.let { channel?.invokeMethod("openUri", it) }
    }

    companion object {
        fun viewUri(intent: Intent?): String? {
            if (intent == null) return null
            val viewing = intent.action == Intent.ACTION_VIEW ||
                intent.action == "com.android.camera.action.REVIEW"
            return if (viewing) intent.data?.toString() else null
        }
    }
}
