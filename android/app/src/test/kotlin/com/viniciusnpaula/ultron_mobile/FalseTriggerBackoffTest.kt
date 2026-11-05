package com.viniciusnpaula.ultron_mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FalseTriggerBackoffTest {

    @Test
    fun `cooldown base nos dois primeiros misses`() {
        val b = FalseTriggerBackoff()
        assertEquals(1_500L, b.onMiss(0))
        assertEquals(1_500L, b.onMiss(1_000))
    }

    @Test
    fun `backoff progressivo a partir do terceiro miss`() {
        val b = FalseTriggerBackoff()
        b.onMiss(0); b.onMiss(1)
        assertEquals(5_000L, b.onMiss(2))
        assertEquals(10_000L, b.onMiss(3))
        assertEquals(20_000L, b.onMiss(4))
        assertEquals(30_000L, b.onMiss(5))
        assertEquals(30_000L, b.onMiss(6))
    }

    @Test
    fun `sucesso zera o contador`() {
        val b = FalseTriggerBackoff()
        b.onMiss(0); b.onMiss(1); b.onMiss(2)
        b.onSuccess(3)
        assertEquals(0, b.misses())
        assertEquals(1_500L, b.onMiss(4))
    }

    @Test
    fun `silencio de 60 s zera o contador`() {
        val b = FalseTriggerBackoff()
        b.onMiss(0)
        assertFalse(b.onQuiet(59_000))
        assertTrue(b.onQuiet(60_000))
        assertEquals(0, b.misses())
    }
}
