package com.viniciusnpaula.ultron_mobile

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.speech.tts.TextToSpeech
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Wrapper de Voz Offline do U.L.T.R.O.N.:
 * 1. Reproduz o arquivo "ultron_fish_voice.wav" diretamente de assets/ via AssetFileDescriptor
 *    (corrigindo o bug de Uri.parse("asset:///...") que falha no MediaPlayer do Android).
 * 2. Combina a assinatura vocal da Fish Audio com o motor neural offline nativo do Android
 *    (TextToSpeech calibrado em pitch grave 0.55f) sem exigir bibliotecas quebradas como
 *    org.mozilla:tts:0.1.0 e sem drenar bateria em repouso.
 */
object UltronTtsHelper {
    private const val VOICE_ASSET_NAME = "ultron_fish_voice.wav"
    private var player: MediaPlayer? = null
    private var offlineTts: TextToSpeech? = null
    private var ttsReady: Boolean = false

    fun playFishVoiceAsset(context: Context, onComplete: (() -> Unit)? = null): Boolean {
        return try {
            releasePlayer()
            val afd = context.assets.openFd(VOICE_ASSET_NAME)
            val mp = MediaPlayer()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                mp.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
            }
            mp.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            afd.close()
            mp.setOnCompletionListener {
                releasePlayer()
                onComplete?.invoke()
            }
            mp.prepare()
            mp.start()
            player = mp
            true
        } catch (_: Exception) {
            onComplete?.invoke()
            false
        }
    }

    fun speak(context: Context, text: String, playSampleFirst: Boolean = true) {
        val clean = text.trim()
        if (clean.isEmpty()) {
            playFishVoiceAsset(context)
            return
        }
        if (playSampleFirst) {
            playFishVoiceAsset(context) {
                speakWithOfflineEngine(context.applicationContext, clean)
            }
        } else {
            speakWithOfflineEngine(context.applicationContext, clean)
        }
    }

    fun answerQuickOfflineQuery(context: Context, query: String): String {
        val lower = query.lowercase(Locale("pt", "BR"))
        val reply = when {
            lower.contains("que horas") || lower.contains("horário") || lower.contains("hora") -> {
                val now = SimpleDateFormat("HH:mm", Locale("pt", "BR")).format(Date())
                "Operador, agora são exatamente $now."
            }
            lower.contains("data") || lower.contains("que dia") -> {
                val today = SimpleDateFormat("dd 'de' MMMM 'de' yyyy", Locale("pt", "BR")).format(Date())
                "Hoje é dia $today."
            }
            else -> query
        }
        speak(context, reply, playSampleFirst = true)
        return reply
    }

    private fun speakWithOfflineEngine(appContext: Context, text: String) {
        if (offlineTts != null && ttsReady) {
            offlineTts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "ultron_offline_utt")
            return
        }
        offlineTts = TextToSpeech(appContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                ttsReady = true
                offlineTts?.language = Locale("pt", "BR")
                offlineTts?.setPitch(0.55f)
                offlineTts?.setSpeechRate(0.92f)
                offlineTts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "ultron_offline_utt")
            }
        }
    }

    fun releasePlayer() {
        try {
            player?.stop()
        } catch (_: Exception) {
        }
        try {
            player?.release()
        } catch (_: Exception) {
        }
        player = null
    }

    fun shutdown() {
        releasePlayer()
        try {
            offlineTts?.stop()
            offlineTts?.shutdown()
        } catch (_: Exception) {
        }
        offlineTts = null
        ttsReady = false
    }
}
