package my.minned.fotos

import android.app.Activity
import android.media.ExifInterface
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Android work Flutter has no API for. Slow calls run off the main thread. */
class NativeChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val NAME = "my.minned.fotos/native"
    }

    private val io = Executors.newSingleThreadExecutor()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "exif" -> background(result) { exif(call.argument<String>("path")!!) }
            else -> result.notImplemented()
        }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                activity.runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                activity.runOnUiThread { result.error("native_failed", e.message, null) }
            }
        }
    }

    /** Camera details for the viewer's details sheet. Missing tags are left out. */
    private fun exif(path: String): Map<String, Any> {
        val e = ExifInterface(path)
        val out = mutableMapOf<String, Any>()
        e.getAttribute(ExifInterface.TAG_MAKE)?.let { out["make"] = it.trim() }
        e.getAttribute(ExifInterface.TAG_MODEL)?.let { out["model"] = it.trim() }
        e.getAttributeDouble(ExifInterface.TAG_F_NUMBER, -1.0).takeIf { it > 0 }
            ?.let { out["fNumber"] = it }
        e.getAttributeDouble(ExifInterface.TAG_EXPOSURE_TIME, -1.0).takeIf { it > 0 }
            ?.let { out["exposure"] = it }
        e.getAttributeInt(ExifInterface.TAG_ISO_SPEED_RATINGS, -1).takeIf { it > 0 }
            ?.let { out["iso"] = it }
        e.getAttributeDouble(ExifInterface.TAG_FOCAL_LENGTH, -1.0).takeIf { it > 0 }
            ?.let { out["focalLength"] = it }
        return out
    }
}
