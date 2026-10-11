package dev.termphin.termphin

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * The files shared to [ShareActivity], for its Dart side to upload.
 *
 * The read grant comes with the activity's intent and lasts as long as the
 * activity, so a file is opened only when Dart starts reading it, and opened
 * again from the start if the upload is tried a second time - after a
 * failure, or to another machine. Dart pulls it a chunk at a time, so nothing
 * is copied to disk first.
 */
class ShareChannel(private val activity: Activity, private val share: Intent) {

    companion object {
        private const val CHANNEL_NAME = "dev.termphin.termphin/share"

        @Suppress("DEPRECATION")
        fun streamsOf(intent: Intent): List<Uri> {
            if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
                return if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
                } ?: emptyList()
            }
            val uri = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            return listOfNotNull(uri)
        }
    }

    private val files = ConcurrentHashMap<String, Uri>()
    private val open = ConcurrentHashMap<String, InputStream>()
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeShare" -> takeShare(result)
                    "read" -> read(
                        call.argument<String>("id")!!,
                        call.argument<Int>("max")!!,
                        result,
                    )
                    "rewind" -> {
                        call.argument<String>("id")?.let { id ->
                            open.remove(id)?.let { closeQuietly(it) }
                        }
                        result.success(null)
                    }
                    "finish" -> {
                        activity.finish()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * What was shared. `files` lists what could be read, which leaves it
     * empty for a share of text alone; `text` says whether there was any.
     */
    private fun takeShare(result: MethodChannel.Result) {
        val uris = streamsOf(share)
        val hasText = !share.getStringExtra(Intent.EXTRA_TEXT).isNullOrEmpty()
        io.execute {
            val described = uris.mapNotNull { uri ->
                val id = UUID.randomUUID().toString()
                describe(uri)?.let { (name, size) ->
                    files[id] = uri
                    mapOf("id" to id, "name" to name, "size" to size)
                }
            }
            main.post { result.success(mapOf("files" to described, "text" to hasText)) }
        }
    }

    /** Up to [max] bytes of the file, or null once it is all read. */
    private fun read(id: String, max: Int, result: MethodChannel.Result) {
        val uri = files[id]
        if (uri == null) {
            result.error("closed", "shared file is no longer open", null)
            return
        }
        io.execute {
            try {
                val stream = open.getOrPut(id) {
                    activity.contentResolver.openInputStream(uri)
                        ?: throw IllegalStateException("no stream")
                }
                val buffer = ByteArray(max)
                var filled = 0
                while (filled < max) {
                    val n = stream.read(buffer, filled, max - filled)
                    if (n < 0) break
                    filled += n
                }
                val chunk = if (filled == 0) null else buffer.copyOf(filled)
                main.post { result.success(chunk) }
            } catch (e: Exception) {
                main.post { result.error("read", e.message, null) }
            }
        }
    }

    /**
     * The name the sharing app gave the file, never a path from it, and its
     * size if known. Null for a file that cannot be looked at at all.
     */
    private fun describe(uri: Uri): Pair<String, Long?>? {
        var name: String? = null
        var size: Long? = null
        try {
            activity.contentResolver.query(
                uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    name = cursor.getString(0)
                    if (!cursor.isNull(1)) size = cursor.getLong(1).takeIf { it >= 0 }
                }
            }
        } catch (_: SecurityException) {
            return null
        } catch (_: Exception) {
        }
        val raw = name ?: uri.lastPathSegment ?: "shared-file"
        val safe = raw.substringAfterLast('/').substringAfterLast('\\').trim()
        return (if (safe.isEmpty() || safe == "." || safe == "..") "shared-file" else safe) to size
    }

    fun dispose() {
        open.values.forEach { closeQuietly(it) }
        open.clear()
        files.clear()
        io.shutdown()
    }

    private fun closeQuietly(stream: InputStream) {
        try {
            stream.close()
        } catch (_: Exception) {
        }
    }
}
