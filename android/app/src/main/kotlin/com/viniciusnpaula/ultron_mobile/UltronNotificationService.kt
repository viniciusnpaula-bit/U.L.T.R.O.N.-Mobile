package com.viniciusnpaula.ultron_mobile

import android.app.Notification
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CopyOnWriteArrayList

data class CapturedMessage(
    val id: String,
    val packageName: String,
    val appLabel: String,
    val sender: String,
    val text: String,
    val timestampMs: Long,
    val timeFormatted: String,
    val canReplyInline: Boolean,
    val replyAction: Notification.Action?
) {
    fun toMap(): Map<String, Any> = mapOf(
        "id" to id,
        "packageName" to packageName,
        "appLabel" to appLabel,
        "sender" to sender,
        "text" to text,
        "timestampMs" to timestampMs,
        "timeFormatted" to timeFormatted,
        "canReplyInline" to canReplyInline
    )
}

class UltronNotificationService : NotificationListenerService() {
    companion object {
        private const val MAX_MESSAGES = 40
        private val messages = CopyOnWriteArrayList<CapturedMessage>()

        private val knownAppLabels = mapOf(
            "com.whatsapp" to "WhatsApp",
            "com.whatsapp.w4b" to "WhatsApp Business",
            "org.telegram.messenger" to "Telegram",
            "org.telegram.messenger.web" to "Telegram",
            "com.instagram.android" to "Instagram",
            "com.google.android.apps.messaging" to "Mensagens (SMS)",
            "com.samsung.android.messaging" to "Mensagens (SMS)",
            "com.google.android.gm" to "Gmail",
            "com.discord" to "Discord",
            "com.facebook.orca" to "Messenger"
        )

        fun getRecentMessages(limit: Int = 20): List<Map<String, Any>> {
            return messages.take(limit).map { it.toMap() }
        }

        fun clearMessages() {
            messages.clear()
        }

        fun replyToMessage(
            context: Context,
            targetQuery: String?,
            replyText: String
        ): String {
            val cleanReply = replyText.trim()
            if (cleanReply.isEmpty()) {
                throw IllegalArgumentException("O texto da resposta não pode estar vazio.")
            }

            val query = targetQuery?.trim()?.lowercase() ?: ""
            val candidate = if (query.isEmpty() || query == "ultimo" || query == "último" || query == "last") {
                messages.firstOrNull { it.canReplyInline && it.replyAction != null }
            } else {
                messages.firstOrNull {
                    it.canReplyInline &&
                        it.replyAction != null &&
                        (it.sender.lowercase().contains(query) ||
                            it.appLabel.lowercase().contains(query) ||
                            it.id == targetQuery)
                } ?: messages.firstOrNull { it.canReplyInline && it.replyAction != null }
            }

            if (candidate == null || candidate.replyAction == null) {
                throw IllegalStateException(
                    "Nenhuma notificação recente com suporte a resposta rápida encontrada."
                )
            }

            val action = candidate.replyAction
            val remoteInputs = action.remoteInputs
            if (remoteInputs.isNullOrEmpty()) {
                throw IllegalStateException("Esta notificação não aceita resposta direta.")
            }

            val fillInIntent = Intent().addFlags(Intent.FLAG_RECEIVER_FOREGROUND)
            val resultsBundle = Bundle()
            for (remoteInput in remoteInputs) {
                resultsBundle.putCharSequence(remoteInput.resultKey, cleanReply)
            }
            RemoteInput.addResultsToIntent(remoteInputs, fillInIntent, resultsBundle)

            try {
                action.actionIntent.send(context, 0, fillInIntent)
                return "Resposta enviada em segundo plano para ${candidate.sender} (${candidate.appLabel}): \"$cleanReply\""
            } catch (e: PendingIntent.CanceledException) {
                throw IllegalStateException("A notificação de ${candidate.sender} já expirou no Android.")
            }
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val pkg = sbn.packageName ?: return
        // Ignore our own app or ongoing system bars
        if (pkg == packageName || sbn.isOngoing) return

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: return

        val rawTitle = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)
            ?: extras.getCharSequence(Notification.EXTRA_TITLE)
        val rawText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT)

        val sender = rawTitle?.toString()?.trim() ?: ""
        val text = rawText?.toString()?.trim() ?: ""
        if (sender.isEmpty() && text.isEmpty()) return
        // Skip generic "Checking for new messages..." or summary lines
        if (text.lowercase().contains("verificando novas mensagens") ||
            text.lowercase().contains("checking for new messages")
        ) {
            return
        }

        val replyAction = findReplyAction(notification)
        val appLabel = knownAppLabels[pkg] ?: resolveAppLabel(pkg)
        val isMessagingPkg = knownAppLabels.containsKey(pkg) || replyAction != null
        if (!isMessagingPkg) return

        val now = sbn.postTime.takeIf { it > 0 } ?: System.currentTimeMillis()
        val timeFmt = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(now))
        val msgId = "${pkg}_${sbn.id}_$now"

        // Deduplicate identical consecutive notifications from the same sender
        val existingIdx = messages.indexOfFirst {
            it.packageName == pkg && it.sender == sender && it.text == text
        }
        if (existingIdx >= 0) {
            messages.removeAt(existingIdx)
        }

        val captured = CapturedMessage(
            id = msgId,
            packageName = pkg,
            appLabel = appLabel,
            sender = if (sender.isEmpty()) appLabel else sender,
            text = text,
            timestampMs = now,
            timeFormatted = timeFmt,
            canReplyInline = replyAction != null,
            replyAction = replyAction
        )

        messages.add(0, captured)
        while (messages.size > MAX_MESSAGES) {
            messages.removeAt(messages.size - 1)
        }
    }

    private fun findReplyAction(notification: Notification): Notification.Action? {
        val actions = notification.actions ?: return null
        for (action in actions) {
            val remoteInputs = action.remoteInputs
            if (!remoteInputs.isNullOrEmpty()) {
                for (ri in remoteInputs) {
                    if (ri.allowFreeFormInput) {
                        return action
                    }
                }
            }
        }
        return null
    }

    private fun resolveAppLabel(pkg: String): String {
        return try {
            val pm = applicationContext.packageManager
            val info = pm.getApplicationInfo(pkg, 0)
            pm.getApplicationLabel(info).toString()
        } catch (_: Exception) {
            pkg.substringAfterLast('.')
        }
    }
}
