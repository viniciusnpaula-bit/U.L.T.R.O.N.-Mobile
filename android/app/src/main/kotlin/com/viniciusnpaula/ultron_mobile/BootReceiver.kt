package com.viniciusnpaula.ultron_mobile

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Religa o sentinela de voz após reiniciar o aparelho (somente se o usuário ativou o opt-in
 * e o sentinela estava ligado).
 *
 * Android 11+ não entrega áudio a um serviço de microfone iniciado em segundo plano (e o
 * Android 14 o proíbe a partir de BOOT_COMPLETED), então nesses casos o receiver NÃO
 * força o serviço: publica uma notificação de um toque que abre o app e reativa a escuta
 * com o app em primeiro plano. Em Android 10 ou inferior o serviço é iniciado direto.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        const val EXTRA_REARM_SENTINEL = "ultron_rearm_sentinel"
        private const val BOOT_CHANNEL_ID = "ultron_boot_rearm_channel"
        private const val BOOT_NOTIFICATION_ID = 2051
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        val prefs = context.getSharedPreferences(UltronAudioService.PREFS_NAME, Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean(UltronAudioService.PREF_ENABLED, false)
        val autostart = prefs.getBoolean(UltronAudioService.PREF_BOOT_AUTOSTART, false)
        if (!enabled || !autostart) return

        val hasMic = ContextCompat.checkSelfPermission(
            context, Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        if (!hasMic) return

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            try {
                ContextCompat.startForegroundService(
                    context, Intent(context, UltronAudioService::class.java)
                )
                return
            } catch (e: Exception) {
                wakeLogW("falha ao iniciar foreground service em boot: ${e.javaClass.simpleName}")
                // cai para a notificação de reativação
            }
        }
        postRearmNotification(context)
    }

    private fun postRearmNotification(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    BOOT_CHANNEL_ID,
                    "U.L.T.R.O.N. Reativação após reinício",
                    NotificationManager.IMPORTANCE_DEFAULT
                )
            )
        }
        val open = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_REARM_SENTINEL, true)
        }
        val pending = PendingIntent.getActivity(
            context, 20, open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(context, BOOT_CHANNEL_ID)
            .setContentTitle("U.L.T.R.O.N. reiniciado")
            .setContentText("Toque para reativar a escuta por voz")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        try {
            nm.notify(BOOT_NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS negada: nada a fazer.
        }
    }
}
