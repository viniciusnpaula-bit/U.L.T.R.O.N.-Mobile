package com.viniciusnpaula.ultron_mobile

import android.content.Context
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import java.io.File
import java.util.zip.ZipInputStream

/**
 * Transcreve o comando usando Vosk offline.
 *
 * Diferente do SpeechRecognizer, o Vosk aceita PCM injetado — e isso que torna o
 * pre-roll possivel: o audio anterior ao gatilho entra antes do audio ao vivo.
 */
class VoskCommandTranscriber(
    private val context: Context,
    private val modelAsset: String = "vosk/model-pt.zip",
    private val modelDirName: String = "vosk-model-small-pt-0.3",
) {
    private var model: Model? = null
    private var lastUsedMs = 0L
    var lastError: String? = null
        private set

    val isLoaded: Boolean get() = model != null

    fun ensureLoaded(): Boolean {
        model?.let { return true }
        val dir = File(context.filesDir, modelDirName)
        return try {
            if (!dir.exists()) unzipAsset(dir)
            require(dir.exists()) { "modelo nao descompactou em ${dir.name}" }
            model = Model(dir.absolutePath)
            lastUsedMs = System.currentTimeMillis()
            lastError = null
            true
        } catch (e: Exception) {
            lastError = "modelo Vosk indisponível: ${e.message}"
            model = null
            false
        }
    }

    /**
     * Transcreve [preroll] e depois pede mais audio a [readMore] ate o Vosk sinalizar
     * fim de fala ou [maxMs] estourar. [readMore] devolve amostras lidas; <= 0 encerra.
     */
    fun transcribe(
        preroll: ShortArray,
        readMore: (ShortArray) -> Int,
        maxMs: Long = 5_000L,
    ): String {
        val loaded = model ?: return ""
        val recognizer = try {
            Recognizer(loaded, SAMPLE_RATE.toFloat())
        } catch (e: Exception) {
            lastError = "Recognizer Vosk falhou: ${e.message}"
            return ""
        }
        try {
            if (preroll.isNotEmpty()) recognizer.acceptWaveForm(preroll, preroll.size)
            val buffer = ShortArray(CHUNK_SAMPLES)
            var elapsedMs = 0L
            while (elapsedMs < maxMs) {
                val count = readMore(buffer)
                if (count <= 0) break
                if (recognizer.acceptWaveForm(buffer, count)) break
                elapsedMs += CHUNK_MS
            }
            return extractText(recognizer.finalResult)
        } catch (e: Exception) {
            lastError = "transcricao falhou: ${e.message}"
            return ""
        } finally {
            lastUsedMs = System.currentTimeMillis()
            try {
                recognizer.close()
            } catch (_: Exception) {
            }
        }
    }

    fun unloadAfterIdle(nowMs: Long, idleMs: Long = 120_000L) {
        val current = model ?: return
        if (nowMs - lastUsedMs < idleMs) return
        try {
            current.close()
        } catch (_: Exception) {
        }
        model = null
    }

    fun close() {
        try {
            model?.close()
        } catch (_: Exception) {
        } finally {
            model = null
        }
    }

    private fun extractText(json: String): String {
        return try {
            JSONObject(json).optString("text", "").trim()
        } catch (_: Exception) {
            json.trim()
        }
    }

    private fun unzipAsset(targetDir: File) {
        val parent = targetDir.parentFile ?: context.filesDir
        val temp = File(parent, "${targetDir.name}.tmp")
        temp.deleteRecursively()
        context.assets.open(modelAsset).use { input ->
            ZipInputStream(input).use { zip ->
                var entry = zip.nextEntry
                while (entry != null) {
                    val out = File(temp, entry.name)
                    if (entry.isDirectory) {
                        out.mkdirs()
                    } else {
                        out.parentFile?.mkdirs()
                        out.outputStream().use { zip.copyTo(it) }
                    }
                    zip.closeEntry()
                    entry = zip.nextEntry
                }
            }
        }
        // O zip carrega a pasta raiz vosk-model-small-pt-0.3/; o destino final ja tem esse nome.
        val extractedRoot = File(temp, modelDirName)
        val source = if (extractedRoot.exists()) extractedRoot else temp
        if (!source.renameTo(targetDir)) {
            source.copyRecursively(targetDir, overwrite = true)
            temp.deleteRecursively()
        }
    }

    private companion object {
        const val SAMPLE_RATE = 16_000
        const val CHUNK_SAMPLES = 3_200 // 200 ms
        const val CHUNK_MS = 200L
    }
}
