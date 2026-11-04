package com.viniciusnpaula.ultron_mobile

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.AlarmClock
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.roundToInt

class MainActivity : FlutterFragmentActivity(), SensorEventListener {
    companion object {
        private const val CHANNEL = "com.viniciusnpaula.ultron_mobile/device"
        private const val SPEECH_REQUEST_CODE = 9042

        @Volatile
        var isFaceDownGlobal: Boolean = false

        @Volatile
        var isUltronSpeakingGlobal: Boolean = false

        @Volatile
        var lastSpeechEndTimestampMs: Long = 0L

        @Volatile
        var isForegroundRecognizerActive: Boolean = false

        private var instance: MainActivity? = null

        fun notifyWakeWord(phrase: String) {
            instance?.runOnUiThread {
                if (!isUltronSpeakingGlobal && !isForegroundRecognizerActive) {
                    instance?.deviceChannel?.invokeMethod("onWakeWordDetected", phrase)
                }
            }
        }
    }

    private var torchEnabled: Boolean = false
    private var torchCameraId: String? = null
    private var cameraManager: CameraManager? = null
    private var deviceChannel: MethodChannel? = null
    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var isFaceDown: Boolean = false
    private var pendingSpeechResult: MethodChannel.Result? = null
    private var inlineRecognizer: SpeechRecognizer? = null
    private var lastPartialSpeech: String = ""

