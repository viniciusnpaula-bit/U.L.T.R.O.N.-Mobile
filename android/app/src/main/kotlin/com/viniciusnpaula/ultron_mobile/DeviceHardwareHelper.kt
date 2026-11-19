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
import android.os.Environment
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.AlarmClock
import android.provider.MediaStore
import android.provider.Settings
import android.view.KeyEvent
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Ações de hardware e sistema Android compartilhadas entre [MainActivity] (1º plano)
 * e [BackgroundVoiceResponder] (2º plano), evitando lógica duplicada.
 */
object DeviceHardwareHelper {
    @Volatile
    var torchEnabled: Boolean = false
        private set

    @Volatile
    private var torchCameraId: String? = null

    private var cameraManager: CameraManager? = null
    private var callbackRegistered = false

    private val torchCallback = object : CameraManager.TorchCallback() {
        override fun onTorchModeChanged(cameraId: String, enabled: Boolean) {
            if (cameraId == torchCameraId) {
                torchEnabled = enabled
            }
        }
    }

    fun initTorch(context: Context) {
        try {
            val cm = context.applicationContext.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
                ?: return
            cameraManager = cm
            torchCameraId = cm.cameraIdList.firstOrNull { id ->
                cm.getCameraCharacteristics(id).get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            } ?: cm.cameraIdList.firstOrNull()
            if (!callbackRegistered) {
                cm.registerTorchCallback(torchCallback, null)
                callbackRegistered = true
            }
        } catch (_: Exception) {
        }
    }

    fun releaseTorch() {
        try {
            if (callbackRegistered) {
                cameraManager?.unregisterTorchCallback(torchCallback)
                callbackRegistered = false
            }
        } catch (_: Exception) {
        }
    }

    fun setTorch(context: Context, enabled: Boolean): Boolean {
        if (cameraManager == null || torchCameraId == null) {
            initTorch(context)
        }
        val cm = cameraManager ?: throw IllegalStateException("CameraManager indisponível neste aparelho.")
        val id = torchCameraId ?: throw IllegalStateException("Flash/Lanterna não encontrado.")
        cm.setTorchMode(id, enabled)
        torchEnabled = enabled
        return torchEnabled
    }

    fun toggleTorch(context: Context): Boolean = setTorch(context, !torchEnabled)

