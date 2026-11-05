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
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.sqrt

/**
 * UltronAudioService (Wake Word Reliability v1.2.1):
 * 1. Escuta CONTÍNUA e leve: AudioRecord (8 kHz) lido em frames de 100 ms, sem janelas cegas.
 *    Limiar de voz ADAPTATIVO (piso de ruído x margem) no lugar do RMS fixo.
 * 2. Ao detectar voz, libera o AudioRecord (o microfone é exclusivo) e abre o
 *    SpeechRecognizer; ao terminar, reabre a captura. Backoff exponencial para falsos
 *    gatilhos repetidos, mantendo o consumo de bateria sob controle.
 * 3. Half-Duplex Anti-Eco preservado: nunca escuta enquanto o Ultron fala.
 * 4. Watchdog: qualquer falha do AudioRecord/SpeechRecognizer religa a captura com
 *    backoff exponencial (1s até 30s), detecta microfone silenciado pelo sistema e
 *    registra tudo em [diagnostics].
 * 5. Ativação com app em segundo plano/tela bloqueada via notificação full-screen; o
 *    evento fica pendente em [MainActivity] até o Flutter consumi-lo.
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

        /**
         * Motor de detecção realmente em uso. NÃO existe motor de keyword spotting dedicado
         * (Porcupine/openWakeWord/Vosk): a detecção é porta de volume + SpeechRecognizer.
         * Mantido explícito para a UI nunca sugerir um motor que não existe.
         */
        const val ENGINE_DESCRIPTION = "PORTA DE VOLUME + SpeechRecognizer (sem motor KWS dedicado)"
        const val ENGINE_IS_DEDICATED_KWS = false
        const val EXTRA_WAKE_WORD = "ultron_wake_word_trigger"

        const val PREFS_NAME = "ultron_sentinel_prefs"
        const val PREF_ENABLED = "sentinel_enabled"
        const val PREF_BOOT_AUTOSTART = "boot_autostart"

        private const val SAMPLE_RATE_HZ = 8000
        private const val WINDOW_MS = 100

        private const val SLEEP_SPEAKER_GUARD_MS = 400L
        private const val SLEEP_PAUSED_STATE_MS = 1500L
        private const val SLEEP_LOW_BATTERY_MS = 10000L
        private const val POST_SPEECH_ECHO_GUARD_MS = 1100L
        private const val BATTERY_CHECK_INTERVAL_MS = 30_000L

        private const val MIN_VOICE_RMS = 700.0
        private const val MAX_VOICE_RMS = 3500.0
        private const val NOISE_MARGIN = 3.2
        private const val INITIAL_NOISE_FLOOR = 300.0
        private const val VOICE_FRAMES_TO_TRIGGER = 2

        private const val BASE_MISS_COOLDOWN_MS = 1200L
        private const val MAX_MISS_COOLDOWN_MS = 12_000L
        private const val DETECTED_COOLDOWN_MS = 2500L
        private const val RECOGNIZER_WAIT_MS = 10_000L

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

        /** Pausa escolhida pelo usuário na notificação (não persiste entre execuções). */
        @Volatile
        var userPaused: Boolean = false
            private set

        /** O que a UI pode afirmar: serviço vivo, capturando de verdade e não pausado. */
        fun isListeningForReal(): Boolean = isRunning && captureHealthy && !userPaused

        /** Contadores e estado para o painel de diagnóstico no Flutter. */
        object Stats {
            @Volatile var voiceTriggers = 0
            @Volatile var detections = 0
            @Volatile var recognizerMisses = 0
            @Volatile var recognizerErrors = 0
            @Volatile var captureRestarts = 0
            @Volatile var micSilencedEvents = 0
            @Volatile var lastError = "nenhum"
            @Volatile var lastPhrase = ""
            @Volatile var noiseFloor = INITIAL_NOISE_FLOOR
            @Volatile var threshold = MIN_VOICE_RMS
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
                "paused" to userPaused,
                "engine" to ENGINE_DESCRIPTION,
                "dedicatedKws" to ENGINE_IS_DEDICATED_KWS,
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
    private var wakeWordRecognizer: UltronWakeWordRecognizer? = null

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
                // Pausa escolhida pelo usuário não deve ser "ressuscitada" por um restart sticky.
                return if (userPaused) START_NOT_STICKY else START_STICKY
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
            val notification = buildNotification("Escuta contínua ativa — diga \"Ultron\"")
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
        if (now - MainActivity.lastSpeechEndTimestampMs < POST_SPEECH_ECHO_GUARD_MS) return true
        if (now - UltronTtsHelper.lastSpeechEndTimestampMs < POST_SPEECH_ECHO_GUARD_MS) return true
        return false
    }

    /** Watchdog externo: religa a sessão de captura com backoff exponencial em qualquer falha. */
    private fun startEcoVadLoop() {
        if (!workerActive.compareAndSet(false, true)) return

        vadThread = Thread({
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND)
            var backoffMs = 1000L
            try {
                while (workerActive.get()) {
                    try {
                        runCaptureSession()
                        backoffMs = 1000L
                    } catch (e: InterruptedException) {
                        break
                    } catch (e: Exception) {
                        captureHealthy = false
                        Stats.lastError = "${e.javaClass.simpleName}: ${e.message}"
                        Stats.captureRestarts++
                        // Recuperação LIMITADA: sem sucesso real de leitura, desiste em vez de
                        // girar para sempre fingindo que escuta.
                        if (++consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
                            giveUpAfterPersistentFailure()
                            break
                        }
                        updateNotification("Reconectando microfone… (${consecutiveFailures}/$MAX_CONSECUTIVE_FAILURES)")
                        Thread.sleep(backoffMs)
                        backoffMs = (backoffMs * 2).coerceAtMost(MAX_RESTART_BACKOFF_MS)
                    }
                }
            } catch (_: InterruptedException) {
                // Encerramento solicitado pelo onDestroy (interrupt): saída normal.
            } finally {
                captureHealthy = false
                releaseWakeLockSafely()
                isRunning = false
                workerActive.set(false)
            }
        }, "UltronEcoVadThread").also { it.start() }
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

    private fun createRecorder(): AudioRecord {
        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE_HZ,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBuf <= 0) throw IllegalStateException("getMinBufferSize=$minBuf")
        val bufferBytes = minBuf.coerceAtLeast(SAMPLE_RATE_HZ / 2)
        val rec = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            SAMPLE_RATE_HZ,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferBytes
        )
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            rec.release()
            throw IllegalStateException("AudioRecord não inicializou (microfone ocupado?)")
        }
        try {
            rec.startRecording()
        } catch (e: Exception) {
            // Sem release aqui o AudioRecord nativo ficaria vazando a cada tentativa.
            safely("AudioRecord.release após falha de start") { rec.release() }
            throw e
        }
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

    /** Uma sessão de captura; lança exceção em falha para o watchdog religar. */
    private fun runCaptureSession() {
        val windowSamples = (SAMPLE_RATE_HZ * WINDOW_MS) / 1000
        val pcmBuffer = ShortArray(windowSamples)
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        var recorder: AudioRecord? = null

        var noiseFloor = INITIAL_NOISE_FLOOR
        var consecutiveVoiceFrames = 0
        var silentFrames = 0
        var consecutiveMisses = 0

        try {
            while (workerActive.get()) {
                // 1. Economia em bateria crítica (<15% sem carregador): libera o mic e dorme.
                if (isBatteryCriticalUnplugged()) {
                    if (!Stats.economyMode) {
                        Stats.economyMode = true
                        updateNotification("Bateria crítica — escuta em pausa")
                    }
                    releaseRecorder(recorder); recorder = null
                    captureHealthy = false
                    Thread.sleep(SLEEP_LOW_BATTERY_MS)
                    continue
                }
                if (Stats.economyMode) {
                    Stats.economyMode = false
                    updateNotification("Escuta contínua ativa — diga \"Ultron\"")
                }

                // 2. Pausa pelo usuário, em ligação/VoIP ou Flip-to-Shush: microfone liberado.
                val inCall = audioManager != null && audioManager.mode != AudioManager.MODE_NORMAL
                if (userPaused || inCall || MainActivity.isFaceDownGlobal) {
                    consecutiveVoiceFrames = 0
                    releaseRecorder(recorder); recorder = null
                    captureHealthy = false
                    Thread.sleep(SLEEP_PAUSED_STATE_MS)
                    continue
                }

                // 3. Half-Duplex Anti-Eco: NUNCA escuta enquanto o Ultron fala ou o mic principal está aberto.
                if (isSpeakerOrRecognizerBusy(audioManager)) {
                    consecutiveVoiceFrames = 0
                    releaseRecorder(recorder); recorder = null
                    Thread.sleep(SLEEP_SPEAKER_GUARD_MS)
                    continue
                }

                // 4. Garante o AudioRecord aberto (reabre após fala, chamada ou gatilho).
                if (recorder == null) {
                    recorder = createRecorder()
                    silentFrames = 0
                }

                // 5. Leitura bloqueante de 100 ms: sem sono entre frames = sem janela cega.
                val readCount = recorder.read(pcmBuffer, 0, windowSamples)
                if (readCount < 0) {
                    throw IllegalStateException("AudioRecord.read=$readCount")
                }
                if (isSpeakerOrRecognizerBusy(audioManager)) {
                    consecutiveVoiceFrames = 0
                    continue
                }
                if (readCount == 0) {
                    // Leitura vazia não é captura comprovada: conta para o watchdog para que
                    // a UI nunca continue dizendo "escutando" com o microfone travado.
                    captureHealthy = false
                    if (++silentFrames >= SILENT_FRAMES_BEFORE_RESTART) {
                        Stats.micSilencedEvents++
                        throw IllegalStateException("AudioRecord sem dados por 30 s")
                    }
                    continue
                }

                val rms = computeRms(pcmBuffer, readCount)

                // 6. Microfone silenciado pelo sistema (frames 100% zero por 30 s): é FALHA,
                //    não escuta. Vai ao watchdog (backoff + limite), nunca é tratada como sucesso.
                if (rms == 0.0) {
                    if (++silentFrames >= SILENT_FRAMES_BEFORE_RESTART) {
                        Stats.micSilencedEvents++
                        throw IllegalStateException("Microfone silenciado pelo sistema (áudio zerado por 30 s)")
                    }
                } else {
                    silentFrames = 0
                    // Sucesso REAL: áudio não nulo lido do AudioRecord.
                    captureHealthy = true
                    consecutiveFailures = 0
                }

                // 7. Limiar adaptativo: piso de ruído (média móvel) x margem.
                val threshold = (noiseFloor * NOISE_MARGIN).coerceIn(MIN_VOICE_RMS, MAX_VOICE_RMS)
                Stats.noiseFloor = noiseFloor
                Stats.threshold = threshold

                if (rms >= threshold) {
                    consecutiveVoiceFrames++
                    if (consecutiveVoiceFrames >= VOICE_FRAMES_TO_TRIGGER) {
                        consecutiveVoiceFrames = 0
                        // O microfone é exclusivo: libera antes de abrir o SpeechRecognizer.
                        releaseRecorder(recorder); recorder = null
                        // Enquanto o ASR detém o microfone não há captura contínua real.
                        captureHealthy = false
                        val detected = onVoiceWakeTriggered()
                        if (detected) {
                            consecutiveMisses = 0
                            Thread.sleep(DETECTED_COOLDOWN_MS)
                        } else {
                            consecutiveMisses++
                            val cooldown = (BASE_MISS_COOLDOWN_MS shl
                                (consecutiveMisses - 1).coerceAtMost(4))
                                .coerceAtMost(MAX_MISS_COOLDOWN_MS)
                            Thread.sleep(cooldown)
                        }
                    }
                } else {
                    consecutiveVoiceFrames = 0
                    noiseFloor = (noiseFloor * 0.98 + rms * 0.02).coerceIn(50.0, 1500.0)
                    if (consecutiveMisses > 0 && rms < threshold * 0.5) {
                        // Ambiente calmo: perdoa falsos gatilhos antigos aos poucos.
                        consecutiveMisses = 0
                    }
                }
            }
        } finally {
            releaseRecorder(recorder)
        }
    }

    private fun computeRms(buffer: ShortArray, count: Int): Double {
        var sumSq = 0L
        for (i in 0 until count) {
            val s = buffer[i].toLong()
            sumSq += s * s
        }
        return sqrt(sumSq.toDouble() / count.coerceAtLeast(1))
    }

    /** Abre o reconhecedor e BLOQUEIA o thread de captura até ele terminar. Retorna true se ativou. */
    private fun onVoiceWakeTriggered(): Boolean {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (isSpeakerOrRecognizerBusy(audioManager)) return false

        wakeLock?.acquire(15_000L)
        val nowStr = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())
        lastTriggerTimestamp = nowStr
        Stats.voiceTriggers++
        updateNotification("Verificando palavra 'Ultron'... ($nowStr)")

        val latch = CountDownLatch(1)
        var detected = false

        wakeWordRecognizer?.destroy()
        val recognizer = UltronWakeWordRecognizer(
            context = applicationContext,
            onHotwordDetected = { matched ->
                detected = true
                Stats.detections++
                Stats.lastPhrase = matched
                updateNotification("Ativado por voz: \"$matched\"")
                onWakeConfirmed(matched)
            },
            onFinished = { _, error ->
                if (!detected) {
                    Stats.recognizerMisses++
                    when (error) {
                        UltronWakeWordRecognizer.NO_ERROR,
                        SpeechRecognizer.ERROR_NO_MATCH,
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> Unit
                        else -> {
                            Stats.recognizerErrors++
                            Stats.lastError = "SpeechRecognizer erro $error"
                        }
                    }
                }
                updateNotification("Escuta contínua ativa — diga \"Ultron\"")
                latch.countDown()
            }
        )
        wakeWordRecognizer = recognizer
        recognizer.startListening()

        if (!latch.await(RECOGNIZER_WAIT_MS, TimeUnit.MILLISECONDS)) {
            recognizer.destroy()
            Stats.recognizerErrors++
            Stats.lastError = "SpeechRecognizer não respondeu em ${RECOGNIZER_WAIT_MS / 1000}s"
            // onFinished não virá: a notificação permanente não pode ficar presa em "Verificando".
            updateNotification("Escuta contínua ativa — diga \"Ultron\"")
        }
        // WakeLock só pelo tempo estritamente necessário: solta assim que o reconhecedor termina.
        releaseWakeLockSafely()
        return detected
    }

    /**
     * Wake word confirmada: guarda o evento como pendente (nunca perdido) e, se o app não
     * está em primeiro plano (segundo plano ou tela bloqueada), sobe a notificação full-screen.
     * O Flutter só processa após a autenticação normal do app — o Action Gate é preservado.
     */
    private fun onWakeConfirmed(phrase: String) {
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
        // O foreground service sobrevive ao swipe do app; não é erro (não poluir o diagnóstico).
        wakeLogW("app removido dos recentes; serviço mantido")
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        workerActive.set(false)
        isRunning = false
        captureHealthy = false
        Stats.economyMode = false
        vadThread?.interrupt()
        wakeWordRecognizer?.destroy()
        wakeWordRecognizer = null
        releaseWakeLockSafely()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
