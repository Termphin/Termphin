package dev.termphin.termphin

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class DownloadChannel(private val activity: Activity) {

    companion object {
        private const val CHANNEL_NAME = "dev.termphin.termphin/downloads"
        private const val PROGRESS_CHANNEL_ID = "download_progress"
        private const val COMPLETE_CHANNEL_ID = "download_complete"
        private const val GROUP_KEY = "dev.termphin.DOWNLOADS"
        private const val GROUP_SUMMARY_ID = 0x7F000000
        private const val COMPLETE_TAG = "download_complete"
        private const val ACTION_CANCEL_DOWNLOAD = "dev.termphin.action.CANCEL_DOWNLOAD"
        private const val EXTRA_DOWNLOAD_ID = "download_id"
        const val PICK_FOLDER_REQUEST = 0x7E01

        /** Safe as static: the process stays alive for the duration of a
         *  download because the foreground service holds it. */
        private var liveChannel: MethodChannel? = null
    }

    private val context get() = activity.applicationContext
    private val resolver get() = context.contentResolver

    /** Progress notifications currently on screen, so the group summary can go
     *  away with the last of them instead of outliving every download. */
    private val activeProgress = mutableSetOf<Int>()

    private var pendingFolderPick: MethodChannel.Result? = null
    private var receiverRegistered = false

    private val cancelReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val id = intent?.getIntExtra(EXTRA_DOWNLOAD_ID, -1) ?: return
            if (id != -1) {
                liveChannel?.invokeMethod("downloadCancelRequested", mapOf("id" to id))
            }
        }
    }

    private fun registerCancelReceiver() {
        if (receiverRegistered) return
        ContextCompat.registerReceiver(
            context,
            cancelReceiver,
            IntentFilter(ACTION_CANCEL_DOWNLOAD),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
        receiverRegistered = true
    }

    fun register(flutterEngine: FlutterEngine) {
        clearStaleProgressNotifications()

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        liveChannel = channel
        registerCancelReceiver()

        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val sourcePath = call.argument<String>("sourcePath")!!
                        val fileName = call.argument<String>("fileName")!!
                        val relativePath = call.argument<String>("relativePath")
                        val treeUri = call.argument<String>("treeUri")
                        try {
                            result.success(
                                saveToDownloads(sourcePath, fileName, relativePath, treeUri)
                            )
                        } catch (e: FolderUnavailableException) {
                            result.error("FOLDER_UNAVAILABLE", e.message, null)
                        } catch (e: Exception) {
                            result.error("SAVE_ERROR", e.message, null)
                        }
                    }
                    "pickDownloadFolder" -> {
                        pendingFolderPick?.error("CANCELLED", "Replaced by a new request", null)
                        pendingFolderPick = result
                        try {
                            activity.startActivityForResult(
                                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                                ),
                                PICK_FOLDER_REQUEST
                            )
                        } catch (e: ActivityNotFoundException) {
                            pendingFolderPick = null
                            result.error("NO_PICKER", e.message, null)
                        }
                    }
                    "downloadFolderLabel" -> {
                        val uri = call.argument<String>("treeUri")!!
                        result.success(folderLabel(Uri.parse(uri)))
                    }
                    "hasDownloadFolderAccess" -> {
                        val uri = call.argument<String>("treeUri")!!
                        result.success(hasPersistedAccess(Uri.parse(uri)))
                    }
                    "releaseDownloadFolder" -> {
                        val uri = call.argument<String>("treeUri")!!
                        releasePersistedAccess(Uri.parse(uri))
                        result.success(null)
                    }
                    "openDownload" -> {
                        val uri = call.argument<String>("uri")!!
                        val fileName = call.argument<String>("fileName") ?: ""
                        try {
                            openDownload(uri, fileName)
                            result.success(true)
                        } catch (e: ActivityNotFoundException) {
                            result.error("NO_HANDLER", e.message, null)
                        } catch (e: Exception) {
                            result.error("OPEN_ERROR", e.message, null)
                        }
                    }
                    "showProgress" -> {
                        val id = call.argument<Int>("id")!!
                        val fileName = call.argument<String>("fileName")!!
                        val progress = call.argument<Int>("progress")!!
                        val channelName = call.argument<String>("channelName")!!
                        val channelDescription = call.argument<String>("channelDescription")!!
                        val cancelLabel = call.argument<String>("cancelLabel")!!
                        showProgress(id, fileName, progress, channelName, channelDescription, cancelLabel)
                        result.success(null)
                    }
                    "showComplete" -> {
                        val id = call.argument<Int>("id")!!
                        val fileName = call.argument<String>("fileName")!!
                        val uri = call.argument<String>("uri")
                        val channelName = call.argument<String>("channelName")!!
                        val channelDescription = call.argument<String>("channelDescription")!!
                        val savedLabel = call.argument<String>("savedLabel")!!
                        showComplete(id, fileName, uri, channelName, channelDescription, savedLabel)
                        result.success(null)
                    }
                    "cancelNotification" -> {
                        val id = call.argument<Int>("id")!!
                        cancelProgress(id)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Returns true when the result belonged to this channel. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_FOLDER_REQUEST) return false
        val pending = pendingFolderPick ?: return true
        pendingFolderPick = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending.success(null)
            return true
        }
        try {
            resolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (e: SecurityException) {
            pending.error("NO_PERMISSION", e.message, null)
            return true
        }
        pending.success(mapOf("uri" to uri.toString(), "label" to folderLabel(uri)))
        return true
    }

    private class FolderUnavailableException(message: String) : Exception(message)

    private val notificationManager: NotificationManager
        get() = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private var progressChannelCreated = false
    private var completeChannelCreated = false

    private fun ensureProgressChannel(name: String, description: String) {
        if (progressChannelCreated) return
        val channel = NotificationChannel(
            PROGRESS_CHANNEL_ID,
            name,
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            this.description = description
            setSound(null, null)
            setShowBadge(false)
        }
        notificationManager.createNotificationChannel(channel)
        progressChannelCreated = true
    }

    private fun ensureCompleteChannel(name: String, description: String) {
        if (completeChannelCreated) return
        val channel = NotificationChannel(
            COMPLETE_CHANNEL_ID,
            name,
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            this.description = description
        }
        notificationManager.createNotificationChannel(channel)
        completeChannelCreated = true
    }

    /**
     * A progress notification is ongoing, so nothing can swipe it away: one left
     * behind by a process the system killed mid-download would sit there until
     * the next reboot. Every download this app knows about is over by the time
     * it starts again, so they all go.
     */
    private fun clearStaleProgressNotifications() {
        notificationManager.activeNotifications
            .filter { it.notification.channelId == PROGRESS_CHANNEL_ID }
            .forEach { notificationManager.cancel(it.id) }
        notificationManager.cancel(GROUP_SUMMARY_ID)
        activeProgress.clear()
    }

    private fun mimeTypeFor(fileName: String): String {
        val ext = fileName.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            ?: "application/octet-stream"
    }

    private fun buildViewIntent(uri: String, fileName: String): Intent =
        Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse(uri), mimeTypeFor(fileName))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }

    /** Hands the saved file to whatever app can display it. */
    private fun openDownload(uri: String, fileName: String) {
        context.startActivity(buildViewIntent(uri, fileName))
    }

    private fun hasPersistedAccess(treeUri: Uri): Boolean =
        resolver.persistedUriPermissions.any {
            it.uri == treeUri && it.isWritePermission && it.isReadPermission
        }

    /** Swallows [SecurityException]: it means the permission is already gone,
     *  so there is nothing left to release. */
    private fun releasePersistedAccess(treeUri: Uri) {
        try {
            resolver.releasePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (_: SecurityException) {
        }
    }

    /** Best-effort display name for a picked tree: what the picker calls it. */
    private fun folderLabel(treeUri: Uri): String {
        val documentUri = DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri)
        )
        resolver.query(
            documentUri,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                cursor.getString(0)?.takeIf { it.isNotEmpty() }?.let { return it }
            }
        }
        return DocumentsContract.getTreeDocumentId(treeUri).substringAfterLast(':')
    }

    /**
     * Saves a downloaded file. [treeUri], when set, is a folder the user picked
     * through the system picker; otherwise the file lands in the platform
     * Downloads folder. [relativePath] is a path below either of them, so a
     * directory transfer keeps its shape instead of dumping every file at the
     * top level. Below Android Q there is no content `Uri` to hand back for a
     * plain Downloads-folder save; a `file://` one would trip StrictMode on
     * the receiving app, so `null` is returned instead.
     */
    private fun saveToDownloads(
        sourcePath: String,
        fileName: String,
        relativePath: String?,
        treeUri: String?
    ): String? {
        val sourceFile = File(sourcePath)
        val mime = mimeTypeFor(fileName)
        val subPath = relativePath
            ?.split('/')
            ?.map { it.trim() }
            ?.filter { it.isNotEmpty() && it != "." && it != ".." }
            ?.joinToString("/")
            ?.takeIf { it.isNotEmpty() }

        if (treeUri != null) {
            return saveToTree(Uri.parse(treeUri), sourceFile, fileName, subPath, mime)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val target = if (subPath == null) {
                Environment.DIRECTORY_DOWNLOADS
            } else {
                "${Environment.DIRECTORY_DOWNLOADS}/$subPath"
            }
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.RELATIVE_PATH, target)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw Exception("Failed to create Downloads entry")
            resolver.openOutputStream(uri)?.use { out ->
                FileInputStream(sourceFile).use { it.copyTo(out) }
            } ?: throw Exception("Failed to open output stream")
            return uri.toString()
        } else {
            var downloadsDir = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS
            )
            if (subPath != null) {
                downloadsDir = File(downloadsDir, subPath)
                if (!downloadsDir.exists() && !downloadsDir.mkdirs()) {
                    throw Exception("Failed to create ${downloadsDir.absolutePath}")
                }
            }
            val dest = uniqueFile(downloadsDir, fileName)
            sourceFile.copyTo(dest, overwrite = false)
            return null
        }
    }

    private fun saveToTree(
        treeUri: Uri,
        sourceFile: File,
        fileName: String,
        subPath: String?,
        mime: String
    ): String {
        if (!hasPersistedAccess(treeUri)) {
            throw FolderUnavailableException("No access to the chosen folder")
        }
        var parent = DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri)
        )
        subPath?.split('/')?.forEach { segment ->
            parent = findOrCreateDirectory(treeUri, parent, segment)
        }

        val target = try {
            DocumentsContract.createDocument(resolver, parent, mime, fileName)
        } catch (e: SecurityException) {
            throw FolderUnavailableException(e.message ?: "Folder is no longer writable")
        } ?: throw Exception("Failed to create $fileName")

        resolver.openOutputStream(target)?.use { out ->
            FileInputStream(sourceFile).use { it.copyTo(out) }
        } ?: throw Exception("Failed to open output stream")
        return target.toString()
    }

    /** Reuses a folder of that name when the tree already has one, so a second
     *  transfer into the same tree does not pile up "site (1)", "site (2)". */
    private fun findOrCreateDirectory(treeUri: Uri, parent: Uri, name: String): Uri {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            parent,
            DocumentsContract.getDocumentId(parent)
        )
        resolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE
            ),
            null,
            null,
            null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val isDirectory =
                    cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR
                if (isDirectory && cursor.getString(1) == name) {
                    return DocumentsContract.buildDocumentUriUsingTree(
                        treeUri,
                        cursor.getString(0)
                    )
                }
            }
        }
        return DocumentsContract.createDocument(
            resolver,
            parent,
            DocumentsContract.Document.MIME_TYPE_DIR,
            name
        ) ?: throw Exception("Failed to create folder $name")
    }

    private fun uniqueFile(dir: File, name: String): File {
        var candidate = File(dir, name)
        if (!candidate.exists()) return candidate

        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var counter = 1
        while (candidate.exists()) {
            candidate = File(dir, "${base} ($counter)$ext")
            counter++
        }
        return candidate
    }

    private fun requestCodeForProgress(id: Int): Int =
        if (id == GROUP_SUMMARY_ID) id xor 1 else id

    private fun requestCodeForCancel(id: Int): Int = id xor 0x33333333

    private fun requestCodeForComplete(id: Int): Int = id xor 0x55555555

    private fun ensureGroupSummary() {
        val summaryIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val summaryPendingIntent = PendingIntent.getActivity(
            context,
            GROUP_SUMMARY_ID,
            summaryIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val summary = NotificationCompat.Builder(context, PROGRESS_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_termphin)
            .setContentIntent(summaryPendingIntent)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setLocalOnly(true)
            .setGroup(GROUP_KEY)
            .setGroupSummary(true)
            .setSilent(true)
            .setAutoCancel(true)
            .build()
        notificationManager.notify(GROUP_SUMMARY_ID, summary)
    }

    /** The summary has no download of its own to end, so it is dismissed by
     *  hand once the last child is gone. */
    private fun dropSummaryIfIdle() {
        if (activeProgress.isEmpty()) notificationManager.cancel(GROUP_SUMMARY_ID)
    }

    private fun showProgress(
        id: Int,
        fileName: String,
        progress: Int,
        channelName: String,
        channelDescription: String,
        cancelLabel: String,
    ) {
        ensureProgressChannel(channelName, channelDescription)
        ensureGroupSummary()
        activeProgress.add(id)

        val tapIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val tapPendingIntent = PendingIntent.getActivity(
            context,
            requestCodeForProgress(id),
            tapIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val cancelIntent = Intent(ACTION_CANCEL_DOWNLOAD).apply {
            setPackage(context.packageName)
            putExtra(EXTRA_DOWNLOAD_ID, id)
        }
        val cancelPendingIntent = PendingIntent.getBroadcast(
            context,
            requestCodeForCancel(id),
            cancelIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(context, PROGRESS_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_termphin)
            .setContentTitle(fileName)
            .setProgress(100, progress, progress == 0)
            .setContentIntent(tapPendingIntent)
            .addAction(0, cancelLabel, cancelPendingIntent)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setLocalOnly(true)
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setGroup(GROUP_KEY)
            .build()
        notificationManager.notify(id, notification)
    }

    private fun cancelProgress(id: Int) {
        notificationManager.cancel(id)
        activeProgress.remove(id)
        dropSummaryIfIdle()
    }

    private fun showComplete(
        id: Int,
        fileName: String,
        uri: String?,
        channelName: String,
        channelDescription: String,
        savedLabel: String,
    ) {
        ensureCompleteChannel(channelName, channelDescription)
        cancelProgress(id)

        val tapIntent = if (uri != null) {
            buildViewIntent(uri, fileName)
        } else {
            Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        }
        val tapPendingIntent = PendingIntent.getActivity(
            context,
            requestCodeForComplete(id),
            tapIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val notification = NotificationCompat.Builder(context, COMPLETE_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_termphin)
            .setContentTitle(fileName)
            .setContentText(savedLabel)
            .setContentIntent(tapPendingIntent)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setLocalOnly(true)
            .setAutoCancel(true)
            .build()
        notificationManager.notify(COMPLETE_TAG, id, notification)
    }
}
