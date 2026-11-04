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
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.sqrt

/**
 * UltronAudioService (Eco-VAD v2 — Consumo Ultra-Baixo):
 * 1. Adaptive Exponential Duty-Cycling (82% a 93.3% Sleep Ratio):
 *    - Amostra janelas curtas de 100ms em 8kHz (banda de voz humana).
 *    - Em ambiente ativo (< 20s de silêncio): dorme 450ms entre janelas (~82% ADC desligado).
 *    - Em silêncio moderado (20s a 120s): dorme 900ms (~90% ADC desligado).
 *    - Em silêncio profundo (> 120s, ex.: mesa/madrugada): dorme 1400ms (~93.3% ADC desligado).
 *    - Retorna instantaneamente ao modo rápido (450ms) ao menor sinal acústico.
 * 2. Zero WakeLock Infinito:
 *    - Nenhum PARTIAL_WAKE_LOCK fica retido em repouso. Só adquire WakeLock por 8 segundos
 *      no exato instante em que a voz humana dispara o gatilho.
 * 3. Pausa Inteligente em Chamadas, Flip-to-Shush (Tela p/ Baixo) e Bateria Crítica (< 15%).
 */
class UltronAudioService : Service() {

    companion object {
        private const val CHANNEL_ID = "ultron_eco_voice_channel"
        private const val NOTIFICATION_ID = 2049
        const val ACTION_STOP = "com.viniciusnpaula.ultron_mobile.STOP_AUDIO_SERVICE"
        const val ACTION_SAY_TIME = "com.viniciusnpaula.ultron_mobile.SAY_TIME_OFFLINE"

        private const val SAMPLE_RATE_HZ = 8000
        private const val WINDOW_MS = 100
        private const val SLEEP_ACTIVE_MS = 450L
        private const val SLEEP_QUIET_MS = 900L
        private const val SLEEP_DEEP_IDLE_MS = 1400L
        private const val SLEEP_PAUSED_STATE_MS = 5000L
        private const val SLEEP_LOW_BATTERY_MS = 10000L

        private const val AMBIENT_ACTIVITY_RMS = 850.0
        private const val VAD_RMS_THRESHOLD = 1950.0
        private const val COOLDOWN_AFTER_TRIGGER_MS = 4500L

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var lastTriggerTimestamp: String = "Nenhum"
            private set
    }

