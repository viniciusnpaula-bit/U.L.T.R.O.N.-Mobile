package com.viniciusnpaula.ultron_mobile

/**
 * Garante que a frase entregue ao Flutter comece com o hotword.
 *
 * O Vosk transcreve o anel de pré-roll, que pode ou não conter "Ultron" de forma
 * reconhecível. O Dart (`WakeWord.extractCommand`) só extrai comando se o hotword
 * estiver entre as 4 primeiras palavras, então o nativo normaliza aqui.
 */
object WakePhraseComposer {
    private const val HOTWORD = "ultron"

    fun ensurePhrase(transcript: String): String {
        val clean = transcript.trim()
        if (clean.isEmpty()) return HOTWORD
        return if (WakeWordMatcher.contains(clean)) clean else "$HOTWORD $clean"
    }
}
