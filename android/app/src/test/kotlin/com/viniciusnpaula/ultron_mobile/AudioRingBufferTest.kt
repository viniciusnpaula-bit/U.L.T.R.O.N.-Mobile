package com.viniciusnpaula.ultron_mobile

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class AudioRingBufferTest {

    @Test
    fun `mantem ordem cronologica apos wrap`() {
        val ring = AudioRingBuffer(4)
        ring.write(shortArrayOf(1, 2, 3, 4))
        ring.write(shortArrayOf(5, 6))
        assertArrayEquals(shortArrayOf(3, 4, 5, 6), ring.snapshot())
    }

    @Test
    fun `snapshot parcial devolve apenas o escrito`() {
        val ring = AudioRingBuffer(8)
        ring.write(shortArrayOf(7, 8, 9))
        assertArrayEquals(shortArrayOf(7, 8, 9), ring.snapshot())
    }

    @Test
    fun `count menor que o frame grava so o inicio`() {
        val ring = AudioRingBuffer(4)
        ring.write(shortArrayOf(1, 2, 3, 4), 2)
        assertEquals(2, ring.snapshot().size)
        assertArrayEquals(shortArrayOf(1, 2), ring.snapshot())
    }

    @Test
    fun `clear zera o conteudo`() {
        val ring = AudioRingBuffer(4)
        ring.write(shortArrayOf(1, 2, 3, 4))
        ring.clear()
        assertEquals(0, ring.snapshot().size)
    }

    @Test
    fun `capacidade invalida falha`() {
        assertThrows(IllegalArgumentException::class.java) { AudioRingBuffer(0) }
    }
}
