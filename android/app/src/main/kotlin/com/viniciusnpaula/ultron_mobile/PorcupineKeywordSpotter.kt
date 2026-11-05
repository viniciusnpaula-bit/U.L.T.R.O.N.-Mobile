package com.viniciusnpaula.ultron_mobile

import android.content.Context
import ai.picovoice.porcupine.Porcupine
import java.io.File

/**
 * Motor de keyword spotting dedicado (Porcupine).
 *
 * O `.ppn` e treinado no Picovoice Console para a frase "ultron" em portugues.
 * Ele vive em assets e precisa ser copiado para um arquivo real: a API do
 * Porcupine recebe caminho, nao asset.
 *
 * Erros de licença/key/modelo nao derrubam o servico: `isConfigured` fica falso
 * e `unavailableReason` explica o motivo. A AccessKey nunca e logada nem
 * incluída no motivo exibido na UI.
 */
class PorcupineKeywordSpotter(
    private val context: Context,
    private val accessKey: String,
    private val keywordAsset: String = "porcupine/ultron_pt.ppn",
) {
    private var porcupine: Porcupine? = null
    var unavailableReason: String? = null
        private set

    val isConfigured: Boolean get() = porcupine != null
    val frameLength: Int get() = porcupine?.frameLength ?: FRAME_FALLBACK

    fun init() {
        if (accessKey.isBlank()) {
            unavailableReason = "AccessKey ausente"
            return
        }
        val keywordFile = try {
            copyAsset(keywordAsset)
        } catch (_: Exception) {
            unavailableReason = "keyword .ppn ausente em assets/$keywordAsset"
            return
        }
        try {
            porcupine = Porcupine.Builder()
                .setAccessKey(accessKey)
                .setKeywordPath(keywordFile.absolutePath)
                .setSensitivity(SENSITIVITY)
                .build(context)
            unavailableReason = null
        } catch (e: Exception) {
            // Mensagem do Porcupine nao contem a AccessKey. Nunca logar a chave.
            unavailableReason = "falha ao iniciar Porcupine: ${e.message}"
            porcupine = null
        }
    }

    /** true quando a palavra foi detectada neste frame de [frameLength] amostras. */
    fun process(frame: ShortArray): Boolean {
        val engine = porcupine ?: return false
        return engine.process(frame) == 1
    }

    fun close() {
        try {
            porcupine?.delete()
        } catch (_: Exception) {
        } finally {
            porcupine = null
        }
    }

    private fun copyAsset(assetPath: String): File {
        val dir = File(context.filesDir, "porcupine").apply { mkdirs() }
        val out = File(dir, assetPath.substringAfterLast('/'))
        context.assets.open(assetPath).use { input ->
            out.outputStream().use { output -> input.copyTo(output) }
        }
        return out
    }

    private companion object {
        const val SENSITIVITY = 0.5f
        const val FRAME_FALLBACK = 512
    }
}
