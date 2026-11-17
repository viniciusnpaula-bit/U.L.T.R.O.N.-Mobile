package com.viniciusnpaula.ultron_mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var audioCaptureHandler: AudioCaptureHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioCaptureHandler?.release()
        audioCaptureHandler = AudioCaptureHandler(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (audioCaptureHandler?.onRequestPermissionsResult(requestCode, permissions, grantResults) == true) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        audioCaptureHandler?.release()
        audioCaptureHandler = null
        super.onDestroy()
    }
}
