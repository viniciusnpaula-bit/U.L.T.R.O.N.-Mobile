package com.viniciusnpaula.ultron_mobile

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Trata ações rápidas das notificações urgentes da Triagem Inteligente:
 * - Ouvir a mensagem em voz alta fora do app (via UltronTtsHelper)
 * - Silenciar o remetente para evitar novos alertas deste contato/grupo
 */
class NotificationTriageActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_SPEAK_URGENT = "com.viniciusnpaula.ultron_mobile.TRIAGE_SPEAK_URGENT"
        const val ACTION_MUTE_SENDER = "com.viniciusnpaula.ultron_mobile.TRIAGE_MUTE_SENDER"
        const val EXTRA_SPEAK_TEXT = "speak_text"
        const val EXTRA_SENDER = "sender"
        const val EXTRA_NOTIFICATION_ID = "notification_id"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        val notifId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)

        when (action) {
            ACTION_SPEAK_URGENT -> {
                val text = intent.getStringExtra(EXTRA_SPEAK_TEXT)?.trim().orEmpty()
                if (text.isNotEmpty()) {
                    UltronTtsHelper.speak(context, text)
                }
            }
            ACTION_MUTE_SENDER -> {
                val sender = intent.getStringExtra(EXTRA_SENDER)?.trim().orEmpty()
                if (sender.isNotEmpty()) {
                    UltronNotificationService.addMutedSender(context, sender)
                    MainActivity.notifyTriageConfigChanged()
                }
                if (notifId > 0) {
                    val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                    nm?.cancel(notifId)
                }
            }
        }
    }
}
