package com.viniciusnpaula.ultron_mobile

/**
 * Anel circular de amostras PCM16.
 *
 * Guarda o áudio imediatamente anterior a um gatilho para que o comando falado logo
 * depois da palavra de ativação não perca o início. Vive só em memória.
 */
class AudioRingBuffer(private val capacity: Int) {
    private val data = ShortArray(capacity)
    private var writeIndex = 0
    private var filled = 0

    init {
        require(capacity > 0) { "capacity deve ser > 0" }
    }

    fun write(frame: ShortArray, count: Int = frame.size) {
        require(count <= frame.size) { "count maior que o frame" }
        for (i in 0 until count) {
            data[writeIndex] = frame[i]
            writeIndex = (writeIndex + 1) % capacity
            if (filled < capacity) filled++
        }
    }

    /** Conteúdo em ordem cronológica (mais antigo primeiro). */
    fun snapshot(): ShortArray {
        val out = ShortArray(filled)
        val start = (writeIndex - filled + capacity) % capacity
        for (i in 0 until filled) out[i] = data[(start + i) % capacity]
        return out
    }

    fun clear() {
        writeIndex = 0
        filled = 0
    }
}
