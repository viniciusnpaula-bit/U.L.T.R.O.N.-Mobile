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

/**
 * Reconhecedor de Palavra de Ativação ("ULTRON" / "EI ULTRON") com Bloqueio Anti-Eco (v1.2.1).
 *
 * - Aborta se o Ultron estiver falando ou se o microfone principal estiver aberto.
 * - Usa [WakeWordMatcher] (palavra inteira, sem acentos, Levenshtein <= 1).
 * - Ao ver "Ultron" num parcial, NÃO corta a escuta: espera o resultado final para
 *   despachar a frase completa ("Ultron, que horas são") e, se o final vier vazio ou
 *   falhar, despacha o parcial já capturado. Nenhuma ativação é descartada.
 * - [onFinished] é chamado exatamente uma vez, com o resultado e o código de erro, para
 *   que o serviço aplique backoff e reabra o microfone de captura.
 */
class UltronWakeWordRecognizer(
    private val context: Context,
    private val onHotwordDetected: (matchedText: String) -> Unit,
    private val onFinished: (detected: Boolean, error: Int) -> Unit
) {
    companion object {
        const val NO_ERROR = -1
        private const val LISTEN_TIMEOUT_MS = 4500L
        private const val HARD_TIMEOUT_MS = 7000L
    }

    private var recognizer: SpeechRecognizer? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var isListening = false
    private var dispatched = false
    private var finished = false
    private var partialMatch: String? = null
    private var lastError = NO_ERROR

    private val softTimeout = Runnable {
        if (isListening) {
            safely("stopListening(timeout)") { recognizer?.stopListening() }
        }
    }
    private val hardTimeout = Runnable { finish() }

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
                if (isSpeakerActive()) {
                    finish()
                    return@post
                }
                if (!SpeechRecognizer.isRecognitionAvailable(context)) {
                    lastError = SpeechRecognizer.ERROR_CLIENT
                    finish()
                    return@post
                }

                releaseRecognizer()
                dispatched = false
                finished = false
                partialMatch = null
                lastError = NO_ERROR

                val sr = SpeechRecognizer.createSpeechRecognizer(context)
                recognizer = sr

                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(
                        RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                        RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                    )
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, "pt-BR")
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "pt-BR")
                    putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                    putExtra(
                        RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                        1200L
                    )
                    putExtra(
                        RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                        900L
                    )
                }

                sr.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        if (isSpeakerActive()) {
                            finish()
                            return
                        }
                        isListening = true
                    }

                    override fun onBeginningOfSpeech() {
                        if (isSpeakerActive()) finish()
                    }

                    override fun onRmsChanged(rmsdB: Float) {}
                    override fun onBufferReceived(buffer: ByteArray?) {}
                    override fun onEndOfSpeech() {}

                    override fun onError(error: Int) {
                        isListening = false
                        lastError = error
                        // Perdeu o final mas já havia ouvido "Ultron" num parcial: despacha.
                        dispatchPartialIfAny()
                        finish()
                    }

                    override fun onResults(results: Bundle?) {
                        isListening = false
                        if (!dispatched && !isSpeakerActive()) {
                            val matches =
                                results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            val hit = WakeWordMatcher.firstMatch(matches)
                            if (hit != null) {
                                dispatch(hit)
                            } else {
                                dispatchPartialIfAny()
                            }
                        }
                        finish()
                    }

                    override fun onPartialResults(partialResults: Bundle?) {
                        if (dispatched || isSpeakerActive()) return
                        val partials =
                            partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        val hit = WakeWordMatcher.firstMatch(partials)
                        if (hit != null) {
                            partialMatch = hit
                            // Deixa o reconhecedor terminar a frase; o final traz o comando.
                        }
                    }

                    override fun onEvent(eventType: Int, params: Bundle?) {}
                })

                sr.startListening(intent)
                mainHandler.postDelayed(softTimeout, LISTEN_TIMEOUT_MS)
                mainHandler.postDelayed(hardTimeout, HARD_TIMEOUT_MS)
            } catch (e: Exception) {
                wakeLogW("falha ao inicializar SpeechRecognizer: ${e.javaClass.simpleName}")
                lastError = SpeechRecognizer.ERROR_CLIENT
                finish()
            }
        }
    }

    private fun dispatchPartialIfAny() {
        val p = partialMatch
        if (!dispatched && p != null && !isSpeakerActive()) dispatch(p)
    }

    private fun dispatch(phrase: String) {
        // destroy()/timeout marcam finished: um resultado atrasado não pode ativar de novo.
        if (dispatched || finished) return
        dispatched = true
        onHotwordDetected(phrase)
    }

    private fun finish() {
        if (finished) return
        finished = true
        mainHandler.removeCallbacks(softTimeout)
        mainHandler.removeCallbacks(hardTimeout)
        releaseRecognizer()
        onFinished(dispatched, lastError)
    }

    private fun releaseRecognizer() {
        safely("recognizer.cancel") { recognizer?.cancel() }
        safely("recognizer.destroy") { recognizer?.destroy() }
        recognizer = null
        isListening = false
    }

    /** Cancelamento externo (onDestroy do serviço): não dispara callbacks. */
    fun destroy() {
        finished = true
        mainHandler.removeCallbacks(softTimeout)
        mainHandler.removeCallbacks(hardTimeout)
        mainHandler.post { releaseRecognizer() }
    }
}
