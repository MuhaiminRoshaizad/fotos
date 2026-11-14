package my.minned.fotos

import android.graphics.Bitmap
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import java.io.ByteArrayOutputStream
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * Frames of one video for the viewer's strip and the editor's timeline,
 * one at a time, so each can go on screen the moment it is read.
 *
 * A strip tile stands for a stretch of the video, and its picture must come
 * from inside that stretch. A keyframe inside it is quick to read, so that
 * is used when there is one; otherwise the exact frame at the stretch's
 * start is decoded. Taking the nearest keyframe instead, as before, could
 * show a picture from seconds or minutes away on downloads, whose
 * keyframes are often ten seconds apart.
 *
 * Opening a file costs more than reading a frame, so up to [READERS]
 * frame readers stay open until [close], each used by one call at a time,
 * and one shared index finds the keyframes.
 */
class VideoFrameReader(private val path: String, private val px: Int) {
    companion object {
        const val READERS = 3
    }

    private val idle = LinkedBlockingQueue<MediaMetadataRetriever>()
    private var made = 0
    @Volatile private var closed = false

    private val keys = Any()
    private var index: MediaExtractor? = null
    private var indexTried = false

    /**
     * The picture for the stretch [fromMs] to [untilMs], as the moment it
     * shows (ms) and JPEG bytes about [px] across; null if none can be read.
     * Blocks, so call it off the main thread.
     */
    fun frameIn(fromMs: Long, untilMs: Long): Pair<Long, ByteArray>? {
        if (closed) return null
        // A reader first: the readers open while the first call reads the
        // keyframe index.
        val reader = take() ?: return null
        try {
            val key = keyframeFrom(fromMs)
            val (ms, option) = if (key != null && key < untilMs) {
                key to MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            } else {
                fromMs to MediaMetadataRetriever.OPTION_CLOSEST
            }
            val frame = reader.getScaledFrameAtTime(ms * 1000, option, px, px) ?: return null
            val jpeg = ByteArrayOutputStream()
                .also { frame.compress(Bitmap.CompressFormat.JPEG, 80, it) }
                .toByteArray()
            frame.recycle()
            return ms to jpeg
        } finally {
            give(reader)
        }
    }

    /** Releases the readers; any still reading are released when done. */
    fun close() {
        synchronized(this) {
            closed = true
            while (true) (idle.poll() ?: break).release()
        }
        synchronized(keys) {
            index?.release()
            index = null
        }
    }

    /** The first keyframe at or after [ms], in ms, or null if unknown. */
    private fun keyframeFrom(ms: Long): Long? = synchronized(keys) {
        // Not opened after close, or nothing would release it.
        if (closed) return null
        if (!indexTried) {
            indexTried = true
            index = openIndex()
        }
        val x = index ?: return null
        x.seekTo(ms * 1000, MediaExtractor.SEEK_TO_NEXT_SYNC)
        x.sampleTime.takeIf { it >= 0 }?.let { it / 1000 }
    }

    private fun openIndex(): MediaExtractor? {
        val x = MediaExtractor()
        return try {
            x.setDataSource(path)
            val track = (0 until x.trackCount).firstOrNull {
                x.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
            }
            if (track == null) {
                x.release()
                null
            } else {
                x.selectTrack(track)
                x
            }
        } catch (_: Exception) {
            x.release()
            null
        }
    }

    private fun take(): MediaMetadataRetriever? {
        idle.poll()?.let { return it }
        // Opened outside the lock, so the readers open side by side.
        val mayOpen = synchronized(this) { (made < READERS).also { if (it) made++ } }
        // Wait for a reader to come back, unless they are closed meanwhile:
        // a closed reader is released, never returned.
        while (!mayOpen) {
            if (closed) return null
            idle.poll(200, TimeUnit.MILLISECONDS)?.let { return it }
        }
        return try {
            MediaMetadataRetriever().apply { setDataSource(path) }
        } catch (_: Exception) {
            synchronized(this) { made-- }
            null
        }
    }

    private fun give(reader: MediaMetadataRetriever) {
        synchronized(this) {
            if (!closed) {
                idle.put(reader)
                return
            }
        }
        reader.release()
    }
}
