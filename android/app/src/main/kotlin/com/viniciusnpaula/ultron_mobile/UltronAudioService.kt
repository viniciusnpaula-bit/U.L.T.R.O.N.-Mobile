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
import android.speech.SpeechRecognizer
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.sqrt

/**
 * UltronAudioService (motor KWS dedicado v1.3.0):
 * 1. Escuta CONTÍNUA e leve: um único AudioRecord (16 kHz, mono, PCM16) lido em frames
 *    de 512 amostras (32 ms), sem janelas cegas. Cada frame alimenta o Porcupine e o
 *    anel de pre-roll de 1,5 s. O microfone nunca é solto entre a palavra e o comando.
 * 2. Ao detectar "Ultron", o Vosk transcreve o anel de pre-roll mais o áudio ao vivo,
 *    sem handoff do microfone nem SpeechRecognizer. Transcrição vazia = miss silencioso
 *    com cooldown e backoff progressivo (5s/10s/20s, teto 30s).
 * 3. Half-Duplex Anti-Eco preservado: nunca escuta enquanto o Ultron fala.
 * 4. Watchdog: falha de AudioRecord ou microfone silenciado religa a captura com
 *    backoff exponencial (1s até 30s), limite de 8 falhas consecutivas.
 * 5. Sem motor KWS configurado (sem AccessKey ou sem .ppn): o loop encerra, o diagnóstico
 *    expõe o motivo e a voz manual continua funcionando.
 * 6. Ativação com app em segundo plano/tela bloqueada via notificação full-screen; o
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

        const val EXTRA_WAKE_WORD = "ultron_wake_word_trigger"

        const val PREFS_NAME = "ultron_sentinel_prefs"
        const val PREF_ENABLED = "sentinel_enabled"
        const val PREF_BOOT_AUTOSTART = "boot_autostart"

        private const val SAMPLE_RATE_HZ = 16_000
        private const val PREROLL_SAMPLES = 24_000 // 1,5 s de pre-roll a 16 kHz

        private const val SLEEP_SPEAKER_GUARD_MS = 400L
        private const val SLEEP_PAUSED_STATE_MS = 1500L
        private const val SLEEP_LOW_BATTERY_MS = 10000L
        private const val POST_SPEECH_ECHO_GUARD_MS = 1100L
        private const val BATTERY_CHECK_INTERVAL_MS = 30_000L

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
            @Volatile var noiseFloor = 300.0
            @Volatile var threshold = 0.0 // sem gate; mantido so para o contrato do Dart
            @Volatile var economyMode = false

            // Motor KWS dedicado (Task 7+)
            @Volatile var wakeDetections = 0
            @Volatile var voskCommands = 0
            @Volatile var voskLoadMs = 0L
            @Volatile var lastCommandMs = 0L
            @Volatile var voskResident = false
            @Volatile var kwsConfigured = false
            @Volatile var kwsUnavailableReason: String = "nao inicializado"
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
                "engine" to if (Stats.kwsConfigured) "Porcupine pt-BR + Vosk (KWS dedicado)"
                            else "KWS nao configurado",
                "dedicatedKws" to Stats.kwsConfigured,
                "kwsUnavailableReason" to Stats.kwsUnavailableReason,
                "wakeDetections" to Stats.wakeDetections,
                "voskCommands" to Stats.voskCommands,
                "voskLoadMs" to Stats.voskLoadMs,
                "lastCommandMs" to Stats.lastCommandMs,
                "voskResident" to Stats.voskResident,
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
        val spotter = PorcupineKeywordSpotter(applicationContext, BuildConfig.PORCUPINE_ACCESS_KEY)
        spotter.init()
        Stats.kwsConfigured = spotter.isConfigured
        Stats.kwsUnavailableReason = spotter.unavailableReason ?: ""
        // Falha rápida: sem motor configurado o serviço não lê nem descarta áudio, nem deixa
        // a UI dizer "capturando" (mesmo problema da v1.2.1). A voz manual segue funcionando.
        if (!spotter.isConfigured) {
            captureHealthy = false
            Stats.lastError = "KWS indisponível: ${Stats.kwsUnavailableReason}"
            updateNotification("KWS não configurado — ativação por voz indisponível")
            spotter.close()
            return
        }

        val transcriber = VoskCommandTranscriber(applicationContext)
        val ring = AudioRingBuffer(PREROLL_SAMPLES)
        val backoff = FalseTriggerBackoff()
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        var recorder: AudioRecord? = null
        var silentFrames = 0
        // Alocado uma vez fora do lixo: 512 amostras por frame (32 ms a 16 kHz).
        var frame = ShortArray(spotter.frameLength)

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
                    releaseRecorder(recorder); recorder = null
                    captureHealthy = false
                    Thread.sleep(SLEEP_PAUSED_STATE_MS)
                    continue
                }

                // 3. Half-Duplex Anti-Eco: NUNCA escuta enquanto o Ultron fala.
                if (isSpeakerOrRecognizerBusy(audioManager)) {
                    releaseRecorder(recorder); recorder = null
                    Thread.sleep(SLEEP_SPEAKER_GUARD_MS)
                    continue
                }

                // 4. Garante o AudioRecord aberto.
                if (recorder == null) {
                    recorder = createRecorder()
                    silentFrames = 0
                }

                // 5. Leitura bloqueante de um frame 16 kHz (32 ms): sem sono entre frames.
                val readCount = recorder.read(frame, 0, frame.size)
                if (readCount < 0) {
                    throw IllegalStateException("AudioRecord.read=$readCount")
                }
                if (isSpeakerOrRecognizerBusy(audioManager)) {
                    continue
                }
                if (readCount == 0) {
                    captureHealthy = false
                    if (++silentFrames >= SILENT_FRAMES_BEFORE_RESTART) {
                        Stats.micSilencedEvents++
                        throw IllegalStateException("AudioRecord sem dados por 30 s")
                    }
                    continue
                }

                val rms = computeRms(frame, readCount)
                // 6. Microfone silenciado pelo sistema (áudio zerado por 30 s): é FALHA,
                //    nunca captura. Vai ao watchdog com backoff e limite de 8 falhas.
                if (rms == 0.0) {
                    if (++silentFrames >= SILENT_FRAMES_BEFORE_RESTART) {
                        Stats.micSilencedEvents++
                        throw IllegalStateException("Microfone silenciado pelo sistema (áudio zerado)")
                    }
                } else {
                    silentFrames = 0
                    captureHealthy = true
                    consecutiveFailures = 0
                }
                Stats.noiseFloor = rms // telemetria apenas; nunca é gatilho de ativação

                // 7. Frame vai para o anel de pre-roll e para o Porcupine.
                ring.write(frame, readCount)
                val triggered = spotter.process(frame)
                if (!triggered) {
                    backoff.onQuiet(System.currentTimeMillis())
                    transcriber.unloadAfterIdle(System.currentTimeMillis())
                    continue
                }

                // 8. Gatilho: transcreve pre-roll + ao vivo SEM soltar o microfone.
                captureHealthy = true
                val activeRecorder = recorder ?: continue
                val phrase = onVoiceWakeTriggered(ring.snapshot(), transcriber) { buffer ->
                    activeRecorder.read(buffer, 0, buffer.size)
                }
                ring.clear()
                if (phrase != null) {
                    backoff.onSuccess(System.currentTimeMillis())
                    onWakeConfirmed(phrase)
                } else {
                    Thread.sleep(backoff.onMiss(System.currentTimeMillis()))
                }
            }
        } finally {
            releaseRecorder(recorder)
            spotter.close()
            transcriber.close()
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

    /**
     * Gatilho confirmado: transcreve pre-roll + ao vivo com o Vosk e devolve a frase pronta
     * para o Flutter, ou null quando não houve comando útil. O microfone NÃO é solto entre
     * a palavra e o comando (sem handoff: o início do comando está no anel de pre-roll).
     *
     * Retorna "ultron" sozinho quando o Vosk está indisponível: o Dart reconhece o hotword
     * sem comando e oferece a voz manual.
     */
    private fun onVoiceWakeTriggered(
        preroll: ShortArray,
        transcriber: VoskCommandTranscriber,
        readMore: (ShortArray) -> Int,
    ): String? {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (isSpeakerOrRecognizerBusy(audioManager)) return null

        val nowStr = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())
        lastTriggerTimestamp = nowStr
        Stats.voiceTriggers++
        Stats.wakeDetections++
        updateNotification("Palavra detectada — ouvindo comando ($nowStr)")

        wakeLock?.acquire(15_000L)
        val startedMs = System.currentTimeMillis()
        val phrase: String? = if (!transcriber.ensureLoaded()) {
            Stats.lastError = transcriber.lastError ?: "Vosk indisponível"
            null
        } else {
            val text = transcriber.transcribe(preroll, readMore).trim()
            if (text.length < 2) null else WakePhraseComposer.ensurePhrase(text)
        }
        Stats.lastCommandMs = System.currentTimeMillis() - startedMs
        releaseWakeLockSafely()
        updateNotification("Escuta contínua ativa — diga \"Ultron\"")

        if (phrase == null) {
            if (transcriber.isLoaded) {
                // Miss silencioso: gatilho sem fala útil, sem notificação nem alteração de HUD.
                Stats.recognizerMisses++
                return null
            }
            // Vosk quebrado: entrega só o hotword e o Dart cai na voz manual.
            return "ultron"
        }
        Stats.detections++
        Stats.voskCommands++
        Stats.lastPhrase = phrase
        return phrase
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
        releaseWakeLockSafely()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
