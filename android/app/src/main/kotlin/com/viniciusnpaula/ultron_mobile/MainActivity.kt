package com.viniciusnpaula.ultron_mobile

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val ACTIONS_CHANNEL = "com.viniciusnpaula.ultron_mobile/android_actions"
    }

    private var audioCaptureHandler: AudioCaptureHandler? = null
    private var actionsChannel: MethodChannel? = null
    private var pendingTileAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureTileIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureTileIntent(intent)
    }

    private fun captureTileIntent(intent: Intent?) {
        if (intent?.action != UltronTileService.ACTION_TILE_LAUNCH) return
        val action = intent.getStringExtra(UltronTileService.EXTRA_TILE_ACTION)
        if (!action.isNullOrBlank()) {
            pendingTileAction = action
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioCaptureHandler?.release()
        audioCaptureHandler = AudioCaptureHandler(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )

        actionsChannel?.setMethodCallHandler(null)
        actionsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ACTIONS_CHANNEL,
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumePendingTileAction" -> {
                        val action = pendingTileAction
                        pendingTileAction = null
                        result.success(action)
                    }
                    "isNotificationAccessGranted" -> {
                        val granted = NotificationManagerCompat
                            .getEnabledListenerPackages(this@MainActivity)
                            .contains(packageName)
                        result.success(granted)
                    }
                    "openNotificationAccessSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success(null)
                    }
                    "readRecentNotifications" -> {
                        val granted = NotificationManagerCompat
                            .getEnabledListenerPackages(this@MainActivity)
                            .contains(packageName)
                        if (!granted) {
                            result.success(emptyList<Map<String, Any?>>())
                        } else {
                            result.success(UltronNotificationListenerService.snapshotRecent())
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
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
        actionsChannel?.setMethodCallHandler(null)
        actionsChannel = null
        audioCaptureHandler?.release()
        audioCaptureHandler = null
        super.onDestroy()
    }
}
