package my.minned.fotos

import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.os.Bundle
import android.provider.MediaStore
import android.util.Size
import java.io.ByteArrayOutputStream

/**
 * Android's own trash (API 30+). MediaStore hides trashed rows from normal
 * queries, so listing them needs QUERY_ARG_MATCH_TRASHED.
 */
object TrashStore {
    private val files = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)

    fun list(context: Context): List<Map<String, Any?>> {
        val image = MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE
        val video = MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
        val args = Bundle().apply {
            putInt(MediaStore.QUERY_ARG_MATCH_TRASHED, MediaStore.MATCH_ONLY)
            putString(
                ContentResolver.QUERY_ARG_SQL_SELECTION,
                "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (?, ?)",
            )
            putStringArray(
                ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS,
                arrayOf(image.toString(), video.toString()),
            )
            putString(
                ContentResolver.QUERY_ARG_SQL_SORT_ORDER,
                "${MediaStore.MediaColumns.DATE_EXPIRES} ASC",
            )
        }
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.Files.FileColumns.MEDIA_TYPE,
            MediaStore.MediaColumns.DATE_EXPIRES,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.WIDTH,
            MediaStore.MediaColumns.HEIGHT,
            MediaStore.MediaColumns.DURATION,
        )
        val out = mutableListOf<Map<String, Any?>>()
        context.contentResolver.query(files, projection, args, null)?.use { c ->
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to c.getLong(0).toString(),
                        "name" to c.getString(1),
                        "video" to (c.getInt(2) == video),
                        "expires" to c.getLong(3),
                        "size" to c.getLong(4),
                        "width" to c.getInt(5),
                        "height" to c.getInt(6),
                        "duration" to c.getLong(7),
                    ),
                )
            }
        }
        return out
    }

    fun thumbnail(context: Context, id: Long, video: Boolean, px: Int): ByteArray {
        val base = if (video) {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        val bitmap = context.contentResolver.loadThumbnail(
            ContentUris.withAppendedId(base, id),
            Size(px, px),
            null,
        )
        val bytes = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 85, bytes)
        bitmap.recycle()
        return bytes.toByteArray()
    }
}
