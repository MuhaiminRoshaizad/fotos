package my.minned.fotos

import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterRenderer
import io.flutter.plugin.common.MethodChannel
import java.time.Duration
import java.time.Instant

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var handler: NativeChannel? = null

    /** False while Android's launch screen is still up. */
    private var splashGone = true
    private var onSplashGone: (() -> Unit)? = null

    /**
     * Started to show one photo or video (from the widget, the camera or
     * another app). The flower is then skipped: the photo is what was asked
     * for, and waiting out an animation first only delays it.
     */
    var openedToView = false
        private set

    override fun onCreate(savedInstanceState: Bundle?) {
        // Videos play into an ImageReader by default, which hands Flutter
        // the decoder's whole buffer: a decoder that pads 1080 to 1088
        // shows the padding as a green line along an edge, and
        // video_player does not crop it (flutter/flutter#159955). A
        // SurfaceTexture's transform carries the crop, and Impeller on
        // Vulkan still draws one, through a GL copy.
        FlutterRenderer.debugForceSurfaceProducerGlTextures = true
        openedToView = viewUri(intent) != null
        // Android takes its launch screen down as soon as Flutter has drawn a
        // frame, which can be midway through the flower's pull-in. Hold it
        // until that animation has run, then hand over to Flutter, which
        // draws the same flower in the same place and plucks it apart.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && savedInstanceState == null && !openedToView) {
            splashGone = false
            splashScreen.setOnExitAnimationListener { view ->
                val start = view.iconAnimationStart
                val length = view.iconAnimationDuration
                val left = if (start == null || length == null) {
                    0L
                } else {
                    Duration.between(Instant.now(), start.plus(length)).toMillis()
                }
                view.postDelayed({
                    // Flutter's flower is already drawn beneath; show it
                    // before this one goes, so there is no empty frame.
                    finishSplash()
                    view.remove()
                }, left.coerceIn(0L, 1200L))
            }
        }
        super.onCreate(savedInstanceState)
    }

    private fun finishSplash() {
        splashGone = true
        onSplashGone?.invoke()
        onSplashGone = null
    }

    /** Calls [done] once Android's launch screen has gone; at once if it has. */
    fun whenSplashGone(done: () -> Unit) {
        if (splashGone) done() else onSplashGone = done
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NativeChannel.NAME)
        val handler = NativeChannel(this, channel)
        channel.setMethodCallHandler(handler)
        this.channel = channel
        this.handler = handler
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        handler?.detach()
        handler = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // A video save tells its outcome on screen while fotos shows, and by
    // notification otherwise (SaveService).
    override fun onResume() {
        super.onResume()
        SaveJob.visible = true
    }

    override fun onPause() {
        SaveJob.visible = false
        super.onPause()
    }

    @Deprecated("FlutterActivity still routes plugin results through this callback.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == MediaRequests.REQUEST_CODE) {
            MediaRequests.onResult(resultCode)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
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
