package my.minned.fotos

import android.app.Activity
import android.media.ExifInterface
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Android work Flutter has no API for. Slow calls run off the main thread. */
class NativeChannel(
    private val activity: Activity,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val NAME = "my.minned.fotos/native"
    }

    private val io = Executors.newCachedThreadPool()

    @Volatile private var takeout: TakeoutImporter? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "exif" -> background(result) { exif(call.argument<String>("path")!!) }
            "trashList" -> background(result) { TrashStore.list(activity) }
            "trashThumbnail" -> background(result) {
                TrashStore.thumbnail(
                    activity,
                    call.argument<String>("id")!!.toLong(),
                    call.argument<Boolean>("video")!!,
                    call.argument<Int>("px")!!,
                )
            }
            "root" -> result.success(FilesNative.root())
            "hasAllFilesAccess" -> result.success(FilesNative.hasAllFilesAccess())
            "openAllFilesAccessSettings" -> {
                FilesNative.openAllFilesAccessSettings(activity)
                result.success(null)
            }
            "storage" -> result.success(FilesNative.storage())
            "scan" -> background(result) {
                FilesNative.scan(activity, call.argument<List<String>>("paths")!!)
            }
            "openWith" -> {
                try {
                    FilesNative.openWith(activity, call.argument<String>("path")!!)
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
            "zipInfo" -> background(result) { FilesNative.zipInfo(call.argument<String>("path")!!) }
            "extract" -> background(result) {
                val written = FilesNative.extract(
                    call.argument<String>("zip")!!,
                    call.argument<String>("target")!!,
                ) { done, total ->
                    activity.runOnUiThread {
                        channel.invokeMethod(
                            "extractProgress",
                            mapOf("done" to done, "total" to total),
                        )
                    }
                }
                FilesNative.scan(activity, written)
                written.size
            }
            "pdfPageCount" -> background(result) {
                FilesNative.pdfPageCount(call.argument<String>("path")!!)
            }
            "pdfPage" -> background(result) {
                FilesNative.pdfPage(
                    call.argument<String>("path")!!,
                    call.argument<Int>("index")!!,
                    call.argument<Int>("width")!!,
                )
            }
            "takeoutStart" -> background(result) {
                val importer = TakeoutImporter(activity) { p ->
                    activity.runOnUiThread { channel.invokeMethod("takeoutProgress", p) }
                }
                takeout = importer
                try {
                    importer.run(call.argument<String>("path")!!)
                } finally {
                    takeout = null
                }
            }
            "takeoutCancel" -> {
                takeout?.cancelled = true
                result.success(null)
            }
            "takeoutReviews" -> background(result) {
                val all = TakeoutImporter.readReviews(activity)
                (0 until all.length()).map { i ->
                    val o = all.getJSONObject(i)
                    o.keys().asSequence().associateWith { k -> o.get(k).takeIf { it != org.json.JSONObject.NULL } }
                }
            }
            "takeoutResolve" -> background(result) {
                val id = call.argument<String>("id")!!
                val keepTakeout = call.argument<Boolean>("keepTakeout")!!
                val item = TakeoutImporter.findReview(activity, id)
                if (item != null && keepTakeout) TakeoutImporter.publishStaged(activity, item)
                TakeoutImporter.dropReview(activity, id)
                null
            }
            "keepScreenOn" -> {
                val on = call.argument<Boolean>("on")!!
                val flag = android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                if (on) activity.window.addFlags(flag) else activity.window.clearFlags(flag)
                result.success(null)
            }
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
