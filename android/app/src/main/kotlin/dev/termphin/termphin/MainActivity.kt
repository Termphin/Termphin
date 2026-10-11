package dev.termphin.termphin

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    private var downloadChannel: DownloadChannel? = null
    private var localNetworkChannel: LocalNetworkChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        downloadChannel = DownloadChannel(this).also { it.register(flutterEngine) }
        localNetworkChannel = LocalNetworkChannel(this).also { it.register(flutterEngine) }
        SystemSettingsChannel(this).register(flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        window.decorView.requestApplyInsets()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            window.decorView.requestApplyInsets()
        }
    }

    /** The folder picker is a system activity, so its answer arrives here. */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (downloadChannel?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    /** Same for the permission dialog. The super call still runs for anything
     *  not ours - the plugins request permissions of their own. */
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
        downloadChannel = null
        localNetworkChannel = null
    }
}
