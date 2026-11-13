package my.minned.fotos

import android.app.Activity
import android.app.PendingIntent
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * MediaStore changes that need the user's consent, sent as ONE system
 * request for the whole batch. URIs are built from id and type, without a
 * query, because MediaStore hides trashed items from queries.
 */
object MediaRequests {
    const val REQUEST_CODE = 4107

    private var pending: ((Boolean) -> Unit)? = null

    private fun uris(ids: List<String>, videos: List<Boolean>): List<Uri> =
        ids.mapIndexed { i, id ->
            val base = if (videos[i]) {
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
            ContentUris.withAppendedId(base, id.toLong())
        }

    fun favourite(
        activity: Activity,
        ids: List<String>,
        videos: List<Boolean>,
        value: Boolean,
        done: (Boolean) -> Unit,
    ) = launch(
        activity,
        MediaStore.createFavoriteRequest(activity.contentResolver, uris(ids, videos), value),
        done,
    )

    /** Moves to Android's trash, or back out of it with [value] false. */
    fun trash(
        activity: Activity,
        ids: List<String>,
        videos: List<Boolean>,
        value: Boolean,
        done: (Boolean) -> Unit,
    ) = launch(
        activity,
        MediaStore.createTrashRequest(activity.contentResolver, uris(ids, videos), value),
        done,
    )

    /**
     * The ids among [ids] that MediaStore still lists, with their paths,
     * trashed ones included. A row can outlive its file, and a request
     * naming a row that has gone fails as a whole.
     */
    fun paths(context: Context, ids: List<String>): Map<String, String> {
        val out = mutableMapOf<String, String>()
        val files = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
        for (chunk in ids.chunked(500)) {
            val args = Bundle().apply {
                putString(
                    ContentResolver.QUERY_ARG_SQL_SELECTION,
                    "${MediaStore.MediaColumns._ID} IN (${chunk.joinToString(",") { "?" }})",
                )
                putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, chunk.toTypedArray())
                putInt(MediaStore.QUERY_ARG_MATCH_TRASHED, MediaStore.MATCH_INCLUDE)
                putInt(MediaStore.QUERY_ARG_MATCH_PENDING, MediaStore.MATCH_INCLUDE)
            }
            val projection = arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DATA)
            context.contentResolver.query(files, projection, args, null)?.use { c ->
                while (c.moveToNext()) out[c.getLong(0).toString()] = c.getString(1) ?: ""
            }
        }
        return out
    }

    /**
     * Drops rows whose file is no longer on disk. Android shows such a
     * row as a photo from its cached thumbnail, but can neither trash nor
     * delete it; scanning its path is what removes it, as after a file is
     * deleted in the Files tab. Returns the ids dropped.
     */
    fun dropMissing(context: Context, paths: Map<String, String>): List<String> {
        val missing = paths.filterValues { it.isNotEmpty() && !File(it).exists() }
        if (missing.isEmpty()) return emptyList()
        val latch = CountDownLatch(missing.size)
        MediaScannerConnection.scanFile(context, missing.values.toTypedArray(), null) { _, _ ->
            latch.countDown()
        }
        latch.await(30, TimeUnit.SECONDS)
        val left = paths(context, missing.keys.toList())
        return missing.keys.filter { it !in left }
    }

    /** Permanently deletes, trashed items included. Android confirms first. */
    fun delete(
        activity: Activity,
        ids: List<String>,
        videos: List<Boolean>,
        done: (Boolean) -> Unit,
    ) = launch(
        activity,
        MediaStore.createDeleteRequest(activity.contentResolver, uris(ids, videos)),
        done,
    )

    private fun launch(activity: Activity, request: PendingIntent, done: (Boolean) -> Unit) {
        pending?.invoke(false)
        pending = done
        activity.startIntentSenderForResult(request.intentSender, REQUEST_CODE, null, 0, 0, 0)
    }

    /** Called from MainActivity.onActivityResult. */
    fun onResult(resultCode: Int) {
        pending?.invoke(resultCode == Activity.RESULT_OK)
        pending = null
    }
}
