package com.viniciusnpaula.ultron_mobile

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Wrapper de Voz Offline do U.L.T.R.O.N. (Ultra-Otimizado):
 * 1. Reproduz "ultron_fish_voice.wav" de assets/ via AssetFileDescriptor e libera o MediaPlayer
 *    imediatamente após o término (zero retenção de codec de hardware).
 * 2. Combina a assinatura vocal da Fish Audio com o motor neural offline nativo do Android
 *    (TextToSpeech em pitch grave 0.55f).
 * 3. Auto-Hibernação do Binder TTS: desliga automaticamente a instância do TextToSpeech
 *    após 25 segundos sem falar, liberando 100% da memória RAM e conexões IPC em repouso.
 */
object UltronTtsHelper {
    private const val VOICE_ASSET_NAME = "ultron_fish_voice.wav"
    private const val IDLE_SHUTDOWN_DELAY_MS = 25_000L

    private val mainHandler = Handler(Looper.getMainLooper())
    private val idleShutdownRunnable = Runnable { shutdownTtsOnly() }

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
            mp.setOnErrorListener { _, _, _ ->
                releasePlayer()
                onComplete?.invoke()
                true
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

    private fun scheduleIdleShutdown() {
        mainHandler.removeCallbacks(idleShutdownRunnable)
        mainHandler.postDelayed(idleShutdownRunnable, IDLE_SHUTDOWN_DELAY_MS)
    }

    private fun speakWithOfflineEngine(appContext: Context, text: String) {
        scheduleIdleShutdown()
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
                offlineTts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {
                        mainHandler.removeCallbacks(idleShutdownRunnable)
                    }

                    override fun onDone(utteranceId: String?) {
                        scheduleIdleShutdown()
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {
                        scheduleIdleShutdown()
                    }
                })
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

    private fun shutdownTtsOnly() {
        try {
            offlineTts?.stop()
            offlineTts?.shutdown()
        } catch (_: Exception) {
        }
        offlineTts = null
        ttsReady = false
    }

    fun shutdown() {
        mainHandler.removeCallbacks(idleShutdownRunnable)
        releasePlayer()
        shutdownTtsOnly()
    }
}
