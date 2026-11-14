package my.minned.fotos

import android.graphics.Bitmap
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import java.io.ByteArrayOutputStream
import java.util.concurrent.LinkedBlockingQueue

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
 * readers stay open until [close], each used by one call at a time.
 */
class VideoFrameReader(private val path: String, private val px: Int) {
    companion object {
        const val READERS = 3
    }

    private class Reader(path: String) {
        val retriever = MediaMetadataRetriever().apply { setDataSource(path) }

        // Finds keyframes; null when the file has no video track it knows.
        val extractor: MediaExtractor? = MediaExtractor().let { x ->
            try {
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

        /** The first keyframe at or after [ms], in ms, or null. */
        fun keyframeFrom(ms: Long): Long? {
            val x = extractor ?: return null
            x.seekTo(ms * 1000, MediaExtractor.SEEK_TO_NEXT_SYNC)
            return x.sampleTime.takeIf { it >= 0 }?.let { it / 1000 }
        }

        fun release() {
            retriever.release()
            extractor?.release()
        }
    }

    private val idle = LinkedBlockingQueue<Reader>()
    private var made = 0
    @Volatile private var closed = false

    /**
     * The picture for the stretch [fromMs] to [untilMs], as the moment it
     * shows (ms) and JPEG bytes about [px] across; null if none can be read.
     * Blocks, so call it off the main thread.
     */
    fun frameIn(fromMs: Long, untilMs: Long): Pair<Long, ByteArray>? {
        if (closed) return null
        val reader = take() ?: return null
        try {
            val key = reader.keyframeFrom(fromMs)
            val (ms, option) = if (key != null && key < untilMs) {
                key to MediaMetadataRetriever.OPTION_CLOSEST_SYNC
            } else {
                fromMs to MediaMetadataRetriever.OPTION_CLOSEST
            }
            val frame = reader.retriever.getScaledFrameAtTime(ms * 1000, option, px, px)
                ?: return null
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
    @Synchronized
    fun close() {
        closed = true
        while (true) (idle.poll() ?: break).release()
    }

    private fun take(): Reader? {
        idle.poll()?.let { return it }
        synchronized(this) {
            if (made < READERS) {
                made++
                return try {
                    Reader(path)
                } catch (_: Exception) {
                    made--
                    null
                }
            }
        }
        return idle.take()
    }

    @Synchronized
    private fun give(reader: Reader) {
        if (closed) reader.release() else idle.put(reader)
    }
}