    private val torchCallback = object : CameraManager.TorchCallback() {
        override fun onTorchModeChanged(cameraId: String, enabled: Boolean) {
            if (cameraId == torchCameraId) {
                torchEnabled = enabled
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        instance = this
        initTorchManager()
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        deviceChannel = channel
        channel.setMethodCallHandler { call, result ->
            try {
                handleDeviceCall(call, result)
            } catch (e: Exception) {
                result.error("DEVICE_ERROR", e.message ?: "Falha na execução nativa Android", null)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        try {
            accelerometer?.let {
                sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
            }
        } catch (_: Exception) {
        }
    }

    override fun onPause() {
        try {
            sensorManager?.unregisterListener(this)
        } catch (_: Exception) {
        }
        super.onPause()
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type != Sensor.TYPE_ACCELEROMETER) return
        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]
        if (z < -8.5f && abs(x) < 3.5f && abs(y) < 3.5f) {
            if (!isFaceDown) {
                isFaceDown = true
                isFaceDownGlobal = true
                deviceChannel?.invokeMethod("onFlipToShush", null)
            }
        } else if (z > 2.5f) {
            isFaceDown = false
            isFaceDownGlobal = false
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SPEECH_REQUEST_CODE) {
            isForegroundRecognizerActive = false
            lastSpeechEndTimestampMs = System.currentTimeMillis()
            val callback = pendingSpeechResult
            pendingSpeechResult = null
            if (callback == null) return
            if (resultCode == Activity.RESULT_OK && data != null) {
                val matches = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                val spoken = matches?.firstOrNull()?.trim() ?: ""
                callback.success(spoken)
            } else {
                callback.success("")
            }
        }
    }

    override fun onDestroy() {
        if (instance == this) instance = null
        destroyInlineRecognizer()
        try {
            sensorManager?.unregisterListener(this)
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
            "listenVoice" -> {
                val prompt = call.argument<String>("prompt") ?: "U.L.T.R.O.N. escutando (fale seu comando)..."
                val locale = call.argument<String>("locale") ?: "pt-BR"
                startVoiceCapture(locale, prompt, result)
            }
            "stopListeningVoice" -> {
                stopInlineRecognizerEarly()
                result.success(true)
            }
            "setUltronSpeaking" -> {
                val speaking = call.argument<Boolean>("speaking") ?: false
                if (!speaking && isUltronSpeakingGlobal) {
                    lastSpeechEndTimestampMs = System.currentTimeMillis()
                }
                isUltronSpeakingGlobal = speaking
                if (!speaking) {
                    UltronTtsHelper.stopAll()
                }
                result.success(true)
            }
            "isNotificationListenerEnabled" -> {
                result.success(isNotificationServiceEnabled())
            }
            "openNotificationListenerSettings" -> {
                val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                result.success(true)
            }
            "getRecentMessages" -> {
                val limit = (call.argument<Int>("limit") ?: 20).coerceIn(1, 40)
                result.success(UltronNotificationService.getRecentMessages(limit))
            }
            "clearRecentMessages" -> {
                UltronNotificationService.clearMessages()
                result.success(true)
            }
            "replyNotification" -> {
                val target = call.argument<String>("target") ?: ""
                val text = call.argument<String>("text") ?: ""
                val statusMsg = UltronNotificationService.replyToMessage(this, target, text)
                result.success(statusMsg)
            }
            "sendWhatsApp" -> {
                val target = call.argument<String>("target") ?: ""
                val text = call.argument<String>("text") ?: ""
                val statusMsg = sendWhatsAppMessage(target, text)
                result.success(statusMsg)
            }
            "sendSms" -> {
                val target = call.argument<String>("target") ?: ""
                val text = call.argument<String>("text") ?: ""
                val statusMsg = sendSmsMessage(target, text)
                result.success(statusMsg)
            }
            "requestContactsPermission" -> {
                val granted = ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.READ_CONTACTS
                ) == PackageManager.PERMISSION_GRANTED
                if (!granted) {
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.READ_CONTACTS),
                        9043
                    )
                }
                result.success(granted)
            }
            "isAudioSentinelRunning" -> {
                result.success(UltronAudioService.isRunning)
            }
            "setAudioSentinel" -> {
                val enable = call.argument<Boolean>("enabled") ?: false
                if (!enable) {
                    stopService(Intent(this, UltronAudioService::class.java))
                    result.success(false)
                } else {
                    val hasMic = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                    if (!hasMic) {
                        val perms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            arrayOf(
                                Manifest.permission.RECORD_AUDIO,
                                Manifest.permission.POST_NOTIFICATIONS
                            )
                        } else {
                            arrayOf(Manifest.permission.RECORD_AUDIO)
                        }
                        ActivityCompat.requestPermissions(this, perms, 9044)
                        result.success(false)
                    } else {
                        val svcIntent = Intent(this, UltronAudioService::class.java)
                        ContextCompat.startForegroundService(this, svcIntent)
                        result.success(true)
                    }
                }
            }
            "speakOfflineFishVoice" -> {
                val text = call.argument<String>("text") ?: ""
                val spoken = UltronTtsHelper.answerQuickOfflineQuery(this, text)
                result.success(spoken)
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

    private fun isNotificationServiceEnabled(): Boolean {
        return try {
            val flat = Settings.Secure.getString(
                contentResolver,
                "enabled_notification_listeners"
            ) ?: return false
            flat.contains(packageName)
        } catch (_: Exception) {
            false
        }
    }

    private fun resolveContactPhone(query: String): Pair<String, String>? {
        val clean = query.trim()
        if (clean.isEmpty()) return null

        // If the query already looks like a phone number
        val digitsOnly = clean.replace(Regex("[^0-9+]"), "")
        if (digitsOnly.length >= 8) {
            return Pair(clean, digitsOnly)
        }

        // Otherwise query Android Contacts if permission is granted
        val hasPerm = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_CONTACTS
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasPerm) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.READ_CONTACTS),
                9043
            )
            return null
        }

        val cursor = contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER
            ),
            "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?",
            arrayOf("%$clean%"),
            "${ContactsContract.CommonDataKinds.Phone.STARRED} DESC"
        )
        cursor?.use {
            if (it.moveToFirst()) {
                val name = it.getString(0) ?: clean
                val rawNum = it.getString(1) ?: ""
                val normalized = rawNum.replace(Regex("[^0-9+]"), "")
                if (normalized.isNotEmpty()) {
                    return Pair(name, normalized)
                }
            }
        }
        return null
    }

    private fun normalizeWhatsAppPhone(rawDigits: String): String {
        val digits = rawDigits.replace(Regex("[^0-9]"), "")
        // Default to Brazil (+55) when 10 or 11 digits are provided without country code
        return if (digits.length in 10..11 && !digits.startsWith("55")) {
            "55$digits"
        } else {
            digits
        }
    }

    private fun sendWhatsAppMessage(target: String, message: String): String {
        val cleanText = message.trim()
        if (cleanText.isEmpty()) {
            throw IllegalArgumentException("Informe o texto da mensagem.")
        }

        // 1. Try background inline reply if there is an active notification from this contact
        if (target.isNotBlank()) {
            try {
                return UltronNotificationService.replyToMessage(this, target, cleanText)
            } catch (_: Exception) {
                // Fall through to WhatsApp deep-link / intent
            }
        }

        // 2. Resolve phone number from target or Contacts
        val resolved = resolveContactPhone(target)
        if (resolved != null) {
            val (contactLabel, rawPhone) = resolved
            val waPhone = normalizeWhatsAppPhone(rawPhone)
            val encodedText = Uri.encode(cleanText)
            val uri = Uri.parse("https://api.whatsapp.com/send?phone=$waPhone&text=$encodedText")
            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            return "WhatsApp aberto diretamente para $contactLabel ($waPhone) com a mensagem pronta."
        }

        // 3. Fallback: Open WhatsApp share chooser with message pre-filled
        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, cleanText)
            setPackage("com.whatsapp")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(sendIntent)
            return "WhatsApp aberto com a mensagem: \"$cleanText\" (selecione o contato)."
        } catch (_: Exception) {
            val encodedText = Uri.encode(cleanText)
            val browserIntent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://api.whatsapp.com/send?text=$encodedText")
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(browserIntent)
            return "Link do WhatsApp aberto com a mensagem: \"$cleanText\"."
        }
    }

    private fun sendSmsMessage(target: String, message: String): String {
        val cleanText = message.trim()
        val resolved = resolveContactPhone(target)
        val phone = resolved?.second ?: target.replace(Regex("[^0-9+]"), "")
        val label = resolved?.first ?: (phone.ifEmpty { "Destinatário" })
        val uri = Uri.parse("smsto:$phone")
        val intent = Intent(Intent.ACTION_SENDTO, uri).apply {
            putExtra("sms_body", cleanText)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
        return "App de SMS aberto para $label com a mensagem: \"$cleanText\"."
    }

    private fun startVoiceCapture(locale: String, prompt: String, result: MethodChannel.Result) {
        // Interrompe imediatamente qualquer fala/TTS do Ultron antes de abrir o microfone
        UltronTtsHelper.stopAll()
        isUltronSpeakingGlobal = false
        isForegroundRecognizerActive = true
        destroyInlineRecognizer()
        pendingSpeechResult?.success("")
        pendingSpeechResult = result
        lastPartialSpeech = ""

        val hasMicPerm = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED

        if (!hasMicPerm) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                9045
            )
            launchSystemSpeechDialog(locale, prompt)
            return
        }

        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            launchSystemSpeechDialog(locale, prompt)
            return
        }

        try {
            val sr = SpeechRecognizer.createSpeechRecognizer(this)
            inlineRecognizer = sr
            var speechStarted = false

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                )
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, locale)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                putExtra(
                    RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                    1800L
                )
                putExtra(
                    RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                    1400L
                )
            }

            sr.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    deviceChannel?.invokeMethod("onSpeechRms", 0.15)
                }

                override fun onBeginningOfSpeech() {
                    speechStarted = true
                }

                override fun onRmsChanged(rmsdB: Float) {
                    val normalized = ((rmsdB + 2.0f) / 12.0f).coerceIn(0.0f, 1.0f).toDouble()
                    deviceChannel?.invokeMethod("onSpeechRms", normalized)
                }

                override fun onBufferReceived(buffer: ByteArray?) {}

                override fun onEndOfSpeech() {
                    deviceChannel?.invokeMethod("onSpeechRms", 0.0)
                }

                override fun onPartialResults(partialResults: Bundle?) {
                    val partials =
                        partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val best = partials?.firstOrNull()?.trim() ?: ""
                    if (best.isNotEmpty()) {
                        lastPartialSpeech = best
                        deviceChannel?.invokeMethod("onSpeechPartial", best)
                    }
                }

                override fun onResults(results: Bundle?) {
                    val matches =
                        results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val best = matches?.firstOrNull()?.trim().orEmpty().ifEmpty { lastPartialSpeech }
                    finishInlineSpeech(best)
                }

                override fun onError(error: Int) {
                    // Se falhou na inicialização do motor antes de começar a falar, usa o diálogo nativo de fallback
                    if (!speechStarted && lastPartialSpeech.isEmpty() &&
                        (error == SpeechRecognizer.ERROR_CLIENT ||
                            error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ||
                            error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY)
                    ) {
                        destroyInlineRecognizer()
                        launchSystemSpeechDialog(locale, prompt)
                        return
                    }
                    // Se o usuário já havia falado algo capturado nos parciais, aproveita o texto parcial!
                    finishInlineSpeech(lastPartialSpeech)
                }

                override fun onEvent(eventType: Int, params: Bundle?) {}
            })

            sr.startListening(intent)
        } catch (_: Exception) {
            destroyInlineRecognizer()
            launchSystemSpeechDialog(locale, prompt)
        }
    }

    private fun finishInlineSpeech(spoken: String) {
        deviceChannel?.invokeMethod("onSpeechRms", 0.0)
        destroyInlineRecognizer()
        isForegroundRecognizerActive = false
        lastSpeechEndTimestampMs = System.currentTimeMillis()
        val cb = pendingSpeechResult
        pendingSpeechResult = null
        cb?.success(spoken.trim())
    }

    private fun stopInlineRecognizerEarly() {
        val sr = inlineRecognizer
        if (sr != null) {
            try {
                sr.stopListening()
            } catch (_: Exception) {
                finishInlineSpeech(lastPartialSpeech)
            }
        }
    }

    private fun destroyInlineRecognizer() {
        try {
            inlineRecognizer?.cancel()
        } catch (_: Exception) {
        }
        try {
            inlineRecognizer?.destroy()
        } catch (_: Exception) {
        }
        inlineRecognizer = null
    }

    private fun launchSystemSpeechDialog(locale: String, prompt: String) {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, locale)
            putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, SPEECH_REQUEST_CODE)
        } catch (e: Exception) {
            isForegroundRecognizerActive = false
            val cb = pendingSpeechResult
            pendingSpeechResult = null
            cb?.error(
                "SPEECH_UNAVAILABLE",
                "Reconhecimento de voz não disponível neste dispositivo (${e.message}).",
                null
            )
        }
    }
}

