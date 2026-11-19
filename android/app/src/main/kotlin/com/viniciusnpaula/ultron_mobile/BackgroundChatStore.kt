package com.viniciusnpaula.ultron_mobile

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

data class BackgroundChatTurn(
    val userText: String,
    val assistantText: String,
    val senderLabel: String,
    val userTimestampMs: Long,
    val replyTimestampMs: Long,
)

/**
 * Fila cifrada (AES-256-GCM via AndroidKeyStore) para persistir turnos de conversa
 * executados em 2º plano e sincronizá-los com o histórico SQLCipher/feed do Flutter.
 */
object BackgroundChatStore {
    private const val PREFS_NAME = "ultron_bg_chat_prefs"
    private const val KEY_PENDING = "encrypted_pending_turns_v1"
    private const val KEY_CONTEXT = "encrypted_recent_context_v1"
    private const val MAX_PENDING_TURNS = 50
    private const val MAX_CONTEXT_TURNS = 8
    private val lock = Any()

    fun enqueueTurn(context: Context, turn: BackgroundChatTurn) {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val pending = loadArray(prefs.getString(KEY_PENDING, null))
            pending.put(turnToJson(turn))
            val trimmedPending = trimArray(pending, MAX_PENDING_TURNS)

            val recent = loadArray(prefs.getString(KEY_CONTEXT, null))
            recent.put(turnToJson(turn))
            val trimmedRecent = trimArray(recent, MAX_CONTEXT_TURNS)

            val encPending = BackgroundVoiceConfigStore.encryptString(trimmedPending.toString())
            val encRecent = BackgroundVoiceConfigStore.encryptString(trimmedRecent.toString())
            prefs.edit().apply {
                if (encPending != null) putString(KEY_PENDING, encPending)
                if (encRecent != null) putString(KEY_CONTEXT, encRecent)
            }.apply()
        }
    }

    fun consumePendingTurns(context: Context): List<Map<String, Any>> {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val arr = loadArray(prefs.getString(KEY_PENDING, null))
            if (arr.length() == 0) return emptyList()
            prefs.edit().remove(KEY_PENDING).apply()

            val out = ArrayList<Map<String, Any>>(arr.length())
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                out.add(
                    mapOf(
                        "userText" to obj.optString("userText", ""),
                        "assistantText" to obj.optString("assistantText", ""),
                        "senderLabel" to obj.optString("senderLabel", "U.L.T.R.O.N."),
                        "userTimestampMs" to obj.optLong("userTimestampMs", System.currentTimeMillis()),
                        "replyTimestampMs" to obj.optLong("replyTimestampMs", System.currentTimeMillis()),
                    )
                )
            }
            return out
        }
    }

    fun recentHistoryPairs(context: Context): List<Pair<String, String>> {
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val arr = loadArray(prefs.getString(KEY_CONTEXT, null))
            val pairs = ArrayList<Pair<String, String>>(arr.length())
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                val u = obj.optString("userText", "").trim()
                val a = obj.optString("assistantText", "").trim()
                if (u.isNotEmpty() && a.isNotEmpty()) {
                    pairs.add(Pair(u, a))
                }
            }
            return pairs
        }
    }

    private fun loadArray(encoded: String?): JSONArray {
        if (encoded.isNullOrBlank()) return JSONArray()
        val raw = BackgroundVoiceConfigStore.decryptString(encoded) ?: return JSONArray()
        return try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
    }

    private fun trimArray(arr: JSONArray, maxItems: Int): JSONArray {
        if (arr.length() <= maxItems) return arr
        val out = JSONArray()
        for (i in (arr.length() - maxItems) until arr.length()) {
            out.put(arr.get(i))
        }
        return out
    }

    private fun turnToJson(turn: BackgroundChatTurn): JSONObject {
        return JSONObject().apply {
            put("userText", turn.userText)
            put("assistantText", turn.assistantText)
            put("senderLabel", turn.senderLabel)
            put("userTimestampMs", turn.userTimestampMs)
            put("replyTimestampMs", turn.replyTimestampMs)
        }
    }
}
