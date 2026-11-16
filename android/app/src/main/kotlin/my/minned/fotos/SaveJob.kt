package my.minned.fotos

import android.os.Handler
import android.os.Looper

/**
 * The one video save that can run at a time, kept for the whole process
 * so it outlives the screen that started it: [SaveService] runs it while
 * fotos is left, or swiped away. Flutter follows it through [listener]
 * while it is attached, and asks for [status] when it attaches mid-save.
 * Touched on the main thread only.
 */
object SaveJob {
    private val main = Handler(Looper.getMainLooper())

    /** Sends an event to Dart (method, argument); set while Flutter is attached. */
    var listener: ((String, Any?) -> Unit)? = null

    /** Whether a fotos screen is on show; set by MainActivity. */
    var visible = false

    var running = false
        private set
    private var percent = 0
    private var name = ""
    private var cancel: (() -> Unit)? = null

    fun status(): Map<String, Any?> = mapOf("running" to running, "percent" to percent, "name" to name)

    fun started(name: String, cancel: () -> Unit) {
        running = true
        percent = 0
        this.name = name
        this.cancel = cancel
    }

    fun progress(p: Int) = main.post {
        percent = p
        listener?.invoke("cutProgress", p)
    }

    /** [outcome] is the new video's id, name and whether it replaced the original, or an error code and message. */
    fun finished(outcome: Map<String, Any?>) {
        running = false
        cancel = null
        listener?.invoke("cutDone", outcome)
    }

    fun cancel() {
        cancel?.invoke()
    }
}
