package com.viniciusnpaula.ultron_mobile

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.util.Locale

/**
 * Reconhecedor de Palavra de Ativação ("ULTRON" / "EI ULTRON"):
 * Roda de forma pontual após o Eco-VAD detectar presença de voz.
 * Usa SpeechRecognizer nativo com extras de retorno parcial e offline (FREE_FORM pt-BR).
 * Se o usuário disse "Ultron" ou "Ei Ultron", dispara o callback com a frase reconhecida.
 */
class UltronWakeWordRecognizer(
    private val context: Context,
    private val onHotwordDetected: (matchedText: String) -> Unit,
    private val onFinished: () -> Unit
) {
    private var recognizer: SpeechRecognizer? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var isListening = false

    fun startListening() {
        mainHandler.post {
            try {
                if (!SpeechRecognizer.isRecognitionAvailable(context)) {
                    onFinished()
                    return@post
                }

                destroy()
                val sr = SpeechRecognizer.createSpeechRecognizer(context)
                recognizer = sr

                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, "pt-BR")
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "pt-BR")
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                    // Tenta preferência offline para respostas instantâneas
                    putExtra("android.speech.extra.PREFER_OFFLINE", true)
                }

                sr.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        isListening = true
                    }

                    override fun onBeginningOfSpeech() {}
                    override fun onRmsChanged(rmsdB: Float) {}
                    override fun onBufferReceived(buffer: ByteArray?) {}
                    override fun onEndOfSpeech() {}

                    override fun onError(error: Int) {
                        isListening = false
                        cleanupAndFinish()
                    }

                    override fun onResults(results: Bundle?) {
                        isListening = false
                        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        checkAndDispatch(matches)
                        cleanupAndFinish()
                    }

                    override fun onPartialResults(partialResults: Bundle?) {
                        val partials = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        if (checkHotword(partials)) {
                            isListening = false
                            try {
                                sr.stopListening()
                            } catch (_: Exception) {}
                        }
                    }

                    override fun onEvent(eventType: Int, params: Bundle?) {}
                })

                sr.startListening(intent)

                // Timeout de segurança de 4.5 segundos para não prender o microfone
                mainHandler.postDelayed({
                    if (isListening) {
                        try {
                            sr.stopListening()
                        } catch (_: Exception) {}
                    }
                }, 4500L)

            } catch (_: Exception) {
                cleanupAndFinish()
            }
        }
    }

    private fun checkHotword(candidates: List<String>?): Boolean {
        if (candidates.isNullOrEmpty()) return false
        for (candidate in candidates) {
            val lower = candidate.lowercase(Locale("pt", "BR"))
            if (lower.contains("ultron") || lower.contains("outron") || lower.contains("uoltron")) {
                onHotwordDetected(candidate)
                return true
            }
        }
        return false
    }

    private fun checkAndDispatch(matches: List<String>?) {
        if (matches.isNullOrEmpty()) return
        checkHotword(matches)
    }

    private fun cleanupAndFinish() {
        destroy()
        onFinished()
    }

    fun destroy() {
        try {
            recognizer?.destroy()
        } catch (_: Exception) {}
        recognizer = null
        isListening = false
    }
}
