package com.viniciusnpaula.ultron_mobile

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.AlarmClock
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val CHANNEL = "com.viniciusnpaula.ultron_mobile/device"
    }

    private var torchEnabled: Boolean = false
    private var torchCameraId: String? = null
    private var cameraManager: CameraManager? = null

    private val torchCallback = object : CameraManager.TorchCallback() {
        override fun onTorchModeChanged(cameraId: String, enabled: Boolean) {
            if (cameraId == torchCameraId) {
                torchEnabled = enabled
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initTorchManager()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    handleDeviceCall(call, result)
                } catch (e: Exception) {
                    result.error("DEVICE_ERROR", e.message ?: "Falha na execução nativa Android", null)
                }
            }
    }

    override fun onDestroy() {
        try {
            cameraManager?.unregisterTorchCallback(torchCallback)
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    private fun initTorchManager() {
        try {
            val cm = getSystemService(Context.CAMERA_SERVICE) as? CameraManager ?: return
            cameraManager = cm
            torchCameraId = cm.cameraIdList.firstOrNull { id ->
                cm.getCameraCharacteristics(id).get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            } ?: cm.cameraIdList.firstOrNull()
            cm.registerTorchCallback(torchCallback, null)
        } catch (_: Exception) {
        }
    }

    private fun handleDeviceCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setTorch" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val state = setTorchInternal(enabled)
                result.success(state)
            }
            "toggleTorch" -> {
                val state = setTorchInternal(!torchEnabled)
                result.success(state)
            }
            "getDeviceStatus" -> {
                result.success(readDeviceStatus())
            }
            "setVolume" -> {
                val percent = (call.argument<Int>("percent") ?: 50).coerceIn(0, 100)
                val updated = setMediaVolumePercent(percent)
                result.success(updated)
            }
            "adjustVolume" -> {
                val direction = call.argument<String>("direction") ?: "up"
                val updated = adjustMediaVolume(direction)
                result.success(updated)
            }
            "vibrate" -> {
                val durationMs = (call.argument<Int>("durationMs") ?: 180).coerceIn(20, 3000)
                triggerVibration(durationMs.toLong())
                result.success(true)
            }
            "openSystemSettings" -> {
                val target = call.argument<String>("target") ?: "general"
                val opened = openSettingsPanel(target)
                result.success(opened)
            }
            "openApp" -> {
                val target = call.argument<String>("target") ?: ""
                val openedLabel = launchInstalledApp(target)
                result.success(openedLabel)
            }
            "setAlarm" -> {
                val hour = (call.argument<Int>("hour") ?: 7).coerceIn(0, 23)
                val minute = (call.argument<Int>("minute") ?: 0).coerceIn(0, 59)
                val message = call.argument<String>("message") ?: "U.L.T.R.O.N."
                val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                    putExtra(AlarmClock.EXTRA_HOUR, hour)
                    putExtra(AlarmClock.EXTRA_MINUTES, minute)
                    putExtra(AlarmClock.EXTRA_MESSAGE, message)
                    putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                result.success(true)
            }
            "setTimer" -> {
                val seconds = (call.argument<Int>("seconds") ?: 60).coerceAtLeast(1)
                val message = call.argument<String>("message") ?: "U.L.T.R.O.N. Timer"
                val intent = Intent(AlarmClock.ACTION_SET_TIMER).apply {
                    putExtra(AlarmClock.EXTRA_LENGTH, seconds)
                    putExtra(AlarmClock.EXTRA_MESSAGE, message)
                    putExtra(AlarmClock.EXTRA_SKIP_UI, false)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                result.success(true)
            }
            "openUrl" -> {
                val rawUrl = call.argument<String>("url") ?: ""
                val uri = Uri.parse(rawUrl)
                val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                result.success(true)
            }
            "dialNumber" -> {
                val number = (call.argument<String>("number") ?: "").replace(Regex("[^0-9+*#]"), "")
                val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number")).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                result.success(true)
            }
            "shareText" -> {
                val text = call.argument<String>("text") ?: ""
                val sendIntent = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, text)
                }
                val chooser = Intent.createChooser(sendIntent, "Compartilhar via U.L.T.R.O.N.").apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(chooser)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun setTorchInternal(enabled: Boolean): Boolean {
        if (cameraManager == null || torchCameraId == null) {
            initTorchManager()
        }
        val cm = cameraManager ?: throw IllegalStateException("CameraManager indisponível neste aparelho.")
        val id = torchCameraId ?: throw IllegalStateException("Flash/Lanterna não encontrado.")
        cm.setTorchMode(id, enabled)
        torchEnabled = enabled
        return torchEnabled
    }

    private fun setMediaVolumePercent(percent: Int): Int {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val targetIndex = ((percent / 100.0) * max).roundToInt().coerceIn(0, max)
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, targetIndex, AudioManager.FLAG_SHOW_UI)
        return ((targetIndex.toDouble() / max) * 100.0).roundToInt()
    }

    private fun adjustMediaVolume(direction: String): Int {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        when (direction.lowercase()) {
            "up" -> audio.adjustStreamVolume(
                AudioManager.STREAM_MUSIC,
                AudioManager.ADJUST_RAISE,
                AudioManager.FLAG_SHOW_UI
            )
            "down" -> audio.adjustStreamVolume(
                AudioManager.STREAM_MUSIC,
                AudioManager.ADJUST_LOWER,
                AudioManager.FLAG_SHOW_UI
            )
            "mute" -> audio.adjustStreamVolume(
                AudioManager.STREAM_MUSIC,
                AudioManager.ADJUST_MUTE,
                AudioManager.FLAG_SHOW_UI
            )
            "unmute" -> audio.adjustStreamVolume(
                AudioManager.STREAM_MUSIC,
                AudioManager.ADJUST_UNMUTE,
                AudioManager.FLAG_SHOW_UI
            )
        }
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val cur = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        return ((cur.toDouble() / max) * 100.0).roundToInt()
    }

    private fun triggerVibration(durationMs: Long) {
        val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            vm?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        if (vibrator == null || !vibrator.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(
                VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE)
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(durationMs)
        }
    }

    private fun openSettingsPanel(target: String): Boolean {
        val action = when (target.lowercase()) {
            "wifi" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                Settings.Panel.ACTION_WIFI
            } else {
                Settings.ACTION_WIFI_SETTINGS
            }
            "internet", "internet_panel" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                Settings.Panel.ACTION_INTERNET_CONNECTIVITY
            } else {
                Settings.ACTION_WIFI_SETTINGS
            }
            "volume_panel" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                Settings.Panel.ACTION_VOLUME
            } else {
                Settings.ACTION_SOUND_SETTINGS
            }
            "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
            "display", "brilho", "tela" -> Settings.ACTION_DISPLAY_SETTINGS
            "sound", "som", "audio" -> Settings.ACTION_SOUND_SETTINGS
            "battery", "bateria" -> Settings.ACTION_BATTERY_SAVER_SETTINGS
            "location", "gps", "localizacao" -> Settings.ACTION_LOCATION_SOURCE_SETTINGS
            "security", "seguranca", "biometria" -> Settings.ACTION_SECURITY_SETTINGS
            "apps", "aplicativos" -> Settings.ACTION_APPLICATION_SETTINGS
            else -> Settings.ACTION_SETTINGS
        }
        val intent = Intent(action).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
        return true
    }

    private fun launchInstalledApp(rawQuery: String): String {
        val query = rawQuery.trim().lowercase()
        if (query.isEmpty()) throw IllegalArgumentException("Informe o nome do aplicativo.")

        // 1. Built-in system actions
        when (query) {
            "camera", "câmera", "foto" -> {
                val intent = Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                return "Câmera"
            }
            "configuracoes", "configurações", "ajustes", "settings" -> {
                openSettingsPanel("general")
                return "Configurações"
            }
            "wifi", "wi-fi" -> {
                openSettingsPanel("wifi")
                return "Painel Wi-Fi"
            }
            "bluetooth" -> {
                openSettingsPanel("bluetooth")
                return "Bluetooth"
            }
            "telefone", "discador", "chamada" -> {
                val intent = Intent(Intent.ACTION_DIAL).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                return "Telefone"
            }
            "relogio", "relógio", "alarme", "despertador" -> {
                val intent = Intent(AlarmClock.ACTION_SHOW_ALARMS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                return "Relógio / Alarmes"
            }
            "navegador", "browser", "internet" -> {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com")).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                return "Navegador"
            }
        }

        // 2. Known package aliases
        val knownPackages = mapOf(
            "whatsapp" to listOf("com.whatsapp", "com.whatsapp.w4b"),
            "youtube" to listOf("com.google.android.youtube"),
            "instagram" to listOf("com.instagram.android"),
            "chrome" to listOf("com.android.chrome"),
            "spotify" to listOf("com.spotify.music"),
            "gmail" to listOf("com.google.android.gm"),
            "maps" to listOf("com.google.android.apps.maps"),
            "mapa" to listOf("com.google.android.apps.maps"),
            "mapas" to listOf("com.google.android.apps.maps"),
            "telegram" to listOf("org.telegram.messenger", "org.telegram.messenger.web"),
            "calculadora" to listOf("com.sec.android.app.popupcalculator", "com.google.android.calculator"),
            "galeria" to listOf("com.sec.android.gallery3d", "com.google.android.apps.photos"),
            "fotos" to listOf("com.google.android.apps.photos", "com.sec.android.gallery3d"),
            "arquivos" to listOf("com.sec.android.app.myfiles", "com.google.android.apps.nbu.files"),
            "play store" to listOf("com.android.vending"),
            "tiktok" to listOf("com.zhiliaoapp.musically"),
            "netflix" to listOf("com.netflix.mediaclient")
        )

        val pm = packageManager
        knownPackages[query]?.forEach { pkg ->
            val launch = pm.getLaunchIntentForPackage(pkg)
            if (launch != null) {
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(launch)
                return query.replaceFirstChar { it.uppercase() }
            }
        }

        // 3. Search all installed launcher activities by label or package name
        val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val resolveInfos = pm.queryIntentActivities(mainIntent, 0)
        for (info in resolveInfos) {
            val label = info.loadLabel(pm).toString()
            val pkg = info.activityInfo.packageName
            if (label.lowercase().contains(query) || pkg.lowercase().contains(query)) {
                val launch = pm.getLaunchIntentForPackage(pkg)
                if (launch != null) {
                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(launch)
                    return label
                }
            }
        }

        throw IllegalStateException("Aplicativo '$rawQuery' não encontrado no dispositivo.")
    }

    private fun readDeviceStatus(): Map<String, Any> {
        // Battery
        val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        val batteryIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            ?: batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            ?: -1
        val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
        val tempTenths = batteryIntent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0
        val tempC = tempTenths / 10.0

        // Audio
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxVol = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val curVol = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        val volumePercent = ((curVol.toDouble() / maxVol) * 100.0).roundToInt()
        val ringerMode = when (audio.ringerMode) {
            AudioManager.RINGER_MODE_SILENT -> "SILENCIOSO"
            AudioManager.RINGER_MODE_VIBRATE -> "VIBRAR"
            else -> "NORMAL"
        }

        // Memory (RAM)
        val actManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        actManager.getMemoryInfo(memInfo)
        val ramTotalMb = (memInfo.totalMem / (1024 * 1024)).toInt()
        val ramFreeMb = (memInfo.availMem / (1024 * 1024)).toInt()
        val ramUsedMb = (ramTotalMb - ramFreeMb).coerceAtLeast(0)

        // Connectivity
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        val capabilities = cm?.getNetworkCapabilities(cm.activeNetwork)
        val wifiConnected = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        val cellularConnected = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true

        val manufacturer = Build.MANUFACTURER.uppercase()
        val model = Build.MODEL
        val deviceModel = if (model.uppercase().startsWith(manufacturer)) model else "$manufacturer $model"

        return mapOf(
            "batteryLevel" to level,
            "isCharging" to isCharging,
            "batteryTempC" to tempC,
            "torchOn" to torchEnabled,
            "volumePercent" to volumePercent,
            "ringerMode" to ringerMode,
            "ramUsedMb" to ramUsedMb,
            "ramTotalMb" to ramTotalMb,
            "ramFreeMb" to ramFreeMb,
            "deviceModel" to deviceModel,
            "androidVersion" to "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
            "wifiConnected" to wifiConnected,
            "cellularConnected" to cellularConnected
        )
    }
}

