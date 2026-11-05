package com.viniciusnpaula.ultron_mobile

import org.junit.Assert.assertEquals
import org.junit.Test

class WakePhraseComposerTest {

    @Test
    fun `hotword na primeira posicao e preservada`() {
        assertEquals("ultron desliga a luz", WakePhraseComposer.ensurePhrase("ultron desliga a luz"))
    }

    @Test
    fun `hotword ate a quarta posicao e preservada`() {
        assertEquals("ei ultron desliga", WakePhraseComposer.ensurePhrase("ei ultron desliga"))
    }

    @Test
    fun `texto sem hotword recebe prefixo`() {
        assertEquals("ultron desliga a luz", WakePhraseComposer.ensurePhrase("desliga a luz"))
    }

    @Test
    fun `hotword depois da quarta palavra recebe prefixo`() {
        assertEquals(
            "ultron um dois tres quatro ultron",
            WakePhraseComposer.ensurePhrase("um dois tres quatro ultron")
        )
    }

    @Test
    fun `texto vazio devolve apenas o hotword`() {
        assertEquals("ultron", WakePhraseComposer.ensurePhrase("   "))
    }
}
