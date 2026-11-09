package my.minned.fotos

import android.app.Activity
import android.app.PendingIntent
import android.content.ContentUris
import android.net.Uri
import android.provider.MediaStore

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
