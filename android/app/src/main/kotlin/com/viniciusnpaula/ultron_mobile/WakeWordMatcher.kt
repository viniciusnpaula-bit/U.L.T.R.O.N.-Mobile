package com.viniciusnpaula.ultron_mobile

import java.text.Normalizer

/**
 * Matcher da palavra de ativação "Ultron" (v1.2.1).
 *
 * Espelha a lógica de `WakeWord` em lib/services/speech_text.dart:
 * compara palavra por palavra (nunca substring), sem acentos, aceitando aliases
 * conhecidos do reconhecedor pt-BR e distância de Levenshtein <= 1 para "ultron".
 * Isso elimina os falsos positivos por substring do antigo `contains` (ex.: "ultronomia");
 * a tolerância de 1 edição é mantida de propósito, igual ao Dart.
 */
object WakeWordMatcher {
    private const val TARGET = "ultron"

    private val aliases: Set<String> = setOf(
        "ultron", "ultrom", "outron", "oultron", "uoltron",
        "hultron", "ultrón", "utron", "ultrao", "ultrão"
    ).map { normalize(it) }.toSet()

    fun normalize(word: String): String {
        val decomposed = Normalizer.normalize(word.lowercase(), Normalizer.Form.NFD)
        return decomposed.replace(Regex("\\p{Mn}+"), "").replace(Regex("[^a-z0-9]"), "")
    }

    fun levenshtein(a: String, b: String): Int {
        if (a == b) return 0
        if (a.isEmpty()) return b.length
        if (b.isEmpty()) return a.length
        var prev = IntArray(b.length + 1) { it }
        for (i in a.indices) {
            val curr = IntArray(b.length + 1)
            curr[0] = i + 1
            for (j in b.indices) {
                val cost = if (a[i] == b[j]) 0 else 1
                curr[j + 1] = minOf(curr[j] + 1, prev[j + 1] + 1, prev[j] + cost)
            }
            prev = curr
        }
        return prev[b.length]
    }

    /** Verdadeiro se [token] soa como "Ultron". */
    fun isHotwordToken(token: String): Boolean {
        val n = normalize(token)
        if (n.length < 4 || n.length > 8) return false
        if (n in aliases) return true
        return levenshtein(n, TARGET) <= 1
    }

    /** Índice da palavra de ativação em [phrase], ou -1.
     *
     * Só as 4 primeiras palavras são consideradas, igual a `WakeWord.hotwordIndex` no Dart.
     * Sem esse limite, uma conversa comum que cite "Ultron" no meio da frase ativaria o
     * assistente e o comando extraído no Flutter ficaria inconsistente.
     */
    fun hotwordIndex(phrase: String): Int {
        val words = phrase.trim().split(Regex("\\s+"))
        for (i in words.indices) {
            if (i >= 4) break
            if (isHotwordToken(words[i])) return i
        }
        return -1
    }

    fun contains(phrase: String): Boolean = hotwordIndex(phrase) >= 0

    /** Primeiro candidato do reconhecedor que contém a palavra de ativação, ou null. */
    fun firstMatch(candidates: List<String>?): String? =
        candidates?.firstOrNull { contains(it) }?.trim()
}
