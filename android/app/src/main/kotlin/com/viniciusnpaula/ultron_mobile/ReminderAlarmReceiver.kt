package com.viniciusnpaula.ultron_mobile

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.Build
import androidx.core.app.NotificationCompat
import kotlin.math.max

/**
 * BroadcastReceiver acionado pelo AlarmManager quando um lembrete persistente
 * agendado pelo ReminderService atinge o horário programado.
 */
class ReminderAlarmReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_TRIGGER_REMINDER = "com.viniciusnpaula.ultron_mobile.TRIGGER_REMINDER"
        const val EXTRA_REMINDER_ID = "reminder_id"
        const val EXTRA_REMINDER_TITLE = "reminder_title"
        private const val CHANNEL_ID = "ultron_reminders_channel"
        private const val NOTIFICATION_BASE_ID = 42000
        private const val ALARM_REQUEST_BASE_ID = 50_000
        private const val REMINDERS_DB_NAME = "ultron_reminders.db"

        fun scheduleAlarm(
            context: Context,
            reminderId: Int,
            title: String,
            triggerAtMs: Long,
        ): Boolean {
            return try {
                val alarmManager =
                    context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return false
                val intent = Intent(context, ReminderAlarmReceiver::class.java).apply {
                    action = ACTION_TRIGGER_REMINDER
                    putExtra(EXTRA_REMINDER_ID, reminderId)
                    putExtra(EXTRA_REMINDER_TITLE, title)
                }
                val pending = PendingIntent.getBroadcast(
                    context,
                    ALARM_REQUEST_BASE_ID + reminderId,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                val safeTrigger = max(triggerAtMs, System.currentTimeMillis() + 1_000L)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, safeTrigger, pending)
                } else {
                    alarmManager.set(AlarmManager.RTC_WAKEUP, safeTrigger, pending)
                }
                true
            } catch (_: Exception) {
                false
            }
        }

        fun cancelAlarm(context: Context, reminderId: Int): Boolean {
            return try {
                val alarmManager =
                    context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return false
                val intent = Intent(context, ReminderAlarmReceiver::class.java).apply {
                    action = ACTION_TRIGGER_REMINDER
                }
                val pending = PendingIntent.getBroadcast(
                    context,
                    ALARM_REQUEST_BASE_ID + reminderId,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                alarmManager.cancel(pending)
                pending.cancel()
                true
            } catch (_: Exception) {
                false
            }
        }

        /**
         * Reagenda no AlarmManager todos os lembretes PENDING futuros persistidos no SQLite
         * (`ultron_reminders.db`), garantindo sobrevivência a reboot e atualização de APK.
         */
        fun reschedulePersistedReminders(context: Context): Int {
            val dbFile = context.getDatabasePath(REMINDERS_DB_NAME)
            if (dbFile == null || !dbFile.exists()) return 0
            var rescheduled = 0
            var db: SQLiteDatabase? = null
            try {
                db = SQLiteDatabase.openDatabase(
                    dbFile.path,
                    null,
                    SQLiteDatabase.OPEN_READONLY,
                )
                val nowMs = System.currentTimeMillis()
                db.rawQuery(
                    "SELECT id, title, scheduled_ms FROM reminders WHERE status = 'PENDING' AND scheduled_ms > ?",
                    arrayOf(nowMs.toString()),
                ).use { cursor ->
                    while (cursor.moveToNext()) {
                        val id = cursor.getInt(0)
                        val title = cursor.getString(1)?.trim().orEmpty()
                            .ifEmpty { "Lembrete Tático U.L.T.R.O.N." }
                        val triggerMs = cursor.getLong(2)
                        if (scheduleAlarm(context, id, title, triggerMs)) {
                            rescheduled++
                        }
                    }
                }
            } catch (_: Exception) {
                // Banco ainda não criado ou schema incompatível: ignora sem falhar no boot.
            } finally {
                try {
                    db?.close()
                } catch (_: Exception) {}
            }
            return rescheduled
        }
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent == null) return
        val reminderId = intent.getIntExtra(EXTRA_REMINDER_ID, 1)
        val title = intent.getStringExtra(EXTRA_REMINDER_TITLE)?.trim().orEmpty()
            .ifEmpty { "Lembrete Tático U.L.T.R.O.N." }

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "U.L.T.R.O.N. Lembretes",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Notificações agendadas de lembretes do U.L.T.R.O.N."
                    enableVibration(true)
                },
            )
        }

        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentPending = PendingIntent.getActivity(
            context,
            NOTIFICATION_BASE_ID + reminderId,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle("⏰ Lembrete U.L.T.R.O.N. #$reminderId")
            .setContentText(title)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(contentPending)
            .build()

        try {
            nm.notify(NOTIFICATION_BASE_ID + reminderId, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS negada pelo usuário.
        }
    }
}
