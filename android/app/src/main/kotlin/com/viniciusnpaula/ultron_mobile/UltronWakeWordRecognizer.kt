package com.viniciusnpaula.ultron_mobile

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.util.Locale

/**
 * Reconhecedor de Palavra de Ativação ("ULTRON" / "EI ULTRON") com Bloqueio Anti-Eco:
 * 1. Aborta imediatamente se o próprio Ultron estiver falando (isUltronSpeakingGlobal /
 *    UltronTtsHelper.isSpeaking / AudioManager.isMusicActive) ou se o microfone principal
 *    já estiver aberto (isForegroundRecognizerActive).
 * 2. Garante disparo único (alreadyDispatched) para não abrir duas janelas de microfone.
 */
class UltronWakeWordRecognizer(
    private val context: Context,
    private val onHotwordDetected: (matchedText: String) -> Unit,
    private val onFinished: () -> Unit
) {
    private var recognizer: SpeechRecognizer? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var isListening = false
    private var alreadyDispatched = false

    private fun isSpeakerActive(): Boolean {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        return MainActivity.isUltronSpeakingGlobal ||
            UltronTtsHelper.isSpeaking ||
            MainActivity.isForegroundRecognizerActive ||
            (am?.isMusicActive == true)
    }

    fun startListening() {
        mainHandler.post {
            try {
                if (isSpeakerActive() || !SpeechRecognizer.isRecognitionAvailable(context)) {
                    onFinished()
                    return@post
                }

                destroy()
                alreadyDispatched = false
                val sr = SpeechRecognizer.createSpeechRecognizer(context)
                recognizer = sr

                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(
                        RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                        RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                    )
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, "pt-BR")
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "pt-BR")
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                    putExtra("android.speech.extra.PREFER_OFFLINE", true)
                }

                sr.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        if (isSpeakerActive()) {
                            cleanupAndFinish()
                            return
                        }
                        isListening = true
                    }

                    override fun onBeginningOfSpeech() {
                        if (isSpeakerActive()) {
                            cleanupAndFinish()
                        }
                    }

                    override fun onRmsChanged(rmsdB: Float) {}
                    override fun onBufferReceived(buffer: ByteArray?) {}
                    override fun onEndOfSpeech() {}

                    override fun onError(error: Int) {
                        isListening = false
                        cleanupAndFinish()
                    }

                    override fun onResults(results: Bundle?) {
                        isListening = false
                        if (!alreadyDispatched && !isSpeakerActive()) {
                            val matches =
                                results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            checkHotword(matches)
                        }
                        cleanupAndFinish()
                    }

                    override fun onPartialResults(partialResults: Bundle?) {
                        if (alreadyDispatched || isSpeakerActive()) return
                        val partials =
                            partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        if (checkHotword(partials)) {
                            isListening = false
                            try {
                                sr.stopListening()
                            } catch (_: Exception) {
                            }
                        }
                    }

                    override fun onEvent(eventType: Int, params: Bundle?) {}
                })

                sr.startListening(intent)

                // Timeout de segurança de 4.0 segundos
                mainHandler.postDelayed({
                    if (isListening) {
                        try {
                            sr.stopListening()
                        } catch (_: Exception) {
                        }
                    }
                }, 4000L)
            } catch (_: Exception) {
                cleanupAndFinish()
            }
        }
    }

    private fun checkHotword(candidates: List<String>?): Boolean {
        if (alreadyDispatched || candidates.isNullOrEmpty() || isSpeakerActive()) return false
        val aliases = listOf(
            "ultron",
            "ultrom",
            "outron",
            "oultron",
            "uoltron",
            "hultron",
            "utron",
            "ultrao",
            "ultrão",
            "ultrón"
        )
        for (candidate in candidates) {
            val lower = candidate.lowercase(Locale("pt", "BR"))
            if (aliases.any { lower.contains(it) }) {
                alreadyDispatched = true
                onHotwordDetected(candidate.trim())
                return true
            }
        }
        return false
    }

    private fun cleanupAndFinish() {
        destroy()
        onFinished()
    }

    fun destroy() {
        try {
            recognizer?.cancel()
        } catch (_: Exception) {
        }
        try {
            recognizer?.destroy()
        } catch (_: Exception) {
        }
        recognizer = null
        isListening = false
    }
}
