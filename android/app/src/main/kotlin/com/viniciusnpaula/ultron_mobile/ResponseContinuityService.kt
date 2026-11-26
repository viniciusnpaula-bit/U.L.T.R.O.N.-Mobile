package com.viniciusnpaula.ultron_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Mantém respostas longas da IA e a síntese de voz (TTS) ativas em segundo plano
 * quando o usuário sai do app ou bloqueia a tela, oferecendo controle rápido
 * "Parar fala" diretamente na notificação.
 */
class ResponseContinuityService : Service() {

    companion object {
        private const val CHANNEL_ID = "ultron_response_continuity_channel"
        private const val READY_CHANNEL_ID = "ultron_response_ready_channel"
        private const val FOREGROUND_ID = 2071
        private const val READY_NOTIFICATION_ID = 2072

        const val ACTION_UPDATE = "com.viniciusnpaula.ultron_mobile.RESPONSE_CONTINUITY_UPDATE"
        const val ACTION_STOP = "com.viniciusnpaula.ultron_mobile.RESPONSE_CONTINUITY_STOP"
        const val ACTION_STOP_SPEAKING = "com.viniciusnpaula.ultron_mobile.RESPONSE_STOP_SPEAKING"

        const val EXTRA_PHASE = "phase"
        const val EXTRA_PREVIEW = "preview"

        @Volatile
        var isActive: Boolean = false
            private set

        fun startOrUpdate(context: Context, phase: String, preview: String = "") {
            val intent = Intent(context, ResponseContinuityService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_PHASE, phase)
                putExtra(EXTRA_PREVIEW, preview.take(180))
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ContextCompat.startForegroundService(context, intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Throwable) {
                // Em Android 12+, iniciar FGS a partir de segundo plano estrito pode ser recusado;
                // falha segura sem derrubar o processo.
            }
        }

        fun stop(context: Context) {
            if (!isActive) return
            val intent = Intent(context, ResponseContinuityService::class.java).apply {
                action = ACTION_STOP
            }
            try {
                context.startService(intent)
            } catch (_: Throwable) {
                try {
                    context.stopService(Intent(context, ResponseContinuityService::class.java))
                } catch (_: Throwable) {
                }
            }
        }

        fun postBackgroundAnswerReady(context: Context, title: String, body: String) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                ?: return
            ensureChannels(nm)

            val openIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val openPending = PendingIntent.getActivity(
                context,
                READY_NOTIFICATION_ID,
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val cleanBody = body.trim().take(700)
            val notification = NotificationCompat.Builder(context, READY_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title.ifBlank { "U.L.T.R.O.N. concluiu a resposta" })
                .setContentText(cleanBody.take(120))
                .setStyle(NotificationCompat.BigTextStyle().bigText(cleanBody))
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .setContentIntent(openPending)
                .build()

            try {
                nm.notify(READY_NOTIFICATION_ID, notification)
            } catch (_: SecurityException) {
            }
        }

        private fun ensureChannels(nm: NotificationManager) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                    val ch = NotificationChannel(
                        CHANNEL_ID,
                        "Resposta e voz em segundo plano",
                        NotificationManager.IMPORTANCE_LOW,
                    ).apply {
                        description = "Mantém respostas longas e fala ativas fora do aplicativo."
                        setShowBadge(false)
                    }
                    nm.createNotificationChannel(ch)
                }
                if (nm.getNotificationChannel(READY_CHANNEL_ID) == null) {
                    val ch = NotificationChannel(
                        READY_CHANNEL_ID,
                        "Respostas concluídas em segundo plano",
                        NotificationManager.IMPORTANCE_DEFAULT,
                    ).apply {
                        description = "Exibe respostas finalizadas enquanto o aplicativo estava em segundo plano."
                    }
                    nm.createNotificationChannel(ch)
                }
            }
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        val pm = getSystemService(POWER_SERVICE) as? PowerManager
        wakeLock = pm?.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "Ultron::ResponseContinuityLock",
        )?.apply {
            setReferenceCounted(false)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                releaseAndStop()
                return START_NOT_STICKY
            }
            ACTION_STOP_SPEAKING -> {
                UltronTtsHelper.stopAll()
                MainActivity.notifyStopSpeakingRequested()
                releaseAndStop()
                return START_NOT_STICKY
            }
        }

        val phase = intent?.getStringExtra(EXTRA_PHASE) ?: "speaking"
        val preview = intent?.getStringExtra(EXTRA_PREVIEW) ?: ""

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        if (nm != null) ensureChannels(nm)

        val notification = buildNotification(phase, preview)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    FOREGROUND_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else {
                startForeground(FOREGROUND_ID, notification)
            }
            isActive = true
            DynamicIslandService.updateState(
                modeId = if (phase == "thinking") "processing" else "speaking",
                detail = preview,
            )
            try {
                // Limite de segurança de 5 minutos por resposta longa
                wakeLock?.acquire(5 * 60 * 1000L)
            } catch (_: Throwable) {
            }
        } catch (_: Throwable) {
            releaseAndStop()
        }
        return START_NOT_STICKY
    }

    private fun buildNotification(phase: String, preview: String): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPending = PendingIntent.getActivity(
            this,
            FOREGROUND_ID,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val stopSpeakIntent = Intent(this, ResponseContinuityService::class.java).apply {
            action = ACTION_STOP_SPEAKING
        }
        val stopSpeakPending = PendingIntent.getService(
            this,
            FOREGROUND_ID + 1,
            stopSpeakIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val title = when (phase) {
            "thinking" -> "U.L.T.R.O.N. processando resposta..."
            else -> "U.L.T.R.O.N. falando em segundo plano"
        }
        val text = if (preview.isNotBlank()) {
            preview
        } else if (phase == "thinking") {
            "A resposta continuará disponível mesmo fora do app."
        } else {
            "Toque para voltar à conversa ou parar a fala."
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openPending)
            .addAction(
                android.R.drawable.ic_media_pause,
                "Parar fala",
                stopSpeakPending,
            )
            .build()
    }

    private fun releaseAndStop() {
        isActive = false
        if (DynamicIslandService.currentMode == IslandMode.PROCESSING ||
            DynamicIslandService.currentMode == IslandMode.SPEAKING
        ) {
            DynamicIslandService.updateState("idle")
        }
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Throwable) {
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Throwable) {
        }
        stopSelf()
    }

    override fun onDestroy() {
        isActive = false
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Throwable) {
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
