package com.viniciusnpaula.ultron_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.text.Normalizer
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
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
        private const val TRIAGE_PREFS = "ultron_smart_triage_prefs"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_SAVE_OBSIDIAN = "save_to_obsidian"
        private const val KEY_SPEAK_URGENT = "speak_urgent_alerts"
        private const val KEY_RESPECT_NIGHT = "respect_night_focus"
        private const val KEY_THRESHOLD = "urgency_threshold"
        private const val KEY_VIPS = "vip_contacts"
        private const val KEY_KEYWORDS = "custom_keywords"
        private const val KEY_MUTED = "muted_senders"
        private const val KEY_APPS = "monitored_apps"
        private const val KEY_PENDING_URGENT = "pending_urgent_json"
        private const val KEY_TRIAGED_COUNT = "triaged_count"

        private const val URGENT_CHANNEL_ID = "ultron_urgent_triage_channel"
        private const val DEDUP_WINDOW_MS = 5 * 60 * 1000L
        private const val BURST_WINDOW_MS = 60 * 1000L

        private val messages = CopyOnWriteArrayList<CapturedMessage>()
        private val recentDedupHashes = ConcurrentHashMap<String, Long>()
        private val senderBursts = ConcurrentHashMap<String, MutableList<Long>>()
        private var urgentNotifSeq = 3100

        private val knownAppLabels = mapOf(
            "com.whatsapp" to "WhatsApp",
            "com.whatsapp.w4b" to "WhatsApp Business",
            "org.telegram.messenger" to "Telegram",
            "org.telegram.messenger.web" to "Telegram",
            "com.instagram.android" to "Instagram",
            "com.google.android.apps.messaging" to "Mensagens (SMS)",
            "com.samsung.android.messaging" to "Mensagens (SMS)",
            "com.google.android.gm" to "Gmail",
            "com.microsoft.office.outlook" to "Outlook",
            "com.samsung.android.email.provider" to "E-mail",
            "com.discord" to "Discord",
            "com.facebook.orca" to "Messenger"
        )

        private val criticalKeywords = listOf(
            "emergencia", "socorro", "acidente", "hospital", "urgente", "urgencia",
            "imediato", "imediatamente", "me liga", "liga pra mim", "liga agora",
            "to na porta", "estou na porta", "cheguei agora", "vazamento",
            "servidor fora", "sistema caiu", "falha critica", "parou tudo"
        )

        private val timeSensitiveKeywords = listOf(
            "hoje", "agora", "prazo", "vence", "atrasado", "reuniao",
            "cancelou", "confirmar", "pix", "boleto", "entrega", "importante"
        )

        private val noisePatterns = listOf(
            "cupom", "desconto", "oferta", "black friday", "frete gratis",
            "newsletter", "promocao", "promocoes", "cashback",
            "codigo de verificacao", "codigo de seguranca", "nao compartilhe",
            "seu codigo e", "verification code", "one-time password"
        )

        fun getRecentMessages(limit: Int = 20): List<Map<String, Any>> {
            return messages.take(limit).map { it.toMap() }
        }

        fun clearMessages() {
            messages.clear()
        }

        fun saveTriageConfig(context: Context, config: Map<String, Any?>) {
            val prefs = context.getSharedPreferences(TRIAGE_PREFS, Context.MODE_PRIVATE)
            prefs.edit().apply {
                if (config.containsKey("enabled")) {
                    putBoolean(KEY_ENABLED, config["enabled"] as? Boolean ?: false)
                }
                if (config.containsKey("saveToObsidian")) {
                    putBoolean(KEY_SAVE_OBSIDIAN, config["saveToObsidian"] as? Boolean ?: true)
                }
                if (config.containsKey("speakUrgentAlerts")) {
                    putBoolean(KEY_SPEAK_URGENT, config["speakUrgentAlerts"] as? Boolean ?: false)
                }
                if (config.containsKey("respectNightFocus")) {
                    putBoolean(KEY_RESPECT_NIGHT, config["respectNightFocus"] as? Boolean ?: true)
                }
                if (config.containsKey("urgencyThreshold")) {
                    val th = (config["urgencyThreshold"] as? Number)?.toFloat() ?: 0.70f
                    putFloat(KEY_THRESHOLD, th.coerceIn(0.35f, 0.95f))
                }
                if (config.containsKey("vipContacts")) {
                    putString(KEY_VIPS, encodeStringList(config["vipContacts"]))
                }
                if (config.containsKey("customKeywords")) {
                    putString(KEY_KEYWORDS, encodeStringList(config["customKeywords"]))
                }
                if (config.containsKey("mutedSenders")) {
                    putString(KEY_MUTED, encodeStringList(config["mutedSenders"]))
                }
                if (config.containsKey("monitoredApps")) {
                    putString(KEY_APPS, encodeStringList(config["monitoredApps"]))
                }
            }.apply()
        }

        fun loadTriageConfig(context: Context): Map<String, Any> {
            val prefs = context.getSharedPreferences(TRIAGE_PREFS, Context.MODE_PRIVATE)
            return mapOf(
                "enabled" to prefs.getBoolean(KEY_ENABLED, false),
                "saveToObsidian" to prefs.getBoolean(KEY_SAVE_OBSIDIAN, true),
                "speakUrgentAlerts" to prefs.getBoolean(KEY_SPEAK_URGENT, false),
                "respectNightFocus" to prefs.getBoolean(KEY_RESPECT_NIGHT, true),
                "urgencyThreshold" to prefs.getFloat(KEY_THRESHOLD, 0.70f).toDouble(),
                "vipContacts" to decodeStringList(prefs.getString(KEY_VIPS, null)),
                "customKeywords" to decodeStringList(prefs.getString(KEY_KEYWORDS, null)),
                "mutedSenders" to decodeStringList(prefs.getString(KEY_MUTED, null)),
                "monitoredApps" to decodeStringList(
                    prefs.getString(KEY_APPS, null),
                    default = listOf("whatsapp", "telegram", "email"),
                ),
                "triagedCount" to prefs.getInt(KEY_TRIAGED_COUNT, 0),
            )
        }

        fun addMutedSender(context: Context, sender: String) {
            val clean = sender.trim()
            if (clean.isEmpty()) return
            val prefs = context.getSharedPreferences(TRIAGE_PREFS, Context.MODE_PRIVATE)
            val existing = decodeStringList(prefs.getString(KEY_MUTED, null)).toMutableList()
            if (existing.none { it.equals(clean, ignoreCase = true) }) {
                existing.add(clean)
                prefs.edit().putString(KEY_MUTED, encodeStringList(existing)).apply()
            }
        }

        fun consumePendingUrgentEvents(context: Context): List<Map<String, Any>> {
            val prefs = context.getSharedPreferences(TRIAGE_PREFS, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY_PENDING_URGENT, null) ?: return emptyList()
            prefs.edit().remove(KEY_PENDING_URGENT).apply()
            return try {
                val arr = JSONArray(raw)
                val out = mutableListOf<Map<String, Any>>()
                for (i in 0 until arr.length()) {
                    val obj = arr.optJSONObject(i) ?: continue
                    out.add(
                        mapOf(
                            "appLabel" to obj.optString("appLabel", ""),
                            "packageName" to obj.optString("packageName", ""),
                            "sender" to obj.optString("sender", ""),
                            "text" to obj.optString("text", ""),
                            "score" to obj.optDouble("score", 0.0),
                            "reasons" to obj.optString("reasons", ""),
                            "timestampMs" to obj.optLong("timestampMs", System.currentTimeMillis()),
                            "saveToObsidian" to obj.optBoolean("saveToObsidian", true),
                        )
                    )
                }
                out
            } catch (_: Throwable) {
                emptyList()
            }
        }

        private fun enqueuePendingUrgent(context: Context, payload: JSONObject) {
            val prefs = context.getSharedPreferences(TRIAGE_PREFS, Context.MODE_PRIVATE)
            val arr = try {
                JSONArray(prefs.getString(KEY_PENDING_URGENT, "[]"))
            } catch (_: Throwable) {
                JSONArray()
            }
            arr.put(payload)
            val trimmed = JSONArray()
            val start = (arr.length() - 25).coerceAtLeast(0)
            for (i in start until arr.length()) {
                trimmed.put(arr.get(i))
            }
            val nextCount = prefs.getInt(KEY_TRIAGED_COUNT, 0) + 1
            prefs.edit()
                .putString(KEY_PENDING_URGENT, trimmed.toString())
                .putInt(KEY_TRIAGED_COUNT, nextCount)
                .apply()
        }

        private fun encodeStringList(raw: Any?): String {
            val arr = JSONArray()
            if (raw is List<*>) {
                for (item in raw) {
                    val clean = item?.toString()?.trim().orEmpty()
                    if (clean.isNotEmpty()) arr.put(clean)
                }
            }
            return arr.toString()
        }

        private fun decodeStringList(
            raw: String?,
            default: List<String> = emptyList(),
        ): List<String> {
            if (raw.isNullOrBlank()) return default
            return try {
                val arr = JSONArray(raw)
                val out = mutableListOf<String>()
                for (i in 0 until arr.length()) {
                    val v = arr.optString(i).trim()
                    if (v.isNotEmpty()) out.add(v)
                }
                out
            } catch (_: Throwable) {
                default
            }
        }

        private fun normalizeText(input: String): String {
            val decomposed = Normalizer.normalize(input.lowercase(Locale.ROOT), Normalizer.Form.NFD)
            return decomposed.replace(Regex("\\p{InCombiningDiacriticalMarks}+"), "").trim()
        }

        private fun sha256Hex(raw: String): String {
            val digest = MessageDigest.getInstance("SHA-256").digest(raw.toByteArray(Charsets.UTF_8))
            return digest.joinToString("") { "%02x".format(it) }
        }

        private fun resolveCategory(pkg: String, appLabel: String): String {
            val p = pkg.lowercase(Locale.ROOT)
            val l = appLabel.lowercase(Locale.ROOT)
            return when {
                p.contains("whatsapp") || l.contains("whatsapp") -> "whatsapp"
                p.contains("telegram") || l.contains("telegram") -> "telegram"
                p.contains(".gm") || p.contains("outlook") || p.contains("email") || p.contains("mail") || l.contains("mail") -> "email"
                p.contains("messaging") || l.contains("sms") -> "sms"
                else -> l
            }
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
        // Auto-exclusão obrigatória: nunca reprocessar notificações do próprio U.L.T.R.O.N.
        if (pkg == packageName) return

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: return

        // Atualiza mídia na Ilha Dinâmica (players de streaming, locais e controladores DJ).
        val isMediaNotification = extras.containsKey(Notification.EXTRA_MEDIA_SESSION) ||
            notification.category == Notification.CATEGORY_TRANSPORT ||
            pkg.contains("spotify") ||
            pkg.contains("youtube.music") ||
            pkg.contains("deezer") ||
            pkg.contains("soundcloud") ||
            pkg.contains("apple.android.music") ||
            pkg.contains("aspiro.tidal") ||
            pkg.contains("amazon.mp3") ||
            pkg.contains("maxmpz.audioplayer") ||
            pkg.contains("videolan.vlc") ||
            pkg.contains("algoriddim.djay") ||
            pkg.contains("edjing") ||
            pkg.contains("mixvibes") ||
            pkg.contains("rekordbox") ||
            pkg.contains("bandlab") ||
            pkg.contains("traktor")
        if (isMediaNotification) {
            val mediaTitle = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
            val mediaArtist = (
                extras.getCharSequence(Notification.EXTRA_TEXT)
                    ?: extras.getCharSequence(Notification.EXTRA_SUB_TEXT)
                )?.toString()?.trim().orEmpty()
            if (mediaTitle.isNotEmpty()) {
                val audio = getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
                val isPlaying = audio?.isMusicActive ?: sbn.isOngoing
                DynamicIslandService.updateMediaState(mediaTitle, mediaArtist, isPlaying)
            }
            if (sbn.isOngoing) return
        }

        if (sbn.isOngoing) return

        val rawTitle = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)
            ?: extras.getCharSequence(Notification.EXTRA_TITLE)
        val rawText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT)

        val sender = rawTitle?.toString()?.trim() ?: ""
        val text = rawText?.toString()?.trim() ?: ""
        if (sender.isEmpty() && text.isEmpty()) return
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

        val existingIdx = messages.indexOfFirst {
            it.packageName == pkg && it.sender == sender && it.text == text
        }
        if (existingIdx >= 0) {
            messages.removeAt(existingIdx)
        }

        val resolvedSender = if (sender.isEmpty()) appLabel else sender
        val captured = CapturedMessage(
            id = msgId,
            packageName = pkg,
            appLabel = appLabel,
            sender = resolvedSender,
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

        evaluateSmartTriage(captured)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        val notification = sbn?.notification ?: return
        val extras = notification.extras ?: return
        val pkg = sbn.packageName ?: ""
        val isMedia = extras.containsKey(Notification.EXTRA_MEDIA_SESSION) ||
            notification.category == Notification.CATEGORY_TRANSPORT ||
            pkg.contains("spotify") ||
            pkg.contains("youtube.music")
        if (isMedia) {
            DynamicIslandService.updateMediaState("", "", false)
        }
    }

    private fun evaluateSmartTriage(msg: CapturedMessage) {
        val prefs = getSharedPreferences(TRIAGE_PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_ENABLED, false)) return

        val monitored = decodeStringList(
            prefs.getString(KEY_APPS, null),
            default = listOf("whatsapp", "telegram", "email"),
        ).map { normalizeText(it) }
        val category = resolveCategory(msg.packageName, msg.appLabel)
        if (monitored.isNotEmpty() && monitored.none { it == category || it == "all" }) {
            return
        }

        val normSender = normalizeText(msg.sender)
        val normText = normalizeText(msg.text)

        // Ignorar remetentes silenciados
        val muted = decodeStringList(prefs.getString(KEY_MUTED, null)).map { normalizeText(it) }
        if (muted.any { it.isNotEmpty() && normSender.contains(it) }) return

        // Ignorar promoções, spam e códigos OTP/2FA
        if (noisePatterns.any { normText.contains(it) }) return

        // Deduplicação por SHA-256 com janela de 5 minutos
        val dedupHash = sha256Hex("${msg.packageName}|$normSender|$normText")
        val now = System.currentTimeMillis()
        val prevMs = recentDedupHashes[dedupHash]
        if (prevMs != null && (now - prevMs) < DEDUP_WINDOW_MS) {
            return
        }

        // Detecção de rajada (3+ mensagens do mesmo remetente em 60s)
        val burstKey = "${msg.packageName}|$normSender"
        val stamps = senderBursts.computeIfAbsent(burstKey) { mutableListOf() }
        val burstCount: Int
        synchronized(stamps) {
            stamps.removeAll { (now - it) > BURST_WINDOW_MS }
            stamps.add(now)
            burstCount = stamps.size
        }

        var score = 0.0
        val reasons = mutableListOf<String>()

        val vips = decodeStringList(prefs.getString(KEY_VIPS, null)).map { normalizeText(it) }
        val isVip = vips.any { it.isNotEmpty() && normSender.contains(it) }
        if (isVip) {
            score += 0.45
            reasons.add("VIP")
        }

        val customKw = decodeStringList(prefs.getString(KEY_KEYWORDS, null)).map { normalizeText(it) }
        val matchedCustom = customKw.firstOrNull { it.isNotEmpty() && normText.contains(it) }
        if (matchedCustom != null) {
            score += 0.65
            reasons.add("palavra:$matchedCustom")
        }

        val matchedCrit = criticalKeywords.firstOrNull { normText.contains(it) }
        if (matchedCrit != null) {
            score += 0.72
            reasons.add(matchedCrit)
        } else {
            val matchedTime = timeSensitiveKeywords.firstOrNull { normText.contains(it) }
            if (matchedTime != null) {
                score += 0.35
                reasons.add(matchedTime)
            }
        }

        if (burstCount >= 3) {
            score += 0.40
            reasons.add("rajada(${burstCount}x)")
        }

        if (msg.text.contains("!!") || msg.text.contains("??")) {
            score += 0.12
        }

        val finalScore = score.coerceIn(0.0, 1.0)
        val threshold = prefs.getFloat(KEY_THRESHOLD, 0.70f).toDouble()
        if (finalScore < threshold) return

        // Respeitar Foco Noturno (22h–06h): só fura se VIP ou urgência crítica (>= 0.90)
        val respectNight = prefs.getBoolean(KEY_RESPECT_NIGHT, true)
        val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        val isNight = hour >= 22 || hour < 6
        if (respectNight && isNight && !isVip && finalScore < 0.90) {
            return
        }

        recentDedupHashes[dedupHash] = now
        val reasonLabel = reasons.distinct().joinToString(", ")

        val payload = JSONObject().apply {
            put("appLabel", msg.appLabel)
            put("packageName", msg.packageName)
            put("sender", msg.sender)
            put("text", msg.text)
            put("score", finalScore)
            put("reasons", reasonLabel)
            put("timestampMs", msg.timestampMs)
            put("saveToObsidian", prefs.getBoolean(KEY_SAVE_OBSIDIAN, true))
        }
        enqueuePendingUrgent(this, payload)
        MainActivity.notifyUrgentNotificationDetected()

        postUrgentNotification(msg, finalScore, reasonLabel)
        DynamicIslandService.showNotificationAlert(msg.sender, msg.text, msg.appLabel)

        if (prefs.getBoolean(KEY_SPEAK_URGENT, false) && (!isNight || isVip)) {
            UltronTtsHelper.speak(
                this,
                "Mensagem urgente de ${msg.sender} no ${msg.appLabel}: ${msg.text.take(160)}",
            )
        }
    }

    private fun postUrgentNotification(msg: CapturedMessage, score: Double, reasonLabel: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (nm.getNotificationChannel(URGENT_CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    URGENT_CHANNEL_ID,
                    "Alertas urgentes (Triagem Inteligente)",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = "Notificações prioritárias filtradas pelo U.L.T.R.O.N."
                }
                nm.createNotificationChannel(ch)
            }
        }

        val notifId = ++urgentNotifSeq
        val pct = (score * 100).toInt()
        val shortText = msg.text.take(110)

        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPending = PendingIntent.getActivity(
            this,
            notifId,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val speakIntent = Intent(this, NotificationTriageActionReceiver::class.java).apply {
            action = NotificationTriageActionReceiver.ACTION_SPEAK_URGENT
            putExtra(
                NotificationTriageActionReceiver.EXTRA_SPEAK_TEXT,
                "Mensagem urgente de ${msg.sender} no ${msg.appLabel}: ${msg.text.take(240)}",
            )
            putExtra(NotificationTriageActionReceiver.EXTRA_NOTIFICATION_ID, notifId)
        }
        val speakPending = PendingIntent.getBroadcast(
            this,
            notifId + 10000,
            speakIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val muteIntent = Intent(this, NotificationTriageActionReceiver::class.java).apply {
            action = NotificationTriageActionReceiver.ACTION_MUTE_SENDER
            putExtra(NotificationTriageActionReceiver.EXTRA_SENDER, msg.sender)
            putExtra(NotificationTriageActionReceiver.EXTRA_NOTIFICATION_ID, notifId)
        }
        val mutePending = PendingIntent.getBroadcast(
            this,
            notifId + 20000,
            muteIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(this, URGENT_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Urgência ($pct%): ${msg.sender} · ${msg.appLabel}")
            .setContentText(shortText)
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText("${msg.text}\n\nSinais: ${reasonLabel.ifBlank { "urgência detectada" }}")
            )
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(openPending)
            .addAction(android.R.drawable.ic_lock_silent_mode_off, "Ouvir", speakPending)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Silenciar", mutePending)

        try {
            nm.notify(notifId, builder.build())
        } catch (_: SecurityException) {
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
