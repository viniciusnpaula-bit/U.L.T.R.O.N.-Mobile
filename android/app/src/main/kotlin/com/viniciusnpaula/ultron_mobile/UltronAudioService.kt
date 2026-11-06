package com.viniciusnpaula.ultron_mobile

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.BatteryManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.speech.SpeechRecognizer
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.KeywordSpotter
import com.k2fsa.sherpa.onnx.KeywordSpotterConfig
import com.k2fsa.sherpa.onnx.OnlineModelConfig
import com.k2fsa.sherpa.onnx.OnlineTransducerModelConfig
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Sentinela de wake word com sherpa-onnx Zipformer KWS.
 * O modelo roda localmente/offline e recebe PCM16 mono a 16 kHz em frames de 100 ms.
 * O AudioRecord só é liberado para o reconhecimento de comando depois da detecção KWS.
 * Half-duplex anti-eco, serviço em primeiro plano, watchdog, backoff e notificação
 * de falha são mantidos. Energia de áudio nunca é usada como gatilho de ativação.
 */
class UltronAudioService : Service() {

    companion object {
        private const val CHANNEL_ID = "ultron_eco_voice_channel"
        private const val WAKE_CHANNEL_ID = "ultron_wake_alert_channel"
        private const val NOTIFICATION_ID = 2049
        private const val WAKE_NOTIFICATION_ID = 2050
        const val ACTION_STOP = "com.viniciusnpaula.ultron_mobile.STOP_AUDIO_SERVICE"
        const val ACTION_SAY_TIME = "com.viniciusnpaula.ultron_mobile.SAY_TIME_OFFLINE"
        const val ACTION_TOGGLE_PAUSE = "com.viniciusnpaula.ultron_mobile.TOGGLE_PAUSE_AUDIO_SERVICE"

        const val ENGINE_DESCRIPTION = "sherpa-onnx Zipformer KWS (offline / CPU)"
        const val ENGINE_IS_DEDICATED_KWS = true
        private const val MODEL_DIR = "sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01-mobile"
        const val EXTRA_WAKE_WORD = "ultron_wake_word_trigger"

        const val PREFS_NAME = "ultron_sentinel_prefs"
        const val PREF_ENABLED = "sentinel_enabled"
        const val PREF_BOOT_AUTOSTART = "boot_autostart"

        private const val SAMPLE_RATE_HZ = 16000
        private const val WINDOW_MS = 100

        private const val SLEEP_SPEAKER_GUARD_MS = 400L
        private const val SLEEP_PAUSED_STATE_MS = 1500L
        private const val SLEEP_LOW_BATTERY_MS = 10000L
        private const val POST_SPEECH_ECHO_GUARD_MS = 1100L
        private const val BATTERY_CHECK_INTERVAL_MS = 30_000L

        private const val INITIAL_NOISE_FLOOR = 300.0
        private const val WAKE_HANDOFF_GUARD_MS = 2500L

        private const val SILENT_FRAMES_BEFORE_RESTART = 300 // 30 s de zeros = mic silenciado
        private const val MAX_RESTART_BACKOFF_MS = 30_000L
        private const val MAX_CONSECUTIVE_FAILURES = 8

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var lastTriggerTimestamp: String = "Nenhum"
            private set

        /** true somente após uma leitura real de áudio; false em falha, silêncio forçado ou pausa. */
        @Volatile
        var captureHealthy: Boolean = false
            private set

        @Volatile
        var modelLoaded: Boolean = false
            private set

        /** Pausa escolhida pelo usuário na notificação (não persiste entre execuções). */
        @Volatile
        var userPaused: Boolean = false
            private set

        /** O que a UI pode afirmar: serviço vivo, capturando de verdade e não pausado. */
        fun isListeningForReal(): Boolean = isRunning && modelLoaded && captureHealthy && !userPaused

        /** Contadores e estado para o painel de diagnóstico no Flutter. */
        object Stats {
            @Volatile var voiceTriggers = 0
            @Volatile var detections = 0
            @Volatile var recognizerMisses = 0
            @Volatile var recognizerErrors = 0
            @Volatile var kwsErrors = 0
            @Volatile var captureRestarts = 0
            @Volatile var micSilencedEvents = 0
            @Volatile var lastError = "nenhum"
            @Volatile var lastPhrase = ""
            @Volatile var noiseFloor = INITIAL_NOISE_FLOOR
            @Volatile var threshold = 0.0
            @Volatile var economyMode = false
        }

        fun diagnostics(context: Context): Map<String, Any> {
            val hasMic = ContextCompat.checkSelfPermission(
                context, Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val ignoringBattery = pm?.isIgnoringBatteryOptimizations(context.packageName) ?: false
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            return mapOf(
                "running" to isRunning,
                "capturing" to isListeningForReal(),
                "modelLoaded" to modelLoaded,
                "paused" to userPaused,
                "engine" to ENGINE_DESCRIPTION,
                "dedicatedKws" to (ENGINE_IS_DEDICATED_KWS && modelLoaded),
                "sdk" to Build.VERSION.SDK_INT,
                "notificationsPermission" to (
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                        ContextCompat.checkSelfPermission(
                            context, Manifest.permission.POST_NOTIFICATIONS
                        ) == PackageManager.PERMISSION_GRANTED
                    ),
                "micPermission" to hasMic,
                "ignoringBatteryOptimizations" to ignoringBattery,
                "bootAutostart" to prefs.getBoolean(PREF_BOOT_AUTOSTART, false),
                "recognitionAvailable" to SpeechRecognizer.isRecognitionAvailable(context),
                "lastTrigger" to lastTriggerTimestamp,
                "voiceTriggers" to Stats.voiceTriggers,
                "detections" to Stats.detections,
                "recognizerMisses" to Stats.recognizerMisses,
                "recognizerErrors" to Stats.recognizerErrors,
                "kwsErrors" to Stats.kwsErrors,
                "captureRestarts" to Stats.captureRestarts,
                "micSilencedEvents" to Stats.micSilencedEvents,
                "lastError" to Stats.lastError,
                "lastPhrase" to Stats.lastPhrase,
                "noiseFloor" to Stats.noiseFloor.toInt(),
                "threshold" to Stats.threshold.toInt(),
                "economyMode" to Stats.economyMode
            )
        }
    }

    private val workerActive = AtomicBoolean(false)
    private var vadThread: Thread? = null
    private var wakeLock: PowerManager.WakeLock? = null
    @Volatile
    private var keywordSpotter: KeywordSpotter? = null

    @Volatile
    private var wakeHandoffUntilMs: Long = 0L

    private var lastBatteryCheckMs = 0L
    private var batteryCritical = false
    @Volatile
    private var consecutiveFailures = 0

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Ultron::EcoVadWakeLock").apply {
            setReferenceCounted(false)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit().putBoolean(PREF_ENABLED, false).apply()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_SAY_TIME -> {
                UltronTtsHelper.answerQuickOfflineQuery(this, "que horas são")
                return START_STICKY
            }
            ACTION_TOGGLE_PAUSE -> {
                userPaused = !userPaused
                if (userPaused) captureHealthy = false
                updateNotification(
                    if (userPaused) "Escuta PAUSADA — microfone liberado"
                    else "Escuta contínua ativa — diga \"Ultron\""
                )
                return START_STICKY
            }
        }

