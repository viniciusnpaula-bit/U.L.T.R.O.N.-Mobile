package com.viniciusnpaula.ultron_mobile

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.ArrayDeque

class UltronNotificationListenerService : NotificationListenerService() {
    companion object {
        private const val MAX_RECENT = 20
        private val lock = Any()
        private val recent = ArrayDeque<Map<String, Any?>>()

        fun snapshotRecent(): List<Map<String, Any?>> {
            synchronized(lock) {
                return recent.toList()
            }
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null || sbn.isOngoing) return
        val extras = sbn.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        if (title.isEmpty() && text.isEmpty()) return

        val item = mapOf<String, Any?>(
            "packageName" to sbn.packageName.orEmpty(),
            "title" to title,
            "text" to text,
            "postedAtMs" to sbn.postTime,
        )

        synchronized(lock) {
            if (recent.size >= MAX_RECENT) {
                recent.removeFirst()
            }
            recent.addLast(item)
        }
    }
}
