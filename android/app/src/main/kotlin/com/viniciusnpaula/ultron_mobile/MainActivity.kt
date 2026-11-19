package com.viniciusnpaula.ultron_mobile

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.media.ExifInterface
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.Settings
import android.util.Base64
import android.view.KeyEvent
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.TimeZone
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

class MainActivity : FlutterFragmentActivity(), SensorEventListener {
    companion object {
        private const val CHANNEL = "com.viniciusnpaula.ultron_mobile/device"
        private const val ACTIONS_CHANNEL = "com.viniciusnpaula.ultron_mobile/android_actions"

        @Volatile
        var isFaceDownGlobal: Boolean = false

        @Volatile
        var isUltronSpeakingGlobal: Boolean = false

        @Volatile
        var lastSpeechEndTimestampMs: Long = 0L

        @Volatile
        var isForegroundRecognizerActive: Boolean = false

        @Volatile
        var isForegroundCaptureActive: Boolean = false

        @Volatile
        var isActivityResumed: Boolean = false

        private const val PENDING_WAKE_TTL_MS = 90_000L
        private const val VISION_CAMERA_REQUEST_CODE = 9101
        private const val VISION_GALLERY_REQUEST_CODE = 9102
        private const val VISION_CAMERA_PERM_REQUEST_CODE = 9103
        private const val CALENDAR_PERM_REQUEST_CODE = 9104
        private const val VISION_MAX_DIM_PX = 1024
        private const val VISION_JPEG_QUALITY = 82

        private var instance: MainActivity? = null

        @Volatile
        private var pendingWakeWord: String? = null

        @Volatile
        private var pendingWakeTimestampMs: Long = 0L

        /**
         * Registra a wake word como PENDENTE (nunca é descartada por Activity ausente) e tenta
         * entregá-la ao Flutter. Só é removida quando o Flutter a consome com sucesso.
         */
        fun notifyWakeWord(phrase: String) {
            pendingWakeWord = phrase
            pendingWakeTimestampMs = System.currentTimeMillis()
            instance?.runOnUiThread { instance?.deliverPendingWakeWord() }
        }

        /** Retorna e limpa a wake word pendente se ainda estiver fresca (30 s). */
        fun consumePendingWakeWord(): String? {
            val phrase = pendingWakeWord ?: return null
            val fresh = System.currentTimeMillis() - pendingWakeTimestampMs <= PENDING_WAKE_TTL_MS
            pendingWakeWord = null
            return if (fresh) phrase else null
        }

        /** Notifica o Flutter (se vivo em memória) que há novos turnos gravados em 2º plano. */
        fun notifyBackgroundTurn() {
            instance?.runOnUiThread {
                instance?.deviceChannel?.invokeMethod("onBackgroundTurnAvailable", null)
            }
        }
    }

    /** Entrega a wake word pendente ao Flutter; só consome quando a Activity está em 1º plano. */
    private fun deliverPendingWakeWord() {
        if (!isActivityResumed || isUltronSpeakingGlobal || isForegroundRecognizerActive) return
        val channel = deviceChannel ?: return
        val phrase = consumePendingWakeWord() ?: return
        channel.invokeMethod("onWakeWordDetected", phrase, object : MethodChannel.Result {
            override fun success(result: Any?) {}
            override fun error(code: String, message: String?, details: Any?) {
                restorePendingWakeWord(phrase)
            }
            override fun notImplemented() {
                // Dart ainda sem handler (engine subindo): mantém pendente para o consumo no init.
                restorePendingWakeWord(phrase)
            }
        })
    }

    private fun restorePendingWakeWord(phrase: String) {
        if (pendingWakeWord == null) {
            pendingWakeWord = phrase
            pendingWakeTimestampMs = System.currentTimeMillis()
        }
    }

