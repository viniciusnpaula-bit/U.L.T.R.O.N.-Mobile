package com.viniciusnpaula.ultron_mobile

import android.util.Log

private const val WAKE_TAG = "UltronWake"

/**
 * Executa uma limpeza best-effort registrando a falha em vez de engoli-la em silêncio.
 * Nunca registra conteúdo de áudio, frases ou credenciais — apenas o nome da operação e o
 * tipo da exceção.
 */
internal inline fun safely(what: String, block: () -> Unit) {
    try {
        block()
    } catch (e: Exception) {
        Log.d(WAKE_TAG, "$what falhou: ${e.javaClass.simpleName}")
    }
}

internal fun wakeLogW(message: String) {
    Log.w(WAKE_TAG, message)
}