    private val workerActive = AtomicBoolean(false)
    private var vadThread: Thread? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Ultron::EcoVadWakeLock").apply {
            setReferenceCounted(false)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_SAY_TIME -> {
                UltronTtsHelper.answerQuickOfflineQuery(this, "que horas são")
                return START_STICKY
            }
        }

        val hasMicPerm = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasMicPerm) {
            stopSelf()
            return START_NOT_STICKY
        }

        val notification = buildNotification("Eco-VAD Adaptativo ativo (82%–93% Sleep)")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        isRunning = true
        startEcoVadLoop()
        return START_STICKY
    }

    private fun startEcoVadLoop() {
        if (!workerActive.compareAndSet(false, true)) return

        vadThread = Thread({
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_LOWEST)
            val minBuf = AudioRecord.getMinBufferSize(
                SAMPLE_RATE_HZ,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            ).coerceAtLeast(SAMPLE_RATE_HZ / 4)

            val windowSamples = (SAMPLE_RATE_HZ * WINDOW_MS) / 1000
            val pcmBuffer = ShortArray(windowSamples)
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            var recorder: AudioRecord? = null

            try {
                recorder = AudioRecord(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION,
                    SAMPLE_RATE_HZ,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    minBuf
                )

                var consecutiveVoiceFrames = 0
                var lastSoundDetectedMs = System.currentTimeMillis()

                while (workerActive.get()) {
                    // 1. Economia Profunda em Bateria Crítica (< 15% sem carregador)
                    if (isBatteryCriticalUnplugged()) {
                        Thread.sleep(SLEEP_LOW_BATTERY_MS)
                        continue
                    }

                    // 2. Pausa se estiver em ligação telefônica/VoIP ou Flip-to-Shush (tela p/ baixo)
                    val inCall = audioManager != null &&
                        audioManager.mode != AudioManager.MODE_NORMAL
                    if (inCall || MainActivity.isFaceDownGlobal) {
                        Thread.sleep(SLEEP_PAUSED_STATE_MS)
                        continue
                    }

                    // 3. Captura Burst de apenas 100ms
                    if (recorder.state == AudioRecord.STATE_INITIALIZED) {
                        recorder.startRecording()
                        val readCount = recorder.read(pcmBuffer, 0, windowSamples)
                        recorder.stop()

                        if (readCount > 0) {
                            val rms = computeRms(pcmBuffer, readCount)
                            if (rms >= AMBIENT_ACTIVITY_RMS) {
                                lastSoundDetectedMs = System.currentTimeMillis()
                            }
                            if (rms >= VAD_RMS_THRESHOLD) {
                                consecutiveVoiceFrames++
                                if (consecutiveVoiceFrames >= 2) {
                                    consecutiveVoiceFrames = 0
                                    onVoiceWakeTriggered()
                                    Thread.sleep(COOLDOWN_AFTER_TRIGGER_MS)
                                    continue
                                }
                            } else {
                                consecutiveVoiceFrames = 0
                            }
                        }
                    }

                    // 4. Adaptive Exponential Sleep Backoff (450ms -> 900ms -> 1400ms)
                    val silenceDurationMs = System.currentTimeMillis() - lastSoundDetectedMs
                    val sleepMs = when {
                        silenceDurationMs > 120_000L -> SLEEP_DEEP_IDLE_MS
                        silenceDurationMs > 20_000L -> SLEEP_QUIET_MS
                        else -> SLEEP_ACTIVE_MS
                    }
                    Thread.sleep(sleepMs)
                }
            } catch (_: InterruptedException) {
            } catch (_: Exception) {
            } finally {
                try {
                    recorder?.stop()
                } catch (_: Exception) {
                }
                try {
                    recorder?.release()
                } catch (_: Exception) {
                }
                releaseWakeLockSafely()
                isRunning = false
                workerActive.set(false)
            }
        }, "UltronEcoVadThread").also { it.start() }
    }

    private fun computeRms(buffer: ShortArray, count: Int): Double {
        var sumSq = 0L
        for (i in 0 until count) {
            val s = buffer[i].toLong()
            sumSq += s * s
        }
        return sqrt(sumSq.toDouble() / count.coerceAtLeast(1))
    }

    private fun onVoiceWakeTriggered() {
        // Adquire WakeLock apenas por 8 segundos (nunca infinito!)
        wakeLock?.acquire(8_000L)
        val nowStr = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())
        lastTriggerTimestamp = nowStr

        UltronTtsHelper.playFishVoiceAsset(applicationContext)
        updateNotification("Voz detectada às $nowStr • Toque para falar")
    }

    private fun isBatteryCriticalUnplugged(): Boolean {
        return try {
            val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
            val level = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 50
            val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL
            level in 1..15 && !charging
        } catch (_: Exception) {
            false
        }
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

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("U.L.T.R.O.N. Sentinela Eco-VAD")
            .setContentText(subtitle)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingOpen)
            .addAction(android.R.drawable.ic_lock_idle_alarm, "Que horas são?", pendingTime)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Parar Escuta", pendingStop)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "U.L.T.R.O.N. Sentinela Eco-VAD",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Escuta inteligente em Duty-Cycle Adaptativo (82% a 93% Sleep)"
                setShowBadge(false)
            }
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun releaseWakeLockSafely() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        workerActive.set(false)
        isRunning = false
        vadThread?.interrupt()
        releaseWakeLockSafely()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