    private fun startSentinelService() {
        try {
            ContextCompat.startForegroundService(this, Intent(this, UltronAudioService::class.java))
        } catch (e: Exception) {
            wakeLogW("não foi possível iniciar o sentinela: ${e.javaClass.simpleName}")
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (audioCaptureHandler?.onRequestPermissionsResult(requestCode, permissions, grantResults) == true) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 9044) {
            val micGranted = ContextCompat.checkSelfPermission(
                this, Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
            if (micGranted && !UltronAudioService.isRunning) startSentinelService()
        } else if (requestCode == VISION_CAMERA_PERM_REQUEST_CODE) {
            val camGranted = ContextCompat.checkSelfPermission(
                this, Manifest.permission.CAMERA
            ) == PackageManager.PERMISSION_GRANTED
            val pending = pendingVisionResult
            if (camGranted && pending != null) {
                startVisionCapture("camera", pending)
            } else {
                pendingVisionResult = null
                pending?.error("PERMISSION_DENIED", "Permissão de câmera negada para Visão Multimodal.", null)
            }
        } else if (requestCode == CALENDAR_PERM_REQUEST_CODE) {
            val readGranted = ContextCompat.checkSelfPermission(
                this, Manifest.permission.READ_CALENDAR
            ) == PackageManager.PERMISSION_GRANTED
            val op = pendingCalendarOperation
            val pending = pendingCalendarResult
            pendingCalendarOperation = null
            pendingCalendarResult = null
            if (readGranted && op != null) {
                op.invoke()
            } else {
                pending?.error("CALENDAR_PERMISSION_DENIED", "Permissão de Agenda (Calendário) negada.", null)
            }
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VISION_CAMERA_REQUEST_CODE && requestCode != VISION_GALLERY_REQUEST_CODE) {
            return
        }
        val pending = pendingVisionResult ?: return
        pendingVisionResult = null
        val source = if (requestCode == VISION_CAMERA_REQUEST_CODE) "camera" else "gallery"
        if (resultCode != Activity.RESULT_OK) {
            pendingVisionCameraUri = null
            pending.success(null)
            return
        }
        val uri = if (requestCode == VISION_CAMERA_REQUEST_CODE) {
            pendingVisionCameraUri
        } else {
            data?.data
        }
        pendingVisionCameraUri = null
        if (uri == null) {
            pending.success(null)
            return
        }
        Thread {
            try {
                val payload = decodeAndCompressVisionImage(uri, source)
                runOnUiThread {
                    if (payload == null) {
                        pending.error("VISION_DECODE_FAILED", "Não foi possível decodificar a imagem.", null)
                    } else {
                        pending.success(payload)
                    }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    pending.error("VISION_ERROR", e.message ?: "Falha ao processar imagem.", null)
                }
            } finally {
                if (requestCode == VISION_CAMERA_REQUEST_CODE) {
                    safely("cleanupVisionTemp") {
                        File(cacheDir, "vision").listFiles()?.forEach { it.delete() }
                    }
                }
            }
        }.start()
    }

    /** Permite abrir sobre a tela de bloqueio quando a ativação por voz acorda o app. */
    private fun applyLockScreenMode(enable: Boolean) {
        safely("applyLockScreenMode") {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(enable)
                setTurnScreenOn(enable)
            }
        }
    }

