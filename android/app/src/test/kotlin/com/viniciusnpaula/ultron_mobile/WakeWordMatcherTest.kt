package com.viniciusnpaula.ultron_mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WakeWordMatcherTest {

    @Test
    fun matchesCanonicalAndAliases() {
        listOf("Ultron", "ULTRON", "ultrom", "outron", "Ultrón", "ultrão", "utron", "hultron")
            .forEach { assertTrue("deveria casar: $it", WakeWordMatcher.contains(it)) }
    }

    @Test
    fun matchesInsideSentenceWithFiller() {
        assertTrue(WakeWordMatcher.contains("Ei Ultron que horas são"))
        assertEquals(1, WakeWordMatcher.hotwordIndex("ei ultron ligar lanterna"))
        assertEquals(0, WakeWordMatcher.hotwordIndex("Ultron, abrir o WhatsApp"))
    }

    @Test
    fun matchesPunctuationAndAccents() {
        assertTrue(WakeWordMatcher.contains("Ultrón!"))
        assertTrue(WakeWordMatcher.contains("olá, ultron."))
    }

    @Test
    fun rejectsSubstringFalsePositives() {
        // Comparação por palavra inteira: não casa por substring (como o antigo `contains`).
        assertFalse(WakeWordMatcher.contains("ultrassom"))
        assertFalse(WakeWordMatcher.contains("eletron"))
        assertFalse(WakeWordMatcher.contains("ultronomia"))
    }

    @Test
    fun rejectsUnrelatedSpeech() {
        assertFalse(WakeWordMatcher.contains("que horas são"))
        assertFalse(WakeWordMatcher.contains(""))
        assertFalse(WakeWordMatcher.contains("   "))
    }

    @Test
    fun firstMatchPicksCandidateWithHotword() {
        assertEquals(
            "oi ultron",
            WakeWordMatcher.firstMatch(listOf("oi vitrô", " oi ultron ", "outra"))
        )
        assertNull(WakeWordMatcher.firstMatch(listOf("bom dia", "boa noite")))
        assertNull(WakeWordMatcher.firstMatch(null))
    }

    @Test
    fun levenshteinBasics() {
        assertEquals(0, WakeWordMatcher.levenshtein("ultron", "ultron"))
        assertEquals(1, WakeWordMatcher.levenshtein("ultron", "ultrom"))
        assertEquals(3, WakeWordMatcher.levenshtein("", "abc"))
    }
}
