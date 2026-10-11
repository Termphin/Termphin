package dev.termphin.termphin

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The runtime permission that gates talking to anything on the LAN.
 *
 * From Android 17, an app targeting API 37 cannot open a TCP connection to a
 * local-network address without it - and the failure is a timeout rather than
 * a refusal, so an SSH client that does not ask ends up looking broken against
 * every machine on the user's own network. Traffic off the LAN is unaffected,
 * which is why this is asked for on demand and not at startup.
 */
class LocalNetworkChannel(private val activity: Activity) {

    companion object {
        private const val CHANNEL_NAME = "dev.termphin.termphin/local_network"
        private const val REQUEST_CODE = 4137

        /** Below Android 17 nothing gates local traffic, so it is always allowed. */
        private val enforced: Boolean
            get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.CINNAMON_BUN
    }

    private var pending: MethodChannel.Result? = null

    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnforced" -> result.success(enforced)
                    "isGranted" -> result.success(isGranted())
                    "request" -> request(result)
                    "openAppSettings" -> {
                        openAppSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isGranted(): Boolean =
        !enforced ||
            activity.checkSelfPermission(Manifest.permission.ACCESS_LOCAL_NETWORK) ==
            PackageManager.PERMISSION_GRANTED

    /** Refuses a second request while the first dialog is still up, which
     *  would otherwise strand the earlier call with no answer ever arriving. */
    private fun request(result: MethodChannel.Result) {
        if (isGranted()) {
            result.success("granted")
            return
        }
        if (pending != null) {
            result.success("denied")
            return
        }
        pending = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.ACCESS_LOCAL_NETWORK),
            REQUEST_CODE,
        )
    }

    /** True when this was our request; the caller then skips its own handling.
     *  "permanentlyDenied" is only meaningful after a refusal: no rationale to
     *  show and no grant means the system will not put the dialog up again,
     *  so the app's settings page is the only way left in. */
    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pending ?: return true
        pending = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        result.success(
            when {
                granted -> "granted"
                !activity.shouldShowRequestPermissionRationale(
                    Manifest.permission.ACCESS_LOCAL_NETWORK,
                ) -> "permanentlyDenied"
                else -> "denied"
            },
        )
        return true
    }

    private fun openAppSettings() {
        activity.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", activity.packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }
}
