package my.minned.fotos

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.provider.MediaStore
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Runs a video save ([VideoCutter]) as a foreground service, so it carries
 * on when fotos is left or swiped away and the screen turns off. Its
 * notification shows how far it has got, with Cancel; when fotos is not on
 * show at the end, a second one says how it went.
 *
 * Android 15 gave long media work its own type, "mediaProcessing", with up
 * to six hours a day in the background; earlier versions run it as
 * "dataSync".
 */
class SaveService : Service() {
    companion object {
        private const val CHANNEL = "saving"
        private const val ONGOING = 41
        private const val OUTCOME = 42
        private const val ACTION_CANCEL = "my.minned.fotos.CANCEL_SAVE"

        /**
         * Starts saving video [id], keeping the parts [keep] ([start, end] in
         * ms). [name] is the original's file name, for the notification.
         * Must be called while fotos is on screen: Android lets an app start
         * a foreground service only then.
         */
        fun start(context: Context, id: Long, keep: List<Pair<Long, Long>>, replace: Boolean, name: String) {
            val i = Intent(context, SaveService::class.java)
                .putExtra("id", id)
                .putExtra("keep", keep.flatMap { listOf(it.first, it.second) }.toLongArray())
                .putExtra("replace", replace)
                .putExtra("name", name)
            context.startForegroundService(i)
        }
    }

    private val io: ExecutorService = Executors.newCachedThreadPool()
    private var cutter: VideoCutter? = null
    private var wake: PowerManager.WakeLock? = null
    private var name = ""
    private var shown = -1

    private val notifications get() = getSystemService(NotificationManager::class.java)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL) {
            cutter?.cancel()
            return START_NOT_STICKY
        }
        // One save at a time; fotos refuses a second before it gets here.
        if (intent == null || cutter != null) return START_NOT_STICKY
        name = intent.getStringExtra("name") ?: ""
        notifications.createNotificationChannel(
            NotificationChannel(CHANNEL, "Saving videos", NotificationManager.IMPORTANCE_LOW),
        )
        val type = if (Build.VERSION.SDK_INT >= 35) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING
        } else {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        }
        startForeground(ONGOING, progress(0), type)
        // A foreground service keeps fotos running, not the processor
        // awake: with the screen off the phone could sleep mid-encode.
        wake = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "fotos:save")
            .apply { acquire(6 * 60 * 60 * 1000L) }
        val keep = (intent.getLongArrayExtra("keep") ?: LongArray(0))
            .toList().chunked(2).map { it[0] to it[1] }
        val c = VideoCutter(applicationContext, io) { p ->
            SaveJob.progress(p)
            if (p != shown) {
                shown = p
                notifications.notify(ONGOING, progress(p))
            }
        }
        cutter = c
        SaveJob.started(name) { c.cancel() }
        c.start(intent.getLongExtra("id", -1), keep, intent.getBooleanExtra("replace", false)) { outcome ->
            finish(outcome)
        }
        return START_NOT_STICKY
    }

    /** The six hours a day are used up: stop, as Android requires within seconds. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        cutter?.cancel()
    }

    override fun onDestroy() {
        wake?.takeIf { it.isHeld }?.release()
        io.shutdown()
        super.onDestroy()
    }

    /** On the main thread, once, however the save ended. */
    private fun finish(outcome: Result<Map<String, Any?>>) {
        cutter = null
        wake?.takeIf { it.isHeld }?.release()
        val event = outcome.fold(
            { it },
            { e ->
                mapOf(
                    "error" to ((e as? VideoCutter.CutException)?.code ?: "failed"),
                    "message" to e.message,
                )
            },
        )
        SaveJob.finished(event)
        stopForeground(STOP_FOREGROUND_REMOVE)
        // On screen, fotos says how it went itself.
        if (!SaveJob.visible) told(event)?.let { notifications.notify(OUTCOME, it) }
        stopSelf()
    }

    private fun progress(p: Int): Notification {
        val finishing = p >= 100
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notify)
            .setContentTitle(if (finishing) "Finishing video" else "Saving video · $p%")
            .setContentText(name)
            .setProgress(100, p, finishing)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setContentIntent(openApp())
            .apply {
                // Past 100 the original may already be in the trash; the
                // save can no longer be stopped.
                if (!finishing) {
                    addAction(
                        Notification.Action.Builder(
                            null,
                            "Cancel",
                            PendingIntent.getService(
                                this@SaveService,
                                0,
                                Intent(this@SaveService, SaveService::class.java).setAction(ACTION_CANCEL),
                                PendingIntent.FLAG_IMMUTABLE,
                            ),
                        ).build(),
                    )
                }
            }
            .build()
    }

    /** The notification for how the save ended, or null for a cancel, which the user did. */
    private fun told(event: Map<String, Any?>): Notification? {
        val error = event["error"] as String?
        if (error == "cancelled") return null
        val b = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notify)
            .setAutoCancel(true)
        if (error != null) {
            return b.setContentTitle("Couldn't save the edit")
                .setContentText("$name is unchanged.")
                .setContentIntent(openApp())
                .build()
        }
        val saved = event["name"] as String? ?: ""
        val id = (event["id"] as String?)?.toLongOrNull()
        return b.setContentTitle("Video saved")
            .setContentText("$saved. Tap to watch it.")
            .setContentIntent(if (id == null) openApp() else watch(id))
            .build()
    }

    private fun openApp(): PendingIntent = PendingIntent.getActivity(
        this,
        0,
        packageManager.getLaunchIntentForPackage(packageName),
        PendingIntent.FLAG_IMMUTABLE,
    )

    /** Opens video [id] in fotos' viewer, as Android's View would. */
    private fun watch(id: Long): PendingIntent = PendingIntent.getActivity(
        this,
        1,
        Intent(Intent.ACTION_VIEW, ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id))
            .setClass(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
}
