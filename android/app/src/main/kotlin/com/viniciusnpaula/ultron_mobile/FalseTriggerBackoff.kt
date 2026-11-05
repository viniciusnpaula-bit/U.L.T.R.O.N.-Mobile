package com.viniciusnpaula.ultron_mobile

/**
 * Política para gatilhos do Porcupine que não viraram comando.
 *
 * Um falso positivo custa caro (carregar o Vosk e transcrever), então misses
 * consecutivos aumentam a espera antes de aceitar o próximo gatilho.
 */
class FalseTriggerBackoff(
    private val baseCooldownMs: Long = 1_500L,
    private val quietResetMs: Long = 60_000L,
    private val maxBackoffMs: Long = 30_000L,
) {
    private var misses = 0
    private var lastMissMs = 0L

    fun onMiss(nowMs: Long): Long {
        misses++
        lastMissMs = nowMs
        if (misses < 3) return baseCooldownMs
        val step = (misses - 3).coerceAtMost(4)
        return (5_000L shl step).coerceAtMost(maxBackoffMs)
    }

    fun onSuccess(nowMs: Long) {
        misses = 0
        lastMissMs = nowMs
    }

    /** Zera contadores após um período de silêncio; devolve true se zerou. */
    fun onQuiet(nowMs: Long): Boolean {
        if (misses > 0 && nowMs - lastMissMs >= quietResetMs) {
            misses = 0
            return true
        }
        return false
    }

    fun misses(): Int = misses
}
