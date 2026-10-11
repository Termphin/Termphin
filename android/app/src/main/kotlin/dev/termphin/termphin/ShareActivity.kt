package dev.termphin.termphin

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Receives shares from other apps and uploads them, on top of the app they
 * came from.
 *
 * It opens in the sharing app's own task with an engine of its own, running
 * `shareMain` rather than the whole app: pick a machine, pick a folder, and
 * once the files are up it finishes and the sharing app is back. The main
 * activity and its sessions are never brought forward. Same process, so the
 * machines, keys and PIN are the ones the app has.
 *
 * A FragmentActivity for the same reason as [MainActivity]: the biometric
 * unlock on the lock screen needs one.
 */
class ShareActivity : FlutterFragmentActivity() {

    private var shareChannel: ShareChannel? = null
    private var localNetworkChannel: LocalNetworkChannel? = null

    override fun getDartEntrypointFunctionName(): String = "shareMain"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = ShareChannel(this, intent).also { it.register(flutterEngine) }
        localNetworkChannel = LocalNetworkChannel(this).also { it.register(flutterEngine) }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (localNetworkChannel?.onRequestPermissionsResult(requestCode, grantResults) == true) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        super.cleanUpFlutterEngine(flutterEngine)
        shareChannel?.dispose()
        shareChannel = null
        localNetworkChannel = null
    }
}
