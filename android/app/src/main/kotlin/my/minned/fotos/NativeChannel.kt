package my.minned.fotos

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.graphics.Rect
import android.media.ExifInterface
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import my.minned.fotos.widget.WidgetConfig

/** Android work Flutter has no API for. Slow calls run off the main thread. */
class NativeChannel(
    private val activity: Activity,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val NAME = "my.minned.fotos/native"
    }

    private val io = Executors.newCachedThreadPool()

    // Thumbnails for Files tiles. A fling or the scroll handle can ask for
    // dozens at once; three at a time keeps the rest of the app responsive.
    private val thumbs = Executors.newFixedThreadPool(3)

    @Volatile private var takeout: TakeoutImporter? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "exif" -> background(result) { exif(call.argument<String>("path")!!) }
            "isMotionPhoto" -> background(result) {
                MotionPhotos.locate(call.argument<String>("path")!!) != null
            }
            "motionVideo" -> background(result) {
                MotionPhotos.extract(activity, call.argument<String>("path")!!)
            }
            "trashList" -> background(result) { TrashStore.list(activity) }
            "trashThumbnail" -> background(result) {
                TrashStore.thumbnail(
                    activity,
                    call.argument<String>("id")!!.toLong(),
                    call.argument<Boolean>("video")!!,
                    call.argument<Int>("px")!!,
                )
            }
            "favourite" -> MediaRequests.favourite(
                activity,
                call.argument<List<String>>("ids")!!,
                call.argument<List<Boolean>>("videos")!!,
                call.argument<Boolean>("value")!!,
            ) { ok -> result.success(ok) }
            "deleteForever" -> MediaRequests.delete(
                activity,
                call.argument<List<String>>("ids")!!,
                call.argument<List<Boolean>>("videos")!!,
            ) { ok -> result.success(ok) }
            "awaitSplash" -> {
                val main = activity as? MainActivity
                // Answers whether to skip the flower: true when fotos was
                // opened to show one photo.
                if (main == null) result.success(false) else main.whenSplashGone { result.success(main.openedToView) }
            }
            "launchUri" -> {
                // Handed out once, so a later resume doesn't reopen it.
                val uri = MainActivity.viewUri(activity.intent)
                activity.intent = android.content.Intent(activity.intent).setAction(null)
                result.success(uri)
            }
            "root" -> result.success(FilesNative.root())
            "rekeyWidgetAlbum" -> {
                val changed = WidgetConfig.rekeyAlbum(
                    activity, call.argument<String>("from")!!, call.argument<String>("to")!!,
                )
                val manager = AppWidgetManager.getInstance(activity)
                // The widget reads its pictures again with the new id.
                for (id in changed) manager.notifyAppWidgetViewDataChanged(id, R.id.flipper)
                result.success(changed.size)
            }
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
            "zipCover" -> background(result) {
                FilesNative.zipCover(call.argument<String>("path")!!, call.argument<Int>("px")!!)
            }
            "zipEntries" -> background(result) {
                FilesNative.zipEntries(call.argument<String>("path")!!)
            }
            "zipPageThumb" -> background(result) {
                FilesNative.zipPageThumb(
                    call.argument<String>("path")!!,
                    call.argument<String>("name")!!,
                    call.argument<Int>("px")!!,
                )
            }
            "zipRemove" -> background(result) {
                val path = call.argument<String>("path")!!
                val remaining = FilesNative.zipRemove(
                    path,
                    call.argument<List<String>>("names")!!.toSet(),
                ) { done, total ->
                    activity.runOnUiThread {
                        channel.invokeMethod(
                            "zipRemoveProgress",
                            mapOf("done" to done, "total" to total),
                        )
                    }
                }
                // The archive's size changed; keep MediaStore in step.
                FilesNative.scan(activity, listOf(path))
                remaining
            }
            "videoFrame" -> background(result) {
                FilesNative.videoFrame(call.argument<String>("path")!!, call.argument<Int>("px")!!)
            }
            "setGestureExclusion" -> {
                // Areas in window pixels where Android's back swipe is off,
                // such as the scroll handle on the right edge.
                val rects = call.argument<List<List<Int>>>("rects").orEmpty()
                activity.window.decorView.systemGestureExclusionRects =
                    rects.map { Rect(it[0], it[1], it[2], it[3]) }
                result.success(null)
            }
            "thumbnail" -> background(result, thumbs) {
                FilesNative.thumbnail(
                    activity,
                    call.argument<String>("path")!!,
                    call.argument<Int>("px")!!,
                )
            }
            "videoFrames" -> background(result) {
                FilesNative.videoFrames(
                    call.argument<String>("path")!!,
                    call.argument<Int>("count")!!,
                    call.argument<Int>("px")!!,
                )
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
            "takeoutRepairDates" -> background(result) { TakeoutDates.repair(activity) }
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

    private fun background(
        result: MethodChannel.Result,
        pool: ExecutorService = io,
        work: () -> Any?,
    ) {
        pool.execute {
            try {
                // A Unit result can't cross the channel; replying with it
                // throws on the main thread and takes the whole app down.
                val value = work().takeUnless { it == Unit }
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
