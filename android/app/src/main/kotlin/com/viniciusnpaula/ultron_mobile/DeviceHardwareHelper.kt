package com.viniciusnpaula.ultron_mobile

import android.app.Activity
import android.app.ActivityManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
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
import java.text.Normalizer
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

    data class MediaDispatchResult(
        val status: String, // "confirmed" | "opened_needs_play" | "no_active_session" | "uncertain" | "failed"
        val confirmed: Boolean,
        val activePackage: String = "",
        val launchedApp: String = "",
        val detail: String = "",
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "status" to status,
            "confirmed" to confirmed,
            "activePackage" to activePackage,
            "launchedApp" to launchedApp,
            "detail" to detail,
        )
    }

    fun dispatchMediaControlVerified(
        context: Context,
        action: String,
        preferredApp: String = "",
        autoLaunchIfClosed: Boolean = true,
    ): MediaDispatchResult {
        val normAction = action.trim().lowercase()
        val firstPass = dispatchMediaControlSinglePass(context, normAction, preferredApp)
        if (firstPass.confirmed || !autoLaunchIfClosed) {
            return firstPass
        }

        // Proatividade: se o pedido era para reproduzir/controlar faixa e o app está fechado,
        // abre o player automaticamente, aguarda inicialização e tenta retomar a reprodução!
        val isPlaybackStartAction = normAction in setOf("play", "play_pause", "toggle", "next", "previous", "prev")
        if (firstPass.status == "no_active_session" && isPlaybackStartAction) {
            val targetApp = preferredApp.trim().lowercase().ifEmpty { "spotify" }
            val launched = runCatching {
                launchInstalledAppWithStatus(context, targetApp)
            }.getOrNull()

            if (launched != null) {
                if (!launched.openedImmediately) {
                    return MediaDispatchResult(
                        status = "opened_needs_play",
                        confirmed = false,
                        launchedApp = launched.label,
                        detail = "${launched.label} estava fechado; atalho enviado na notificação para abrir.",
                    )
                }
                // Aguarda o player inicializar e registrar sessão de mídia, depois tenta retomar
                runCatching { Thread.sleep(1500) }
                val retry = dispatchMediaControlSinglePass(context, normAction, targetApp)
                if (retry.confirmed) {
                    return MediaDispatchResult(
                        status = "confirmed",
                        confirmed = true,
                        activePackage = retry.activePackage,
                        launchedApp = launched.label,
                        detail = "Abri ${launched.label} e retomei a reprodução.",
                    )
                }
                return MediaDispatchResult(
                    status = "opened_needs_play",
                    confirmed = false,
                    activePackage = retry.activePackage,
                    launchedApp = launched.label,
                    detail = "${launched.label} estava fechado; abri o aplicativo, mas o play automático não iniciou.",
                )
            }
        }
        return firstPass
    }

    private fun dispatchMediaControlSinglePass(
        context: Context,
        normAction: String,
        preferredApp: String,
    ): MediaDispatchResult {
        val keyCode = when (normAction) {
            "play" -> KeyEvent.KEYCODE_MEDIA_PLAY
            "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
            "play_pause", "toggle" -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
            "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
            "previous", "prev" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            "stop" -> KeyEvent.KEYCODE_MEDIA_STOP
            else -> return MediaDispatchResult("failed", false, detail = "Ação de mídia inválida.")
        }
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            ?: return MediaDispatchResult("failed", false, detail = "AudioManager indisponível.")
        val normApp = preferredApp.trim().lowercase()

        // 1. Se tivermos acesso a MediaSessionManager (via NotificationListenerService),
        // verificamos a sessão real do player antes e depois do comando.
        val sessions: List<MediaController>? = runCatching {
            val msm = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as? MediaSessionManager
            msm?.getActiveSessions(ComponentName(context, UltronNotificationListenerService::class.java))
        }.getOrNull()

        if (sessions != null) {
            val matchedController: MediaController? = if (normApp.isNotEmpty()) {
                val pkgHints = mediaAppPackageHints(normApp)
                sessions.firstOrNull { ctrl ->
                    val p = ctrl.packageName.lowercase()
                    p.contains(normApp) || pkgHints.any { p.contains(it) }
                }
            } else {
                sessions.firstOrNull {
                    val st = it.playbackState?.state
                    st == PlaybackState.STATE_PLAYING || st == PlaybackState.STATE_BUFFERING
                } ?: sessions.firstOrNull()
            }

            if (matchedController == null) {
                // Se o usuário pediu um app específico (ex: Spotify) e ele não tem sessão ativa,
                // ou se não há nenhuma sessão de mídia ativa no aparelho:
                if (normApp.isNotEmpty() || !audio.isMusicActive) {
                    val label = if (normApp.isNotEmpty()) normApp else "player de mídia"
                    return MediaDispatchResult(
                        status = "no_active_session",
                        confirmed = false,
                        detail = "Nenhuma sessão ativa encontrada para $label (app fechado).",
                    )
                }
            } else {
                val pkg = matchedController.packageName
                val beforeState = matchedController.playbackState?.state
                val beforePlaying = beforeState == PlaybackState.STATE_PLAYING ||
                    beforeState == PlaybackState.STATE_BUFFERING ||
                    audio.isMusicActive
                val beforeTitle = matchedController.metadata?.description?.title?.toString().orEmpty()

                when (normAction) {
                    "play" -> matchedController.transportControls.play()
                    "pause" -> matchedController.transportControls.pause()
                    "play_pause", "toggle" -> {
                        if (beforePlaying) matchedController.transportControls.pause()
                        else matchedController.transportControls.play()
                    }
                    "next" -> matchedController.transportControls.skipToNext()
                    "previous", "prev" -> matchedController.transportControls.skipToPrevious()
                    "stop" -> matchedController.transportControls.stop()
                }

                // Aguarda brevemente o estado real do player refletir o comando
                for (attempt in 0 until 6) {
                    runCatching { Thread.sleep(90) }
                    val afterState = matchedController.playbackState?.state
                    val afterPlaying = afterState == PlaybackState.STATE_PLAYING ||
                        afterState == PlaybackState.STATE_BUFFERING ||
                        audio.isMusicActive
                    val afterTitle = matchedController.metadata?.description?.title?.toString().orEmpty()

                    val ok = when (normAction) {
                        "play" -> afterPlaying
                        "pause", "stop" -> !afterPlaying || afterState == PlaybackState.STATE_PAUSED || afterState == PlaybackState.STATE_STOPPED
                        "play_pause", "toggle" -> afterPlaying != beforePlaying
                        "next", "previous", "prev" -> (afterTitle.isNotEmpty() && afterTitle != beforeTitle) || afterPlaying
                        else -> false
                    }
                    if (ok) {
                        return MediaDispatchResult(
                            status = "confirmed",
                            confirmed = true,
                            activePackage = pkg,
                            detail = "Confirmado na sessão $pkg.",
                        )
                    }
                }
                val finalPlaying = audio.isMusicActive ||
                    matchedController.playbackState?.state == PlaybackState.STATE_PLAYING
                return if (normAction == "play" && !finalPlaying) {
                    MediaDispatchResult(
                        status = "no_active_session",
                        confirmed = false,
                        activePackage = pkg,
                        detail = "Sessão $pkg não iniciou reprodução após o comando.",
                    )
                } else {
                    MediaDispatchResult(
                        status = "uncertain",
                        confirmed = false,
                        activePackage = pkg,
                        detail = "Comando enviado para $pkg, mas o estado final não mudou dentro do tempo limite.",
                    )
                }
            }
        }

        // 2. Fallback sem NotificationListener: usa AudioManager.isMusicActive antes e após KeyEvent
        val wasPlaying = audio.isMusicActive
        if ((normAction == "pause" || normAction == "stop") && !wasPlaying) {
            return MediaDispatchResult(
                status = "no_active_session",
                confirmed = false,
                detail = "Nenhuma reprodução ativa detectada no aparelho.",
            )
        }

        val eventTime = SystemClock.uptimeMillis()
        audio.dispatchMediaKeyEvent(KeyEvent(eventTime, eventTime, KeyEvent.ACTION_DOWN, keyCode, 0))
        audio.dispatchMediaKeyEvent(KeyEvent(eventTime, eventTime, KeyEvent.ACTION_UP, keyCode, 0))

        for (attempt in 0 until 6) {
            runCatching { Thread.sleep(90) }
            val nowPlaying = audio.isMusicActive
            when (normAction) {
                "play" -> if (nowPlaying) {
                    return MediaDispatchResult("confirmed", true, detail = "Áudio de mídia ativo confirmado.")
                }
                "pause", "stop" -> if (!nowPlaying) {
                    return MediaDispatchResult("confirmed", true, detail = "Áudio de mídia interrompido.")
                }
                "play_pause", "toggle" -> if (nowPlaying != wasPlaying) {
                    return MediaDispatchResult("confirmed", true, detail = "Estado de reprodução alternado.")
                }
            }
        }

        val finalPlaying = audio.isMusicActive
        return when (normAction) {
            "play" -> MediaDispatchResult(
                status = "no_active_session",
                confirmed = false,
                detail = "Nenhum áudio iniciou após o comando (player possivelmente fechado).",
            )
            "play_pause", "toggle" -> if (!finalPlaying && !wasPlaying) {
                MediaDispatchResult(
                    status = "no_active_session",
                    confirmed = false,
                    detail = "Nenhum player respondeu ao Play/Pause.",
                )
            } else {
                MediaDispatchResult("uncertain", false, detail = "Sinal enviado, mas não foi possível confirmar a troca.")
            }
            "next", "previous", "prev" -> if (!wasPlaying && !finalPlaying) {
                MediaDispatchResult(
                    status = "no_active_session",
                    confirmed = false,
                    detail = "Nenhum player ativo para trocar de faixa.",
                )
            } else {
                MediaDispatchResult("uncertain", false, detail = "Sinal enviado ao player ativo (faixa não verificável sem acesso a notificações).")
            }
            else -> MediaDispatchResult("uncertain", false, detail = "Comando enviado sem confirmação final do player.")
        }
    }

    fun dispatchMediaControl(context: Context, action: String): Boolean =
        dispatchMediaControlVerified(context, action).confirmed

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

    private const val BAL_NOTIFICATION_ID = 2051
    private const val WAKE_CHANNEL_ID = "ultron_wake_alert_channel"

    data class AppLaunchResult(
        val label: String,
        val openedImmediately: Boolean,
    )

    fun canLaunchActivitiesFromBackground(context: Context): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || Settings.canDrawOverlays(context)
    }

    private fun startActivitySafely(
        context: Context,
        intent: Intent,
        fallbackLabel: String,
    ): Boolean {
        val canDirectLaunch = MainActivity.isActivityResumed ||
            canLaunchActivitiesFromBackground(context)
        if (canDirectLaunch) {
            return try {
                context.startActivity(intent)
                true
            } catch (_: Throwable) {
                false
            }
        }
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            val pending = PendingIntent.getActivity(
                context,
                41,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            nm?.notify(
                BAL_NOTIFICATION_ID,
                NotificationCompat.Builder(context, WAKE_CHANNEL_ID)
                    .setContentTitle("U.L.T.R.O.N.: toque para abrir $fallbackLabel")
                    .setContentText("Ative 'Aparecer sobre outros apps' para abrir direto em 2º plano.")
                    .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setAutoCancel(true)
                    .setTimeoutAfter(25_000L)
                    .setContentIntent(pending)
                    .build(),
            )
        } catch (_: Throwable) {
        }
        return false
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
        return startActivitySafely(context, intent, "Configurações")
    }

    private val trailingCourtesyRegex = Regex(
        """(?:\s+(?:para\s+mim|pra\s+mim|por\s+favor|por\s+gentileza|pfv|aqui|a[ií]|agora|r[aá]pido|logo|se\s+puder|se\s+conseguir|por\s+obs[eé]quio|ok|t[aá]|viu|ultron))+$""",
        RegexOption.IGNORE_CASE,
    )

    private val leadingArticleRegex = Regex(
        """^(?:o|a|os|as|um|uma|app|aplicativo)\s+""",
        RegexOption.IGNORE_CASE,
    )

    private fun mediaAppPackageHints(normApp: String): List<String> = when (normApp) {
        "youtube music", "yt music", "ytmusic" -> listOf("youtube.music")
        "apple music" -> listOf("apple.android.music")
        "amazon music" -> listOf("amazon.mp3")
        "tidal" -> listOf("aspiro.tidal", "tidal")
        "poweramp" -> listOf("maxmpz.audioplayer", "poweramp")
        "vlc" -> listOf("videolan.vlc", "vlc")
        "djay", "algoriddim" -> listOf("algoriddim.djay", "djay")
        "edjing", "edjing mix" -> listOf("edjing")
        "cross dj", "crossdj" -> listOf("mixvibes.crossdj", "crossdj")
        "rekordbox", "pioneer" -> listOf("rekordbox", "pioneer")
        "traktor" -> listOf("traktor", "nativeinstruments")
        "bandlab" -> listOf("bandlab")
        else -> listOf(normApp)
    }

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

    private val combiningMarksRegex = Regex("""\p{InCombiningDiacriticalMarks}+""")

    private fun foldAccents(text: String): String {
        val norm = Normalizer.normalize(text, Normalizer.Form.NFD)
        return combiningMarksRegex.replace(norm, "").lowercase(Locale.ROOT).trim()
    }

    fun launchInstalledApp(context: Context, rawQuery: String): String {
        val res = launchInstalledAppWithStatus(context, rawQuery)
        return if (res.openedImmediately) {
            res.label
        } else {
            "${res.label} (atalho na notificação — ative 'Aparecer sobre outros apps' para abrir em 2º plano)"
        }
    }

    fun launchInstalledAppWithStatus(context: Context, rawQuery: String): AppLaunchResult {
        val rawClean = sanitizeAppQuery(rawQuery)
        val query = foldAccents(rawClean)
        if (query.isEmpty()) throw IllegalArgumentException("Informe o nome do aplicativo.")

        when (query) {
            "camera", "câmera", "foto" -> {
                val intent = Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                return AppLaunchResult("Câmera", startActivitySafely(context, intent, "Câmera"))
            }
            "configuracoes", "configurações", "ajustes", "settings" -> {
                val ok = openSettingsPanel(context, "general")
                return AppLaunchResult("Configurações", ok)
            }
            "wifi", "wi-fi" -> {
                val ok = openSettingsPanel(context, "wifi")
                return AppLaunchResult("Painel Wi-Fi", ok)
            }
            "bluetooth" -> {
                val ok = openSettingsPanel(context, "bluetooth")
                return AppLaunchResult("Bluetooth", ok)
            }
            "telefone", "discador", "chamada" -> {
                val intent = Intent(Intent.ACTION_DIAL).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                return AppLaunchResult("Telefone", startActivitySafely(context, intent, "Telefone"))
            }
            "relogio", "relógio", "alarme", "despertador" -> {
                val intent = Intent(AlarmClock.ACTION_SHOW_ALARMS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                return AppLaunchResult("Relógio / Alarmes", startActivitySafely(context, intent, "Relógio / Alarmes"))
            }
            "navegador", "browser", "internet" -> {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com")).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                return AppLaunchResult("Navegador", startActivitySafely(context, intent, "Navegador"))
            }
        }

        val knownPackages = mapOf(
            "whatsapp" to listOf("com.whatsapp", "com.whatsapp.w4b"),
            "youtube" to listOf("com.google.android.youtube"),
            "instagram" to listOf("com.instagram.android"),
            "chrome" to listOf("com.android.chrome"),
            "spotify" to listOf("com.spotify.music"),
            "youtube music" to listOf("com.google.android.apps.youtube.music"),
            "yt music" to listOf("com.google.android.apps.youtube.music"),
            "deezer" to listOf("deezer.android.app"),
            "apple music" to listOf("com.apple.android.music"),
            "soundcloud" to listOf("com.soundcloud.android"),
            "tidal" to listOf("com.aspiro.tidal"),
            "amazon music" to listOf("com.amazon.mp3"),
            "poweramp" to listOf("com.maxmpz.audioplayer"),
            "vlc" to listOf("org.videolan.vlc"),
            "bandlab" to listOf("com.bandlab.bandlab"),
            "djay" to listOf("com.algoriddim.djay_free", "com.algoriddim.djay"),
            "edjing" to listOf("com.edjing.edjingdjturntable"),
            "edjing mix" to listOf("com.edjing.edjingdjturntable"),
            "cross dj" to listOf("com.mixvibes.crossdjfree", "com.mixvibes.crossdjapp"),
            "rekordbox" to listOf("jp.pioneer.mbg.rekordbox"),
            "traktor" to listOf("com.nativeinstruments.traktor"),
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
            "obsidian" to listOf("md.obsidian"),
            "opengym" to listOf("ch.duartesantos.opengym"),
            "open gym" to listOf("ch.duartesantos.opengym"),
        )

        val pm = context.packageManager
        knownPackages[query]?.forEach { pkg ->
            val launch = pm.getLaunchIntentForPackage(pkg)
            if (launch != null) {
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                val label = query.replaceFirstChar { it.uppercase() }
                return AppLaunchResult(label, startActivitySafely(context, launch, label))
            }
        }

        val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val resolveInfos = pm.queryIntentActivities(mainIntent, PackageManager.MATCH_ALL)
        for (info in resolveInfos) {
            val label = info.loadLabel(pm).toString()
            val pkg = info.activityInfo.packageName
            if (foldAccents(label).contains(query) || foldAccents(pkg).contains(query)) {
                val launch = pm.getLaunchIntentForPackage(pkg) ?: Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_LAUNCHER)
                    component = ComponentName(pkg, info.activityInfo.name)
                    addFlags(Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
                }
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                return AppLaunchResult(label, startActivitySafely(context, launch, label))
            }
        }

        throw IllegalStateException("Aplicativo '$rawQuery' não encontrado no dispositivo.")
    }

    fun setAlarm(context: Context, hour: Int, minute: Int, message: String, skipUi: Boolean = false): Boolean {
        val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
            putExtra(AlarmClock.EXTRA_HOUR, hour.coerceIn(0, 23))
            putExtra(AlarmClock.EXTRA_MINUTES, minute.coerceIn(0, 59))
            putExtra(AlarmClock.EXTRA_MESSAGE, message.ifBlank { "U.L.T.R.O.N." })
            putExtra(AlarmClock.EXTRA_SKIP_UI, skipUi)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return startActivitySafely(context, intent, "Alarme ${hour.toString().padStart(2, '0')}:${minute.toString().padStart(2, '0')}")
    }

    fun setTimer(context: Context, seconds: Int, message: String, skipUi: Boolean = false): Boolean {
        val intent = Intent(AlarmClock.ACTION_SET_TIMER).apply {
            putExtra(AlarmClock.EXTRA_LENGTH, seconds.coerceAtLeast(1))
            putExtra(AlarmClock.EXTRA_MESSAGE, message.ifBlank { "U.L.T.R.O.N. Timer" })
            putExtra(AlarmClock.EXTRA_SKIP_UI, skipUi)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return startActivitySafely(context, intent, "Timer (${seconds}s)")
    }

    fun openUrl(context: Context, rawUrl: String): Boolean {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(rawUrl)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return startActivitySafely(context, intent, "Link")
    }

    fun dialNumber(context: Context, rawNumber: String): Boolean {
        val number = rawNumber.replace(Regex("[^0-9+*#]"), "")
        val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number")).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return startActivitySafely(context, intent, "Telefone $number")
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
        val bluetoothEnabled = runCatching {
            val bm = context.getSystemService(Context.BLUETOOTH_SERVICE) as? android.bluetooth.BluetoothManager
            bm?.adapter?.isEnabled == true
        }.getOrDefault(false)

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
            "cellularConnected" to cellularConnected,
            "bluetoothEnabled" to bluetoothEnabled
        )
    }

    /**
     * Consulta dispositivos de áudio Bluetooth atualmente conectados via [AudioManager.getDevices]
     * (A2DP, SCO e LE Audio em API 31+), sem exigir permissão perigosa BLUETOOTH_CONNECT em runtime.
     */
    fun getConnectedBluetoothAudioDevices(context: Context): Map<String, Any> {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            ?: return mapOf(
                "connected" to false,
                "devices" to emptyList<String>(),
                "primaryDevice" to "",
            )

        val names = LinkedHashSet<String>()
        try {
            val outputs = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            for (device in outputs) {
                val isBtAudio = device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                    device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                    (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && (
                        device.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                            device.type == AudioDeviceInfo.TYPE_BLE_SPEAKER
                        ))
                if (isBtAudio) {
                    val label = device.productName?.toString()?.trim().orEmpty()
                    names.add(if (label.isNotEmpty()) label else "Fone Bluetooth")
                }
            }
        } catch (_: Throwable) {
        }

        val list = names.toList()
        return mapOf(
            "connected" to list.isNotEmpty(),
            "devices" to list,
            "primaryDevice" to (list.firstOrNull() ?: ""),
        )
    }

    /**
     * Aguarda (em thread de background) um fone Bluetooth de áudio conectar ao Android.
     * Se [preferredName] for informado (ex.: "Attack Shark L30 Pro"), prioriza correspondência
     * parcial case-insensitive, mas aceita qualquer fone A2DP/BLE conectado após o período inicial.
     */
    fun waitForBluetoothAudioDevice(
        context: Context,
        preferredName: String = "",
        timeoutMs: Long = 20000L,
        pollIntervalMs: Long = 450L,
    ): Map<String, Any> {
        val safeTimeout = timeoutMs.coerceIn(1000L, 60000L)
        val safePoll = pollIntervalMs.coerceIn(150L, 2000L)
        val normalizedPref = preferredName.trim().lowercase(Locale.ROOT)
        val startMs = SystemClock.elapsedRealtime()

        fun inspect(): Map<String, Any>? {
            val snap = getConnectedBluetoothAudioDevices(context)
            @Suppress("UNCHECKED_CAST")
            val devices = (snap["devices"] as? List<String>) ?: emptyList()
            if (devices.isEmpty()) return null
            val matched = if (normalizedPref.isNotEmpty()) {
                devices.firstOrNull { d ->
                    val dl = d.lowercase(Locale.ROOT)
                    dl.contains(normalizedPref) ||
                        normalizedPref.split(Regex("\\s+")).any { tok -> tok.length >= 3 && dl.contains(tok) }
                }
            } else {
                null
            }
            val elapsed = (SystemClock.elapsedRealtime() - startMs).coerceAtLeast(0L)
            return mapOf(
                "connected" to true,
                "deviceName" to (matched ?: devices.first()),
                "matchedPreferred" to (matched != null),
                "devices" to devices,
                "elapsedMs" to elapsed,
            )
        }

        inspect()?.let { return it }

        while (SystemClock.elapsedRealtime() - startMs < safeTimeout) {
            try {
                Thread.sleep(safePoll)
            } catch (_: InterruptedException) {
                break
            }
            inspect()?.let { return it }
        }

        val elapsed = (SystemClock.elapsedRealtime() - startMs).coerceAtLeast(0L)
        return mapOf(
            "connected" to false,
            "deviceName" to "",
            "matchedPreferred" to false,
            "devices" to emptyList<String>(),
            "elapsedMs" to elapsed,
        )
    }
}