        val hasMicPerm = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasMicPerm) {
            Stats.lastError = "RECORD_AUDIO negada"
            stopSelf()
            return START_NOT_STICKY
        }

        // O sistema pode recusar um serviço de microfone iniciado fora de contexto permitido
        // (Android 12+ em segundo plano / 14+). Não há contorno: registra e encerra com segurança.
        try {
            val notification = buildNotification("Preparando motor KWS offline…")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Stats.lastError = "startForeground recusado: ${e.javaClass.simpleName}"
            wakeLogW("startForeground recusado pelo sistema: ${e.javaClass.simpleName}")
            getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit().putBoolean(PREF_ENABLED, false).apply()
            stopSelf()
            return START_NOT_STICKY
        }

        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putBoolean(PREF_ENABLED, true).apply()
        userPaused = false
        isRunning = true
        startEcoVadLoop()
        return START_STICKY
    }

    private fun isSpeakerOrRecognizerBusy(audioManager: AudioManager?): Boolean {
        val now = System.currentTimeMillis()
        if (MainActivity.isForegroundRecognizerActive) return true
        if (MainActivity.isUltronSpeakingGlobal || UltronTtsHelper.isSpeaking) return true
        if (audioManager?.isMusicActive == true) return true
        if (now < wakeHandoffUntilMs) return true
        if (now - MainActivity.lastSpeechEndTimestampMs < POST_SPEECH_ECHO_GUARD_MS) return true
        if (now - UltronTtsHelper.lastSpeechEndTimestampMs < POST_SPEECH_ECHO_GUARD_MS) return true
        return false
    }

    /** Inicializa o modelo real e recupera falhas de captura/decodificação com backoff. */
    private fun startEcoVadLoop() {
        if (!workerActive.compareAndSet(false, true)) return
        vadThread = Thread({
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND)
            var backoffMs = 1000L
            try {
                try {
                    if (keywordSpotter == null) keywordSpotter = createKeywordSpotter()
                    modelLoaded = keywordSpotter != null
                    if (!modelLoaded) throw IllegalStateException("KeywordSpotter nulo")
                    Stats.lastError = "nenhum"
                    updateNotification("sherpa-onnx KWS carregado — diga \"Ultron\"")
                } catch (e: Exception) {
                    modelLoaded = false
                    captureHealthy = false
                    Stats.kwsErrors++
                    Stats.lastError = "Falha ao carregar modelo sherpa-onnx: ${e.javaClass.simpleName}: ${e.message}"
                    getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit().putBoolean(PREF_ENABLED, false).apply()
                    updateNotification("KWS indisponível — modelo não carregado")
                    notifyKwsFailure(Stats.lastError)
                    stopSelf()
                    return@Thread
                }
                while (workerActive.get()) {
                    try {
                        runCaptureSession()
                        backoffMs = 1000L
                    } catch (e: InterruptedException) {
                        break
                    } catch (e: Exception) {
                        captureHealthy = false
                        Stats.lastError = "${e.javaClass.simpleName}: ${e.message}"
                        Stats.kwsErrors++
                        Stats.captureRestarts++
                        if (++consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
                            giveUpAfterPersistentFailure()
                            break
                        }
                        updateNotification("Reconectando microfone/KWS… (${consecutiveFailures}/$MAX_CONSECUTIVE_FAILURES)")
                        Thread.sleep(backoffMs)
                        backoffMs = (backoffMs * 2).coerceAtMost(MAX_RESTART_BACKOFF_MS)
                    }
                }
            } catch (_: InterruptedException) {
                // Encerramento solicitado pelo onDestroy.
            } finally {
                captureHealthy = false
                releaseWakeLockSafely()
                isRunning = false
                workerActive.set(false)
            }
        }, "UltronSherpaKwsThread").also { it.start() }
    }

    private fun notifyKwsFailure(message: String) {
        safely("notificar falha KWS") {
            val manager = getSystemService(NOTIFICATION_SERVICE) as? NotificationManager
            val open = PendingIntent.getActivity(
                this, 31, Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            manager?.notify(
                WAKE_NOTIFICATION_ID,
                NotificationCompat.Builder(this, WAKE_CHANNEL_ID)
                    .setContentTitle("U.L.T.R.O.N. sem detecção de ativação")
                    .setContentText(message.take(180))
                    .setSmallIcon(android.R.drawable.ic_dialog_alert)
                    .setAutoCancel(true)
                    .setContentIntent(open)
                    .build()
            )
        }
    }

    /** Falha persistente: para o serviço, desliga o estado "ligado" e avisa o usuário. */
    private fun giveUpAfterPersistentFailure() {
        wakeLogW("captura falhou $MAX_CONSECUTIVE_FAILURES vezes seguidas; encerrando sentinela")
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putBoolean(PREF_ENABLED, false).apply()
        safely("notificar falha persistente") {
            val nm = getSystemService(NOTIFICATION_SERVICE) as? NotificationManager
            val open = PendingIntent.getActivity(
                this, 30, Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            nm?.notify(
                WAKE_NOTIFICATION_ID,
                NotificationCompat.Builder(this, WAKE_CHANNEL_ID)
                    .setContentTitle("U.L.T.R.O.N. parou de escutar")
                    .setContentText("Não foi possível acessar o microfone. Toque para reativar.")
                    .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                    .setAutoCancel(true)
                    .setContentIntent(open)
                    .build()
            )
        }
        stopSelf()
    }

    private fun createKeywordSpotter(): KeywordSpotter {
        val modelConfig = OnlineModelConfig(
            transducer = OnlineTransducerModelConfig(
                encoder = "$MODEL_DIR/encoder-epoch-12-avg-2-chunk-16-left-64.int8.onnx",
                decoder = "$MODEL_DIR/decoder-epoch-12-avg-2-chunk-16-left-64.onnx",
                joiner = "$MODEL_DIR/joiner-epoch-12-avg-2-chunk-16-left-64.int8.onnx",
            ),
            tokens = "$MODEL_DIR/tokens.txt",
            numThreads = 2,
            provider = "cpu",
            modelType = "zipformer2",
            modelingUnit = "bpe",
            bpeVocab = "$MODEL_DIR/bpe.model",
        )
        val config = KeywordSpotterConfig(
            featConfig = FeatureConfig(sampleRate = SAMPLE_RATE_HZ, featureDim = 80),
            modelConfig = modelConfig,
            keywordsFile = "$MODEL_DIR/keywords.txt",
            maxActivePaths = 4,
            keywordsScore = 1.5f,
            keywordsThreshold = 0.25f,
            numTrailingBlanks = 1,
        )
        return KeywordSpotter(assetManager = assets, config = config)
    }

    private fun createRecorder(): AudioRecord {
        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE_HZ, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBuf <= 0) throw IllegalStateException("getMinBufferSize=$minBuf")
        val frameBytes = (SAMPLE_RATE_HZ * WINDOW_MS / 1000) * 2
        val rec = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            SAMPLE_RATE_HZ,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            minBuf.coerceAtLeast(frameBytes * 2)
        )
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            rec.release()
            throw IllegalStateException("AudioRecord não inicializou (microfone ocupado?)")
        }
        rec.startRecording()
        if (rec.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            rec.release()
            throw IllegalStateException("AudioRecord não entrou em gravação")
        }
        return rec
    }

    private fun releaseRecorder(recorder: AudioRecord?) {
        safely("AudioRecord.stop") { recorder?.stop() }
        safely("AudioRecord.release") { recorder?.release() }
    }

    /**
     * Captura PCM16 mono a 16 kHz e alimenta exclusivamente o sherpa-onnx KWS.
     * Amostras zeradas são apenas um diagnóstico de falha do microfone, nunca um gatilho.
     */
    private fun runCaptureSession() {
        val spotter = keywordSpotter ?: throw IllegalStateException("Motor sherpa-onnx não inicializado")
        val windowSamples = (SAMPLE_RATE_HZ * WINDOW_MS) / 1000
        val pcmBuffer = ShortArray(windowSamples)
        val floatBuffer = FloatArray(windowSamples)
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        var recorder: AudioRecord? = null
        var silentFrames = 0
        val stream = spotter.createStream()
        if (stream.ptr == 0L) {
            stream.release()
            throw IllegalStateException("sherpa-onnx não criou o stream KWS")
        }

        try {
            while (workerActive.get()) {
                if (isBatteryCriticalUnplugged()) {
                    if (!Stats.economyMode) {
                        Stats.economyMode = true
                        updateNotification("Bateria crítica — escuta em pausa")
                    }
                    releaseRecorder(recorder)
                    recorder = null
                    captureHealthy = false
                    Thread.sleep(SLEEP_LOW_BATTERY_MS)
                    continue
                }
                if (Stats.economyMode) {
                    Stats.economyMode = false
                    updateNotification("sherpa-onnx KWS carregado — diga \"Ultron\"")
                }

                val inCall = audioManager != null && audioManager.mode != AudioManager.MODE_NORMAL
                if (userPaused || inCall || MainActivity.isFaceDownGlobal) {
                    releaseRecorder(recorder)
                    recorder = null
                    captureHealthy = false
                    Thread.sleep(SLEEP_PAUSED_STATE_MS)
                    continue
                }

                // Half-duplex: libera o microfone durante comandos, TTS e transferência do evento.
                if (isSpeakerOrRecognizerBusy(audioManager)) {
                    releaseRecorder(recorder)
                    recorder = null
                    captureHealthy = false
                    Thread.sleep(SLEEP_SPEAKER_GUARD_MS)
                    continue
                }

                if (recorder == null) recorder = createRecorder()
                val readCount = recorder.read(pcmBuffer, 0, windowSamples)
                if (readCount < 0) throw IllegalStateException("AudioRecord.read=$readCount")
                if (readCount == 0) continue

                var hasNonZeroSample = false
                for (i in 0 until readCount) {
                    val sample = pcmBuffer[i].toInt()
                    if (sample != 0) hasNonZeroSample = true
                    floatBuffer[i] = sample / 32768.0f
                }
                if (hasNonZeroSample) {
                    silentFrames = 0
                    captureHealthy = true
                    consecutiveFailures = 0
                } else {
                    captureHealthy = false
                    if (++silentFrames >= SILENT_FRAMES_BEFORE_RESTART) {
                        Stats.micSilencedEvents++
                        throw IllegalStateException("Microfone sem amostras não nulas por 30 s")
                    }
                }

                // O nível de volume não participa da detecção: somente o decoder KWS decide.
                val samples = if (readCount == windowSamples) floatBuffer else floatBuffer.copyOf(readCount)
                stream.acceptWaveform(samples, sampleRate = SAMPLE_RATE_HZ)

                var detectedKeyword = ""
                while (spotter.isReady(stream)) {
                    spotter.decode(stream)
                    val result = spotter.getResult(stream)
                    if (result.keyword.isNotBlank()) {
                        spotter.reset(stream)
                        detectedKeyword = result.keyword
                        break
                    }
                }

                if (detectedKeyword.isNotBlank()) {
                    // O microfone KWS é liberado antes do reconhecimento do comando no fluxo Flutter.
                    releaseRecorder(recorder)
                    recorder = null
                    captureHealthy = false
                    Stats.detections++
                    Stats.voiceTriggers++
                    lastTriggerTimestamp = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())
                    Stats.lastPhrase = detectedKeyword
                    wakeHandoffUntilMs = System.currentTimeMillis() + WAKE_HANDOFF_GUARD_MS
                    updateNotification("Palavra \"Ultron\" detectada — aguardando comando")
                    onWakeConfirmed("Ultron")
                    return
                }
            }
        } finally {
            releaseRecorder(recorder)
            captureHealthy = false
            stream.release()
        }
    }

    /**
     * Wake word confirmada: guarda o evento como pendente (nunca perdido) e, se o app não
     * está em primeiro plano (segundo plano ou tela bloqueada), sobe a notificação full-screen.
     * O Flutter só processa após a autenticação normal do app — o Action Gate é preservado.
     */
    private fun onWakeConfirmed(phrase: String) {
        wakeHandoffUntilMs = System.currentTimeMillis() + WAKE_HANDOFF_GUARD_MS
        MainActivity.notifyWakeWord(phrase)
        if (!MainActivity.isActivityResumed) {
            showWakeAlert()
        }
    }

    private fun showWakeAlert() {
        try {
            val nm = getSystemService(NOTIFICATION_SERVICE) as? NotificationManager ?: return
            val openIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(EXTRA_WAKE_WORD, true)
            }
            val pending = PendingIntent.getActivity(
                this, 10, openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val builder = NotificationCompat.Builder(this, WAKE_CHANNEL_ID)
                .setContentTitle("U.L.T.R.O.N. ouviu você")
                .setContentText("Toque para falar o comando")
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setTimeoutAfter(15_000L)
                .setContentIntent(pending)
            val canFullScreen = Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
                nm.canUseFullScreenIntent()
            if (canFullScreen) {
                builder.setFullScreenIntent(pending, true)
            }
            nm.notify(WAKE_NOTIFICATION_ID, builder.build())
        } catch (e: Exception) {
            Stats.lastError = "wake alert: ${e.message}"
        }
    }

    /** Verifica a bateria no máximo a cada 30 s (antes era a cada frame). */
    private fun isBatteryCriticalUnplugged(): Boolean {
        val now = System.currentTimeMillis()
        if (now - lastBatteryCheckMs < BATTERY_CHECK_INTERVAL_MS) return batteryCritical
        lastBatteryCheckMs = now
        batteryCritical = try {
            val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
            val level = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 50
            val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL
            level in 1..15 && !charging
        } catch (e: Exception) {
            wakeLogW("falha ao ler status de bateria: ${e.javaClass.simpleName}")
            false
        }
        return batteryCritical
    }

    private fun updateNotification(subtitle: String) {
        val manager = getSystemService(NOTIFICATION_SERVICE) as? NotificationManager ?: return
        manager.notify(NOTIFICATION_ID, buildNotification(subtitle))
    }

    private fun buildNotification(subtitle: String): Notification {
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingOpen = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, UltronAudioService::class.java).apply {
            action = ACTION_STOP
        }
        val pendingStop = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val timeIntent = Intent(this, UltronAudioService::class.java).apply {
            action = ACTION_SAY_TIME
        }
        val pendingTime = PendingIntent.getService(
            this,
            2,
            timeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val pauseIntent = Intent(this, UltronAudioService::class.java).apply {
            action = ACTION_TOGGLE_PAUSE
        }
        val pendingPause = PendingIntent.getService(
            this,
            3,
            pauseIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("U.L.T.R.O.N. Sentinela de Voz")
            .setContentText(subtitle)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingOpen)
            .addAction(
                android.R.drawable.ic_media_pause,
                if (userPaused) "Retomar" else "Pausar",
                pendingPause
            )
            .addAction(android.R.drawable.ic_lock_idle_alarm, "Que horas são?", pendingTime)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Parar Escuta", pendingStop)
            .build()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "U.L.T.R.O.N. Sentinela de Voz",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Escuta contínua da palavra de ativação com bloqueio Anti-Eco"
                    setShowBadge(false)
                }
            )
            manager.createNotificationChannel(
                NotificationChannel(
                    WAKE_CHANNEL_ID,
                    "U.L.T.R.O.N. Ativação por voz",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Abre o U.L.T.R.O.N. quando você diz a palavra de ativação"
                    setShowBadge(false)
                }
            )
        }
    }

    private fun releaseWakeLockSafely() {
        safely("WakeLock.release") {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // O foreground service sobrevive ao swipe do app; apenas registra para diagnóstico.
        Stats.lastError = "app removido dos recentes (serviço mantido)"
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        workerActive.set(false)
        isRunning = false
        vadThread?.interrupt()
        modelLoaded = false
        safely("KeywordSpotter.release") { keywordSpotter?.release() }
        keywordSpotter = null
        releaseWakeLockSafely()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
