package com.viniciusnpaula.ultron_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * BroadcastReceiver acionado pelo AlarmManager quando um fluxo agendado pelo
 * WorkflowSchedulerService atinge seu horário de execução.
 *
 * Se a MainActivity estiver ativa em memória, entrega o evento imediatamente via
 * MethodChannel para execução sob avaliação do AuthGate/ActionGate; caso contrário,
 * enfileira o fluxo pendente e publica notificação tática.
 */
class WorkflowAlarmReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_TRIGGER_WORKFLOW = "com.viniciusnpaula.ultron_mobile.TRIGGER_WORKFLOW"
        const val EXTRA_WORKFLOW_ID = "workflow_id"
        const val EXTRA_WORKFLOW_NAME = "workflow_name"
        private const val CHANNEL_ID = "ultron_workflows_channel"
        private const val NOTIFICATION_BASE_ID = 46000
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent == null) return
        val flowId = intent.getIntExtra(EXTRA_WORKFLOW_ID, 0)
        if (flowId <= 0) return
        val flowName = intent.getStringExtra(EXTRA_WORKFLOW_NAME)?.trim().orEmpty()
            .ifEmpty { "Fluxo #$flowId" }

        MainActivity.notifyWorkflowTriggered(flowId)

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "U.L.T.R.O.N. Fluxos Agendados",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Disparos de fluxos dinâmicos agendados no U.L.T.R.O.N."
                },
            )
        }

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            context,
            NOTIFICATION_BASE_ID + flowId,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_manage)
            .setContentTitle("⚙️ Fluxo Agendado U.L.T.R.O.N.")
            .setContentText("Fluxo \"$flowName\" acionado (sujeito ao AuthGate).")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()

        try {
            nm.notify(NOTIFICATION_BASE_ID + flowId, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS negada.
        }
    }
}
