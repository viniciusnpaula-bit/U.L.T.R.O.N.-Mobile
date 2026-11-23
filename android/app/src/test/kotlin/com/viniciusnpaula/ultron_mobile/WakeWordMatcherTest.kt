package com.viniciusnpaula.ultron_mobile

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class WakeWordMatcherTest {

    @Before
    fun setUp() {
        WakeWordMatcher.activeProfile = WakeWordProfile.ULTRON
    }

    @After
    fun tearDown() {
        WakeWordMatcher.activeProfile = WakeWordProfile.ULTRON
    }

    @Test
    fun matchesCanonicalAndAliases() {
        listOf("Ultron", "ULTRON", "ultrom", "outron", "Ultrón", "ultrão", "utron", "hultron")
            .forEach { assertTrue("deveria casar: $it", WakeWordMatcher.contains(it)) }
    }

    @Test
    fun matchesMultiProfileJarvisEdithAndVisaoWithAliasesAndLevenshtein() {
        // Jarvis
        WakeWordMatcher.setActiveProfileById("jarvis")
        assertEquals(WakeWordProfile.JARVIS, WakeWordMatcher.activeProfile)
        listOf("Jarvis", "JARVIS", "jarves", "jarviz", "djarvis", "javis", "jarvi")
            .forEach { assertTrue("deveria casar Jarvis: $it", WakeWordMatcher.contains(it)) }
        assertFalse(WakeWordMatcher.contains("Ultron"))

        // Edith
        WakeWordMatcher.setActiveProfileById("edith")
        assertEquals(WakeWordProfile.EDITH, WakeWordMatcher.activeProfile)
        listOf("Edith", "EDITH", "edite", "edit", "editi", "hedith")
            .forEach { assertTrue("deveria casar Edith: $it", WakeWordMatcher.contains(it)) }
        assertFalse(WakeWordMatcher.contains("Jarvis"))

        // Visão
        WakeWordMatcher.setActiveProfileById("visao")
        assertEquals(WakeWordProfile.VISAO, WakeWordMatcher.activeProfile)
        listOf("Visão", "visao", "vizão", "vizao", "vision", "vison", "fisao")
            .forEach { assertTrue("deveria casar Visão: $it", WakeWordMatcher.contains(it)) }
        assertFalse(WakeWordMatcher.contains("que horas são"))
    }

    @Test
    fun detectsProfileAndExtractsCommandAcrossAllProfiles() {
        assertEquals(WakeWordProfile.ULTRON, WakeWordMatcher.detectProfile("Ei Ultron ligar lanterna"))
        assertEquals(WakeWordProfile.JARVIS, WakeWordMatcher.detectProfile("Oi Jarvis abrir agenda"))
        assertEquals(WakeWordProfile.EDITH, WakeWordMatcher.detectProfile("Ok Edite ler mensagens"))
        assertEquals(WakeWordProfile.VISAO, WakeWordMatcher.detectProfile("Fala Visão status do sistema"))
        assertNull(WakeWordMatcher.detectProfile("bom dia pessoal"))

        assertEquals("ligar a lanterna", WakeWordMatcher.extractCommand("Ei Jarvis, ligar a lanterna"))
        assertEquals("ler mensagens", WakeWordMatcher.extractCommand("Oi Edite, ler mensagens"))
        assertEquals("que horas são", WakeWordMatcher.extractCommand("Fala Visão, que horas são"))
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
