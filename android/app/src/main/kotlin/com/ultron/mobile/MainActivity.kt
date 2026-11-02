package com.ultron.mobile

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "ultron.mobile/update"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                if (call.method == "openReleases") {
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://github.com/viniciusnpaula-bit/U.L.T.R.O.N.-Mobile/releases/latest")))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("UPDATE_LINK", e.message, null)
                    }
                } else result.notImplemented()
            }
    }
}
