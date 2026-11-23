package com.viniciusnpaula.ultron_mobile

import java.text.Normalizer

enum class WakeWordProfile(
    val id: String,
    val displayName: String,
    val target: String,
    val minLength: Int,
    val maxLength: Int,
    val keywordsAssetFile: String,
    val sherpaInlineKeywords: String,
) {
    ULTRON(
        id = "ultron",
        displayName = "Ultron",
        target = "ultron",
        minLength = 4,
        maxLength = 8,
        keywordsAssetFile = "keywords_ultron.txt",
        sherpaInlineKeywords = "▁ UL T RO N :1.5 #0.25/▁ U T RO N :1.0 #0.25",
    ),
    JARVIS(
        id = "jarvis",
        displayName = "Jarvis",
        target = "jarvis",
        minLength = 4,
        maxLength = 8,
        keywordsAssetFile = "keywords_jarvis.txt",
        sherpaInlineKeywords = "▁JA R VI S :1.5 #0.25/▁ J AR VI S :1.2 #0.25",
    ),
    EDITH(
        id = "edith",
        displayName = "Edith",
        target = "edith",
        minLength = 4,
        maxLength = 7,
        keywordsAssetFile = "keywords_edith.txt",
        sherpaInlineKeywords = "▁E DI TH :1.5 #0.25/▁E DI T :1.1 #0.25/▁ ED IT :1.1 #0.25",
    ),
    VISAO(
        id = "visao",
        displayName = "Visão",
        target = "visao",
        minLength = 4,
        maxLength = 8,
        keywordsAssetFile = "keywords_visao.txt",
        sherpaInlineKeywords = "▁VI S A O :1.5 #0.25/▁VI Z A O :1.3 #0.25/▁VI S ION :1.3 #0.25",
    );

    companion object {
        fun fromId(raw: String?): WakeWordProfile {
            val clean = WakeWordMatcher.normalize(raw ?: "")
            return entries.firstOrNull { profile ->
                profile.id == clean ||
                    WakeWordMatcher.normalize(profile.displayName) == clean ||
                    (profile == VISAO && clean == "vision")
            } ?: ULTRON
        }
    }
}

/**
 * Matcher Multi-Perfil da palavra de ativação (Ultron, Jarvis, Edith, Visão).
 *
 * Espelha a lógica de `WakeWord` em lib/services/speech_text.dart:
 * compara palavra por palavra (nunca substring), sem acentos, aceitando mapa de aliases
 * conhecidos do reconhecedor pt-BR e distância de Levenshtein <= 1 por perfil.
 */
object WakeWordMatcher {
    @Volatile
    var activeProfile: WakeWordProfile = WakeWordProfile.ULTRON

    fun setActiveProfileById(id: String?): WakeWordProfile {
        val resolved = WakeWordProfile.fromId(id)
        activeProfile = resolved
        return resolved
    }

    val profileAliases: Map<WakeWordProfile, Set<String>> by lazy {
        mapOf(
            WakeWordProfile.ULTRON to setOf(
                "ultron", "ultrom", "outron", "oultron", "uoltron",
                "hultron", "ultrón", "utron", "ultrao", "ultrão",
                "ultram", "ultran", "altron",
            ).map { normalize(it) }.toSet(),
            WakeWordProfile.JARVIS to setOf(
                "jarvis", "jarves", "jarviz", "djarvis", "javis",
                "jarvi", "yarvis", "garvis", "jarbas",
            ).map { normalize(it) }.toSet(),
            WakeWordProfile.EDITH to setOf(
                "edith", "edite", "edit", "editi", "edid",
                "hedith", "eddy",
            ).map { normalize(it) }.toSet(),
            WakeWordProfile.VISAO to setOf(
                "visao", "visão", "vizao", "vizão", "vision",
                "vison", "fisao", "vizaum",
            ).map { normalize(it) }.toSet(),
        )
    }

    fun aliasesFor(profile: WakeWordProfile = activeProfile): Set<String> =
        profileAliases[profile] ?: emptySet()

    private val leadingFillerRegex = Regex(
        "^(?:ei|hey|ok|oi|ol[aá]|e\\s*a[ií]|fala|al[oô])[,\\s]+",
        RegexOption.IGNORE_CASE,
    )

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

    private fun matchesSingleProfile(normalizedToken: String, profile: WakeWordProfile): Boolean {
        if (normalizedToken.length < profile.minLength || normalizedToken.length > profile.maxLength) {
            return false
        }
        if (normalizedToken in aliasesFor(profile)) return true
        return levenshtein(normalizedToken, profile.target) <= 1
    }

    /** Verdadeiro se [token] soa como a wake-word do [profile] (ou todos os perfis se [anyProfile]). */
    @JvmOverloads
    fun isHotwordToken(
        token: String,
        profile: WakeWordProfile = activeProfile,
        anyProfile: Boolean = false,
    ): Boolean {
        val n = normalize(token)
        if (n.isEmpty()) return false
        if (anyProfile) {
            return WakeWordProfile.entries.any { matchesSingleProfile(n, it) }
        }
        return matchesSingleProfile(n, profile)
    }

    /** Índice da palavra de ativação em [phrase], ou -1. */
    @JvmOverloads
    fun hotwordIndex(
        phrase: String,
        profile: WakeWordProfile = activeProfile,
        anyProfile: Boolean = false,
    ): Int {
        val trimmed = phrase.trim()
        if (trimmed.isEmpty()) return -1
        val words = trimmed.split(Regex("\\s+"))
        for (i in words.indices) {
            if (isHotwordToken(words[i], profile = profile, anyProfile = anyProfile)) return i
        }
        return -1
    }

    @JvmOverloads
    fun contains(
        phrase: String,
        profile: WakeWordProfile = activeProfile,
        anyProfile: Boolean = false,
    ): Boolean = hotwordIndex(phrase, profile = profile, anyProfile = anyProfile) >= 0

    /** Detecta qual perfil de wake-word está presente em [phrase], ou null. */
    fun detectProfile(phrase: String): WakeWordProfile? {
        if (contains(phrase, profile = activeProfile)) return activeProfile
        return WakeWordProfile.entries.firstOrNull { it != activeProfile && contains(phrase, profile = it) }
    }

    /** Remove a saudação + wake-word do início de [phrase] e retorna o comando restante. */
    @JvmOverloads
    fun extractCommand(
        phrase: String,
        profile: WakeWordProfile = activeProfile,
        anyProfile: Boolean = false,
    ): String {
        val trimmed = phrase.trim()
        if (trimmed.isEmpty()) return ""
        val words = trimmed.split(Regex("\\s+"))
        var idx = hotwordIndex(trimmed, profile = profile, anyProfile = anyProfile)
        if (idx < 0 && !anyProfile) {
            idx = hotwordIndex(trimmed, anyProfile = true)
        }
        if (idx < 0) return trimmed
        val rest = words.subList(idx + 1, words.size).joinToString(" ")
        return rest
            .replaceFirst(Regex("^[,.:;!?\\s]+"), "")
            .replaceFirst(leadingFillerRegex, "")
            .trim()
    }

    /** Primeiro candidato do reconhecedor que contém a palavra de ativação, ou null. */
    @JvmOverloads
    fun firstMatch(
        candidates: List<String>?,
        profile: WakeWordProfile = activeProfile,
        anyProfile: Boolean = false,
    ): String? =
        candidates?.firstOrNull { contains(it, profile = profile, anyProfile = anyProfile) }?.trim()
}