    private fun handleWakeIntent(intent: Intent?) {
        if (intent?.getBooleanExtra(UltronAudioService.EXTRA_WAKE_WORD, false) == true) {
            applyLockScreenMode(true)
            intent.removeExtra(UltronAudioService.EXTRA_WAKE_WORD)
        }
        if (intent?.getBooleanExtra(BootReceiver.EXTRA_REARM_SENTINEL, false) == true) {
            intent.removeExtra(BootReceiver.EXTRA_REARM_SENTINEL)
            val hasMic = ContextCompat.checkSelfPermission(
                this, Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
            if (hasMic) {
                startSentinelService()
            }
        }
    }

    private fun captureTileIntent(intent: Intent?) {
        if (intent?.action != UltronTileService.ACTION_TILE_LAUNCH) {
            pendingTileAction = null
            return
        }
        val action = intent.getStringExtra(UltronTileService.EXTRA_TILE_ACTION)
        if (!action.isNullOrBlank()) {
            pendingTileAction = action
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        captureTileIntent(intent)
        handleWakeIntent(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureTileIntent(intent)
        handleWakeIntent(intent)
    }

    private var audioCaptureHandler: AudioCaptureHandler? = null
    private var actionsChannel: MethodChannel? = null
    private var pendingTileAction: String? = null
    private var deviceChannel: MethodChannel? = null
    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var isFaceDown: Boolean = false
    private var pendingVisionResult: MethodChannel.Result? = null
    private var pendingVisionCameraUri: Uri? = null
    private var pendingCalendarOperation: (() -> Unit)? = null
    private var pendingCalendarResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        instance = this
        DeviceHardwareHelper.initTorch(this)
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
                        result.success(isNotificationServiceEnabled())
                    }
                    "openNotificationAccessSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success(null)
                    }
                    "readRecentNotifications" -> {
                        if (!isNotificationServiceEnabled()) {
                            result.success(emptyList<Map<String, Any?>>())
                        } else {
                            result.success(UltronNotificationService.getRecentMessages(20))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        isActivityResumed = true
        // Se o sentinela estava habilitado pelo operador, garante retomada ao reabrir o app.
        val sentinelPrefs = getSharedPreferences(UltronAudioService.PREFS_NAME, Context.MODE_PRIVATE)
        if (sentinelPrefs.getBoolean(UltronAudioService.PREF_ENABLED, false) &&
            !UltronAudioService.isRunning &&
            !isForegroundCaptureActive &&
            !isForegroundRecognizerActive &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            startSentinelService()
        }
        // Entrega com pequeno atraso para o Dart já ter registrado o handler (cold start).
        window?.decorView?.postDelayed({ deliverPendingWakeWord() }, 600L)
        try {
            accelerometer?.let {
                sensorManager?.registerListener(this, it, SensorManager.SENSOR_DELAY_UI)
            }
        } catch (_: Exception) {
        }
    }

    override fun onPause() {
        isActivityResumed = false
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

    override fun onStop() {
        audioCaptureHandler?.stopCapture()
        // Ao sair de cena, volta ao comportamento normal da tela de bloqueio.
        applyLockScreenMode(false)
        super.onStop()
    }

    override fun onDestroy() {
        isActivityResumed = false
        if (instance == this) instance = null
        actionsChannel?.setMethodCallHandler(null)
        actionsChannel = null
        audioCaptureHandler?.release()
        audioCaptureHandler = null
        try {
            sensorManager?.unregisterListener(this)
            DeviceHardwareHelper.releaseTorch()
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    private fun handleDeviceCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setTorch" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                result.success(DeviceHardwareHelper.setTorch(this, enabled))
            }
            "toggleTorch" -> {
                result.success(DeviceHardwareHelper.toggleTorch(this))
            }
            "getDeviceStatus" -> {
                result.success(DeviceHardwareHelper.readDeviceStatus(this))
            }
            "setVolume" -> {
                val percent = (call.argument<Int>("percent") ?: 50).coerceIn(0, 100)
                result.success(DeviceHardwareHelper.setMediaVolumePercent(this, percent, showUi = true))
            }
            "adjustVolume" -> {
                val direction = call.argument<String>("direction") ?: "up"
                result.success(DeviceHardwareHelper.adjustMediaVolume(this, direction, showUi = true))
            }
            "mediaControl" -> {
                val action = call.argument<String>("action") ?: "play_pause"
                result.success(DeviceHardwareHelper.dispatchMediaControl(this, action))
            }
            "vibrate" -> {
                val durationMs = (call.argument<Int>("durationMs") ?: 180).coerceIn(20, 3000)
                DeviceHardwareHelper.triggerVibration(this, durationMs.toLong())
                result.success(true)
            }
            "openSystemSettings" -> {
                val target = call.argument<String>("target") ?: "general"
                result.success(DeviceHardwareHelper.openSettingsPanel(this, target))
            }
            "openApp" -> {
                val target = call.argument<String>("target") ?: ""
                result.success(DeviceHardwareHelper.launchInstalledApp(this, target))
            }
            "setAlarm" -> {
                val hour = (call.argument<Int>("hour") ?: 7).coerceIn(0, 23)
                val minute = (call.argument<Int>("minute") ?: 0).coerceIn(0, 59)
                val message = call.argument<String>("message") ?: "U.L.T.R.O.N."
                DeviceHardwareHelper.setAlarm(this, hour, minute, message)
                result.success(true)
            }
            "setTimer" -> {
                val seconds = (call.argument<Int>("seconds") ?: 60).coerceAtLeast(1)
                val message = call.argument<String>("message") ?: "U.L.T.R.O.N. Timer"
                DeviceHardwareHelper.setTimer(this, seconds, message)
                result.success(true)
            }
            "openUrl" -> {
                val rawUrl = call.argument<String>("url") ?: ""
                DeviceHardwareHelper.openUrl(this, rawUrl)
                result.success(true)
            }
            "dialNumber" -> {
                val number = call.argument<String>("number") ?: ""
                DeviceHardwareHelper.dialNumber(this, number)
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
                result.error(
                    "google_stt_blocked",
                    "Reconhecimento Google desativado por regra do app. Use o microfone nativo AudioRecord.",
                    null
                )
            }
            "stopListeningVoice" -> {
                audioCaptureHandler?.stopCapture()
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
                // Só afirma "ativo" com captura real confirmada (não apenas serviço vivo).
                result.success(UltronAudioService.isListeningForReal())
            }
            "consumePendingWakeWord" -> {
                result.success(consumePendingWakeWord())
            }
            "getWakeWordDiagnostics" -> {
                result.success(UltronAudioService.diagnostics(this))
            }
            "setBootAutostart" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                getSharedPreferences(UltronAudioService.PREFS_NAME, Context.MODE_PRIVATE)
                    .edit().putBoolean(UltronAudioService.PREF_BOOT_AUTOSTART, enabled).apply()
                result.success(enabled)
            }
            "requestIgnoreBatteryOptimizations" -> {
                val pm = getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
                if (pm?.isIgnoringBatteryOptimizations(packageName) == true) {
                    result.success(true)
                } else {
                    try {
                        startActivity(
                            Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName")
                            )
                        )
                    } catch (_: Exception) {
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    }
                    result.success(false)
                }
            }
            "setAudioSentinel" -> {
                val enable = call.argument<Boolean>("enabled") ?: false
                if (!enable) {
                    getSharedPreferences(UltronAudioService.PREFS_NAME, Context.MODE_PRIVATE)
                        .edit().putBoolean(UltronAudioService.PREF_ENABLED, false).apply()
                    stopService(Intent(this, UltronAudioService::class.java))
                    result.success(false)
                } else {
                    val hasMic = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                    val needsNotifPerm = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.POST_NOTIFICATIONS
                        ) != PackageManager.PERMISSION_GRANTED
                    val missing = buildList {
                        if (!hasMic) add(Manifest.permission.RECORD_AUDIO)
                        if (needsNotifPerm) add(Manifest.permission.POST_NOTIFICATIONS)
                    }
                    if (missing.isNotEmpty()) {
                        ActivityCompat.requestPermissions(this, missing.toTypedArray(), 9044)
                    }
                    if (!hasMic) {
                        // O serviço sobe em onRequestPermissionsResult, se o usuário conceder.
                        result.success(false)
                    } else {
                        // Pedido de início (contexto permitido: Activity em primeiro plano).
                        // "true" = pedido aceito; o estado REAL vem de isAudioSentinelRunning.
                        startSentinelService()
                        result.success(true)
                    }
                }
            }
            "speakOfflineFishVoice" -> {
                val text = call.argument<String>("text") ?: ""
                val spoken = UltronTtsHelper.answerQuickOfflineQuery(this, text)
                result.success(spoken)
            }
            "configureTts" -> {
                val voiceName = call.argument<String>("voiceName")
                val pitch = (call.argument<Double>("pitch") ?: 0.55).toFloat()
                val rate = (call.argument<Double>("rate") ?: 0.45).toFloat()
                UltronTtsHelper.configure(voiceName, pitch, rate)
                result.success(true)
            }
            "playTtsAudioBytes" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                if (bytes == null || bytes.isEmpty()) {
                    result.success(false)
                } else {
                    UltronTtsHelper.playAudioBytes(this, bytes, volume, result)
                }
            }
            "syncBackgroundVoiceConfig" -> {
                val cfg = BackgroundVoiceConfig(
                    sttUrl = call.argument<String>("sttUrl") ?: "",
                    sttKey = call.argument<String>("sttKey") ?: "",
                    sttModel = call.argument<String>("sttModel") ?: "whisper-large-v3-turbo",
                    sttLanguage = call.argument<String>("sttLanguage") ?: "pt",
                    aiBaseUrl = call.argument<String>("aiBaseUrl") ?: "https://text.pollinations.ai/openai",
                    aiKey = call.argument<String>("aiKey") ?: "",
                    aiModel = call.argument<String>("aiModel") ?: "openai",
                    fishEnabled = call.argument<Boolean>("fishEnabled") ?: false,
                    fishKey = call.argument<String>("fishKey") ?: "",
                    fishRefId = call.argument<String>("fishRefId") ?: "",
                    fishLanguage = call.argument<String>("fishLanguage") ?: "pt",
                    fishModel = call.argument<String>("fishModel") ?: "s2.1-pro",
                    whisperMode = call.argument<Boolean>("whisperMode") ?: false,
                )
                BackgroundVoiceConfigStore.save(this, cfg)
                val historyRaw = call.argument<List<Map<String, Any?>>>("recentHistory")
                if (historyRaw != null) {
                    BackgroundChatStore.seedForegroundContext(this, historyRaw)
                }
                result.success(true)
            }
            "consumePendingBackgroundTurns" -> {
                result.success(BackgroundChatStore.consumePendingTurns(this))
            }
            "canDrawOverlays" -> {
                result.success(DeviceHardwareHelper.canLaunchActivitiesFromBackground(this))
            }
            "requestOverlayPermission" -> {
                if (DeviceHardwareHelper.canLaunchActivitiesFromBackground(this)) {
                    result.success(true)
                } else {
                    try {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                    } catch (_: Exception) {
                        startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))
                    }
                    result.success(false)
                }
            }
            "captureVisionImage" -> {
                val source = (call.argument<String>("source") ?: "camera").lowercase()
                if (pendingVisionResult != null) {
                    result.error("VISION_BUSY", "Já existe uma captura de imagem em andamento.", null)
                    return
                }
                startVisionCapture(source, result)
            }
            "getCalendarEvents" -> {
                val nowMs = System.currentTimeMillis()
                val startMs = (call.argument<Number>("startMs")?.toLong()) ?: nowMs
                val endMs = (call.argument<Number>("endMs")?.toLong()) ?: (startMs + 86_400_000L)
                val limit = ((call.argument<Number>("limit")?.toInt()) ?: 20).coerceIn(1, 50)
                ensureCalendarPermissions(writeRequired = false, result = result) {
                    queryCalendarEvents(startMs, endMs, limit, result)
                }
            }
            "createCalendarEvent" -> {
                val title = (call.argument<String>("title") ?: "").trim()
                if (title.isEmpty()) {
                    result.error("INVALID_ARGUMENT", "Título do evento não pode ser vazio.", null)
                    return
                }
                val startMs = call.argument<Number>("startMs")?.toLong() ?: System.currentTimeMillis()
                val endMs = call.argument<Number>("endMs")?.toLong() ?: (startMs + 3_600_000L)
                val description = call.argument<String>("description") ?: ""
                val location = call.argument<String>("location") ?: ""
                val allDay = call.argument<Boolean>("allDay") ?: false
                ensureCalendarPermissions(writeRequired = true, result = result) {
                    insertOrOpenCalendarEvent(
                        title = title,
                        startMs = startMs,
                        endMs = endMs,
                        description = description,
                        location = location,
                        allDay = allDay,
                        result = result,
                    )
                }
            }
            else -> result.notImplemented()
        }
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

    @Suppress("DEPRECATION")
    private fun startVisionCapture(source: String, result: MethodChannel.Result) {
        if (source == "gallery") {
            pendingVisionResult = result
            val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                type = "image/*"
                addCategory(Intent.CATEGORY_OPENABLE)
            }
            try {
                startActivityForResult(
                    Intent.createChooser(intent, "Selecionar imagem para Visão"),
                    VISION_GALLERY_REQUEST_CODE,
                )
            } catch (e: Exception) {
                pendingVisionResult = null
                result.error("GALLERY_UNAVAILABLE", e.message ?: "Galeria indisponível.", null)
            }
            return
        }

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            pendingVisionResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.CAMERA),
                VISION_CAMERA_PERM_REQUEST_CODE,
            )
            return
        }

        try {
            val visionDir = File(cacheDir, "vision").apply { mkdirs() }
            val imageFile = File(visionDir, "capture_${System.currentTimeMillis()}.jpg")
            val photoUri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                imageFile,
            )
            pendingVisionCameraUri = photoUri
            pendingVisionResult = result
            val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, photoUri)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivityForResult(intent, VISION_CAMERA_REQUEST_CODE)
        } catch (e: Exception) {
            pendingVisionResult = null
            pendingVisionCameraUri = null
            result.error("CAMERA_UNAVAILABLE", e.message ?: "Câmera indisponível.", null)
        }
    }

    private fun decodeAndCompressVisionImage(uri: Uri, source: String): Map<String, Any>? {
        val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        contentResolver.openInputStream(uri)?.use { input ->
            BitmapFactory.decodeStream(input, null, boundsOpts)
        } ?: return null

        val rawW = boundsOpts.outWidth
        val rawH = boundsOpts.outHeight
        if (rawW <= 0 || rawH <= 0) return null

        var sampleSize = 1
        while (max(rawW / sampleSize, rawH / sampleSize) > VISION_MAX_DIM_PX * 2) {
            sampleSize *= 2
        }
        val decodeOpts = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        val decoded = contentResolver.openInputStream(uri)?.use { input ->
            BitmapFactory.decodeStream(input, null, decodeOpts)
        } ?: return null

        val rotated = applyExifOrientationIfNeeded(uri, decoded)
        val longest = max(rotated.width, rotated.height)
        val scaled = if (longest > VISION_MAX_DIM_PX) {
            val scale = VISION_MAX_DIM_PX.toFloat() / longest.toFloat()
            val targetW = max(1, (rotated.width * scale).roundToInt())
            val targetH = max(1, (rotated.height * scale).roundToInt())
            Bitmap.createScaledBitmap(rotated, targetW, targetH, true).also {
                if (it != rotated) rotated.recycle()
            }
        } else {
            rotated
        }

        val out = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, VISION_JPEG_QUALITY, out)
        val finalW = scaled.width
        val finalH = scaled.height
        scaled.recycle()
        val bytes = out.toByteArray()
        val encoded = Base64.encodeToString(bytes, Base64.NO_WRAP)
        return mapOf(
            "base64" to encoded,
            "mimeType" to "image/jpeg",
            "width" to finalW,
            "height" to finalH,
            "byteSize" to bytes.size,
            "source" to source,
        )
    }

    private fun applyExifOrientationIfNeeded(uri: Uri, bitmap: Bitmap): Bitmap {
        val orientation = try {
            contentResolver.openInputStream(uri)?.use { input ->
                ExifInterface(input).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL,
                )
            } ?: ExifInterface.ORIENTATION_NORMAL
        } catch (_: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }
        val degrees = when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> 0f
        }
        if (degrees == 0f) return bitmap
        val matrix = Matrix().apply { postRotate(degrees) }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true).also {
            if (it != bitmap) bitmap.recycle()
        }
    }

    private fun ensureCalendarPermissions(
        writeRequired: Boolean,
        result: MethodChannel.Result,
        onGranted: () -> Unit,
    ) {
        val readOk = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_CALENDAR,
        ) == PackageManager.PERMISSION_GRANTED
        val writeOk = !writeRequired || ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.WRITE_CALENDAR,
        ) == PackageManager.PERMISSION_GRANTED

        if (readOk && writeOk) {
            onGranted()
            return
        }
        if (pendingCalendarResult != null) {
            result.error("CALENDAR_BUSY", "Já existe uma solicitação de agenda em andamento.", null)
            return
        }
        pendingCalendarResult = result
        pendingCalendarOperation = {
            val writeNowOk = !writeRequired || ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.WRITE_CALENDAR,
            ) == PackageManager.PERMISSION_GRANTED
            if (writeNowOk) {
                onGranted()
            } else {
                result.error("CALENDAR_PERMISSION_DENIED", "Permissão de escrita na Agenda negada.", null)
            }
        }
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR),
            CALENDAR_PERM_REQUEST_CODE,
        )
    }

    private fun queryCalendarEvents(
        startMs: Long,
        endMs: Long,
        limit: Int,
        result: MethodChannel.Result,
    ) {
        try {
            val projection = arrayOf(
                CalendarContract.Instances.EVENT_ID,
                CalendarContract.Instances.TITLE,
                CalendarContract.Instances.BEGIN,
                CalendarContract.Instances.END,
                CalendarContract.Instances.ALL_DAY,
                CalendarContract.Instances.EVENT_LOCATION,
                CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
                CalendarContract.Instances.DESCRIPTION,
            )
            val items = mutableListOf<Map<String, Any?>>()
            CalendarContract.Instances.query(
                contentResolver,
                projection,
                startMs,
                endMs,
            )?.use { cursor ->
                val idIdx = cursor.getColumnIndex(CalendarContract.Instances.EVENT_ID)
                val titleIdx = cursor.getColumnIndex(CalendarContract.Instances.TITLE)
                val beginIdx = cursor.getColumnIndex(CalendarContract.Instances.BEGIN)
                val endIdx = cursor.getColumnIndex(CalendarContract.Instances.END)
                val allDayIdx = cursor.getColumnIndex(CalendarContract.Instances.ALL_DAY)
                val locIdx = cursor.getColumnIndex(CalendarContract.Instances.EVENT_LOCATION)
                val calIdx = cursor.getColumnIndex(CalendarContract.Instances.CALENDAR_DISPLAY_NAME)
                val descIdx = cursor.getColumnIndex(CalendarContract.Instances.DESCRIPTION)

                while (cursor.moveToNext()) {
                    val title = if (titleIdx >= 0) cursor.getString(titleIdx) ?: "" else ""
                    if (title.isBlank()) continue
                    val begin = if (beginIdx >= 0) cursor.getLong(beginIdx) else startMs
                    val end = if (endIdx >= 0) cursor.getLong(endIdx) else begin
                    items.add(
                        mapOf(
                            "id" to (if (idIdx >= 0) cursor.getLong(idIdx).toString() else ""),
                            "title" to title.trim(),
                            "startMs" to begin,
                            "endMs" to end,
                            "allDay" to (if (allDayIdx >= 0) cursor.getInt(allDayIdx) == 1 else false),
                            "location" to (if (locIdx >= 0) cursor.getString(locIdx) ?: "" else ""),
                            "calendarName" to (if (calIdx >= 0) cursor.getString(calIdx) ?: "" else ""),
                            "description" to (if (descIdx >= 0) cursor.getString(descIdx) ?: "" else ""),
                        ),
                    )
                }
            }
            val sorted = items.sortedBy { (it["startMs"] as? Long) ?: 0L }.take(limit)
            result.success(sorted)
        } catch (e: Exception) {
            result.error("CALENDAR_READ_ERROR", e.message ?: "Falha ao ler eventos da Agenda.", null)
        }
    }

    private fun findPrimaryWritableCalendar(): Pair<Long, String>? {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
            CalendarContract.Calendars.VISIBLE,
            CalendarContract.Calendars.IS_PRIMARY,
        )
        var fallback: Pair<Long, String>? = null
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            null,
            null,
            null,
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndex(CalendarContract.Calendars._ID)
            val nameIdx = cursor.getColumnIndex(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME)
            val accessIdx = cursor.getColumnIndex(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL)
            val visibleIdx = cursor.getColumnIndex(CalendarContract.Calendars.VISIBLE)
            val primaryIdx = cursor.getColumnIndex(CalendarContract.Calendars.IS_PRIMARY)

            while (cursor.moveToNext()) {
                val id = if (idIdx >= 0) cursor.getLong(idIdx) else continue
                val access = if (accessIdx >= 0) cursor.getInt(accessIdx) else 0
                if (access < CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR) continue
                val visible = if (visibleIdx >= 0) cursor.getInt(visibleIdx) == 1 else true
                val primary = if (primaryIdx >= 0) cursor.getInt(primaryIdx) == 1 else false
                val name = (if (nameIdx >= 0) cursor.getString(nameIdx) else null) ?: "Agenda"
                val pair = Pair(id, name)
                if (visible && primary) return pair
                if (fallback == null && visible) {
                    fallback = pair
                } else if (fallback == null) {
                    fallback = pair
                }
            }
        }
        return fallback
    }

    private fun insertOrOpenCalendarEvent(
        title: String,
        startMs: Long,
        endMs: Long,
        description: String,
        location: String,
        allDay: Boolean,
        result: MethodChannel.Result,
    ) {
        try {
            val writable = findPrimaryWritableCalendar()
            if (writable != null) {
                val values = ContentValues().apply {
                    put(CalendarContract.Events.DTSTART, startMs)
                    put(CalendarContract.Events.DTEND, if (endMs > startMs) endMs else startMs + 3_600_000L)
                    put(CalendarContract.Events.TITLE, title)
                    if (description.isNotBlank()) {
                        put(CalendarContract.Events.DESCRIPTION, description)
                    }
                    if (location.isNotBlank()) {
                        put(CalendarContract.Events.EVENT_LOCATION, location)
                    }
                    put(CalendarContract.Events.CALENDAR_ID, writable.first)
                    put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
                    put(CalendarContract.Events.ALL_DAY, if (allDay) 1 else 0)
                }
                val uri = contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
                if (uri != null) {
                    val eventId = ContentUris.parseId(uri)
                    result.success(
                        mapOf(
                            "created" to true,
                            "mode" to "direct",
                            "eventId" to eventId.toString(),
                            "calendarName" to writable.second,
                            "title" to title,
                        ),
                    )
                    return
                }
            }

            val intent = Intent(Intent.ACTION_INSERT).apply {
                data = CalendarContract.Events.CONTENT_URI
                putExtra(CalendarContract.Events.TITLE, title)
                putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startMs)
                putExtra(CalendarContract.EXTRA_EVENT_END_TIME, if (endMs > startMs) endMs else startMs + 3_600_000L)
                putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, allDay)
                if (description.isNotBlank()) {
                    putExtra(CalendarContract.Events.DESCRIPTION, description)
                }
                if (location.isNotBlank()) {
                    putExtra(CalendarContract.Events.EVENT_LOCATION, location)
                }
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(
                mapOf(
                    "created" to true,
                    "mode" to "intent",
                    "eventId" to "",
                    "calendarName" to "App de Agenda",
                    "title" to title,
                ),
            )
        } catch (e: Exception) {
            result.error("CALENDAR_WRITE_ERROR", e.message ?: "Falha ao criar evento na Agenda.", null)
        }
    }
}