    fun setMediaVolumePercent(context: Context, percent: Int, showUi: Boolean = true): Int {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val targetIndex = ((percent.coerceIn(0, 100) / 100.0) * max).roundToInt().coerceIn(0, max)
        val flags = if (showUi) AudioManager.FLAG_SHOW_UI else 0
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, targetIndex, flags)
        return ((targetIndex.toDouble() / max) * 100.0).roundToInt()
    }

    fun adjustMediaVolume(context: Context, direction: String, showUi: Boolean = true): Int {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val flags = if (showUi) AudioManager.FLAG_SHOW_UI else 0
        when (direction.lowercase()) {
            "up" -> audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_RAISE, flags)
            "down" -> audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_LOWER, flags)
            "mute" -> audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_MUTE, flags)
            "unmute" -> audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_UNMUTE, flags)
        }
        val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val cur = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        return ((cur.toDouble() / max) * 100.0).roundToInt()
    }

    fun dispatchMediaControl(context: Context, action: String): Boolean {
        val keyCode = when (action.trim().lowercase()) {
            "play" -> KeyEvent.KEYCODE_MEDIA_PLAY
            "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
            "play_pause", "toggle" -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
            "previous", "prev" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            "stop" -> KeyEvent.KEYCODE_MEDIA_STOP
            else -> return false
        }
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
        val eventTime = SystemClock.uptimeMillis()
        audio.dispatchMediaKeyEvent(KeyEvent(eventTime, eventTime, KeyEvent.ACTION_DOWN, keyCode, 0))
        audio.dispatchMediaKeyEvent(KeyEvent(eventTime, eventTime, KeyEvent.ACTION_UP, keyCode, 0))
        return true
    }

    fun triggerVibration(context: Context, durationMs: Long) {
        val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            vm?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
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

    fun openSettingsPanel(context: Context, target: String): Boolean {
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
        context.startActivity(intent)
        return true
    }

    private val trailingCourtesyRegex = Regex(
        """(?:\s+(?:para\s+mim|pra\s+mim|por\s+favor|por\s+gentileza|pfv|aqui|a[ií]|agora|r[aá]pido|logo|se\s+puder|se\s+conseguir|por\s+obs[eé]quio|ok|t[aá]|viu|ultron))+$""",
        RegexOption.IGNORE_CASE,
    )

    private val leadingArticleRegex = Regex(
        """^(?:o|a|os|as|um|uma|app|aplicativo)\s+""",
        RegexOption.IGNORE_CASE,
    )

    fun sanitizeAppQuery(rawQuery: String): String {
        var cleaned = rawQuery.trim()
            .trimEnd('.', '!', '?', ',', ';', ':')
            .trim()
        var prev: String
        do {
            prev = cleaned
            cleaned = trailingCourtesyRegex.replace(cleaned, "").trim()
            cleaned = leadingArticleRegex.replace(cleaned, "").trim()
        } while (cleaned != prev && cleaned.isNotEmpty())
        return cleaned
    }

    fun listInstalledAppSample(context: Context, limit: Int = 30): List<String> {
        return try {
            val pm = context.packageManager
            val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            pm.queryIntentActivities(mainIntent, 0)
                .mapNotNull { it.loadLabel(pm)?.toString()?.trim() }
                .filter { it.isNotBlank() }
                .distinct()
                .sorted()
                .take(limit)
        } catch (_: Throwable) {
            emptyList()
        }
    }

    fun launchInstalledApp(context: Context, rawQuery: String): String {
        val query = sanitizeAppQuery(rawQuery).lowercase()
        if (query.isEmpty()) throw IllegalArgumentException("Informe o nome do aplicativo.")

        when (query) {
            "camera", "câmera", "foto" -> {
                val intent = Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                return "Câmera"
            }
            "configuracoes", "configurações", "ajustes", "settings" -> {
                openSettingsPanel(context, "general")
                return "Configurações"
            }
            "wifi", "wi-fi" -> {
                openSettingsPanel(context, "wifi")
                return "Painel Wi-Fi"
            }
            "bluetooth" -> {
                openSettingsPanel(context, "bluetooth")
                return "Bluetooth"
            }
            "telefone", "discador", "chamada" -> {
                val intent = Intent(Intent.ACTION_DIAL).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                return "Telefone"
            }
            "relogio", "relógio", "alarme", "despertador" -> {
                val intent = Intent(AlarmClock.ACTION_SHOW_ALARMS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                return "Relógio / Alarmes"
            }
            "navegador", "browser", "internet" -> {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com")).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                return "Navegador"
            }
        }

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
            "netflix" to listOf("com.netflix.mediaclient"),
            "obsidian" to listOf("md.obsidian")
        )

        val pm = context.packageManager
        knownPackages[query]?.forEach { pkg ->
            val launch = pm.getLaunchIntentForPackage(pkg)
            if (launch != null) {
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(launch)
                return query.replaceFirstChar { it.uppercase() }
            }
        }

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
                    context.startActivity(launch)
                    return label
                }
            }
        }

        throw IllegalStateException("Aplicativo '$rawQuery' não encontrado no dispositivo.")
    }

    fun setAlarm(context: Context, hour: Int, minute: Int, message: String, skipUi: Boolean = false) {
        val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
            putExtra(AlarmClock.EXTRA_HOUR, hour.coerceIn(0, 23))
            putExtra(AlarmClock.EXTRA_MINUTES, minute.coerceIn(0, 59))
            putExtra(AlarmClock.EXTRA_MESSAGE, message.ifBlank { "U.L.T.R.O.N." })
            putExtra(AlarmClock.EXTRA_SKIP_UI, skipUi)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    fun setTimer(context: Context, seconds: Int, message: String, skipUi: Boolean = false) {
        val intent = Intent(AlarmClock.ACTION_SET_TIMER).apply {
            putExtra(AlarmClock.EXTRA_LENGTH, seconds.coerceAtLeast(1))
            putExtra(AlarmClock.EXTRA_MESSAGE, message.ifBlank { "U.L.T.R.O.N. Timer" })
            putExtra(AlarmClock.EXTRA_SKIP_UI, skipUi)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    fun openUrl(context: Context, rawUrl: String) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(rawUrl)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    fun dialNumber(context: Context, rawNumber: String) {
        val number = rawNumber.replace(Regex("[^0-9+*#]"), "")
        val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number")).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    fun appendObsidianEntry(context: Context, subfolder: String, prefix: String, text: String): String? {
        val clean = text.trim()
        if (clean.isEmpty()) return null
        val publicDocs = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
        val candidates = listOfNotNull(
            File(publicDocs, "ULTRON-Vault"),
            File(publicDocs, "Obsidian/ULTRON-Vault"),
            context.filesDir.parentFile?.let { File(it, "app_flutter/ULTRON-Vault") },
        )
        for (root in candidates) {
            try {
                val targetDir = File(root, subfolder)
                if (!targetDir.exists()) targetDir.mkdirs()
                val dateName = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
                val timeStr = SimpleDateFormat("HH:mm", Locale.US).format(Date())
                val file = if (subfolder == "Inbox") {
                    File(targetDir, "Inbox.md")
                } else {
                    File(targetDir, "$dateName.md")
                }
                file.appendText("\n- [$timeStr] $prefix$clean\n")
                return file.name
            } catch (_: Throwable) {
            }
        }
        return null
    }

    fun readDeviceStatus(context: Context): Map<String, Any> {
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        val batteryIntent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            ?: batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            ?: -1
        val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
        val tempTenths = batteryIntent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0
        val tempC = tempTenths / 10.0

        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxVol = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val curVol = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        val volumePercent = ((curVol.toDouble() / maxVol) * 100.0).roundToInt()
        val ringerMode = when (audio.ringerMode) {
            AudioManager.RINGER_MODE_SILENT -> "SILENCIOSO"
            AudioManager.RINGER_MODE_VIBRATE -> "VIBRAR"
            else -> "NORMAL"
        }

        val actManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        actManager.getMemoryInfo(memInfo)
        val ramTotalMb = (memInfo.totalMem / (1024 * 1024)).toInt()
        val ramFreeMb = (memInfo.availMem / (1024 * 1024)).toInt()
        val ramUsedMb = (ramTotalMb - ramFreeMb).coerceAtLeast(0)

        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
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
