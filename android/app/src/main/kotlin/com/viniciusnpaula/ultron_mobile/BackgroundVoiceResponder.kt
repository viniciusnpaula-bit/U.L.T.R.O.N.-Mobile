package com.viniciusnpaula.ultron_mobile

import android.content.Context
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.ToneGenerator
import android.os.SystemClock
import android.view.KeyEvent
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Executa um turno completo de voz em 2º plano quando o usuário chama "Ultron"
 * com o app fechado/minimizado ou tela bloqueada:
 * microfone nativo AudioRecord -> STT não-Google (Groq/Whisper) -> ação segura ou IA ->
 * Fish Audio API (ou TTS offline Android), sem precisar abrir a interface.
 */
object BackgroundVoiceResponder {
    private const val SAMPLE_RATE_HZ = 16000
    private const val CHUNK_SAMPLES = 1600 // 100 ms
    private const val CHUNK_BYTES = CHUNK_SAMPLES * 2
    private const val MAX_WAIT_SPEECH_CHUNKS = 38 // 3.8 s esperando começar a falar
    private const val SILENCE_END_CHUNKS = 10 // 1.0 s de silêncio encerra comando
    private const val MAX_SPEECH_CHUNKS = 100 // 10 s máx. por turno
    private const val PRE_SPEECH_CHUNKS = 4 // 400 ms pré-fala

    fun runBackgroundTurn(
        context: Context,
        onStatusUpdate: (String) -> Unit,
        onReplyNotification: (String, String) -> Unit,
    ) {
        val cfg = BackgroundVoiceConfigStore.load(context)

        playReadyBeep()
        onStatusUpdate("Ouvindo comando em segundo plano…")

        val pcm = captureCommandPcm()
        if (pcm == null || pcm.isEmpty()) {
            return
        }

        if (!cfg.hasStt) {
            val msg = "Operador, configure uma chave Groq nas configurações de IA para comandos em segundo plano."
            onReplyNotification("Chave STT necessária", msg)
            UltronTtsHelper.speakBlocking(context, msg)
            return
        }

        onStatusUpdate("Transcrevendo comando…")
        val wav = buildWav(pcm, SAMPLE_RATE_HZ)
        val transcript = transcribeWhisper(cfg, wav)?.trim().orEmpty()
        if (transcript.length < 2) {
            return
        }

        val localReply = tryLocalSafeAction(context, transcript)
        val reply = if (localReply != null) {
            localReply
        } else {
            onStatusUpdate("Consultando U.L.T.R.O.N…")
            queryAi(cfg, transcript)
                ?: "Não consegui consultar o provedor de inteligência artificial agora, operador."
        }

        val cleanSpeech = sanitizeForSpeech(reply)
        if (cleanSpeech.isEmpty()) return

        onReplyNotification(transcript, cleanSpeech)
        onStatusUpdate("Respondendo…")
        speakReply(context, cfg, cleanSpeech)
    }

    private fun playReadyBeep() {
        var tg: ToneGenerator? = null
        try {
            tg = ToneGenerator(AudioManager.STREAM_MUSIC, 65)
            tg.startTone(ToneGenerator.TONE_PROP_BEEP, 130)
            Thread.sleep(190)
        } catch (_: Throwable) {
        } finally {
            try {
                tg?.release()
            } catch (_: Throwable) {
            }
        }
    }

    private fun captureCommandPcm(): ByteArray? {
        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE_HZ,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuf <= 0) return null
        val bufSize = max(minBuf, CHUNK_BYTES * 4)

        val candidates = listOf(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            MediaRecorder.AudioSource.MIC,
            MediaRecorder.AudioSource.DEFAULT,
        )
        var recorder: AudioRecord? = null
        for (src in candidates) {
            val candidate = try {
                AudioRecord(
                    src,
                    SAMPLE_RATE_HZ,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufSize,
                )
            } catch (_: Throwable) {
                continue
            }
            if (candidate.state != AudioRecord.STATE_INITIALIZED) {
                try {
                    candidate.release()
                } catch (_: Throwable) {
                }
                continue
            }
            try {
                candidate.startRecording()
            } catch (_: Throwable) {
                try {
                    candidate.release()
                } catch (_: Throwable) {
                }
                continue
            }
            if (candidate.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                recorder = candidate
                break
            }
            try {
                candidate.release()
            } catch (_: Throwable) {
            }
        }

        val activeRec = recorder ?: return null
        val out = ByteArrayOutputStream()
        val preRing = ArrayDeque<ByteArray>()
        val chunkBuf = ByteArray(CHUNK_BYTES)
        var speechStarted = false
        var silenceChunks = 0
        var speechChunks = 0
        var waitChunks = 0
        var noiseFloor = 220.0

        try {
            while (true) {
                if (MainActivity.isActivityResumed) return null
                val read = activeRec.read(chunkBuf, 0, CHUNK_BYTES)
                if (read <= 0) break
                val chunk = chunkBuf.copyOf(read)
                val rms = computeRmsInt16(chunk)

                if (!speechStarted) {
                    waitChunks++
                    if (waitChunks <= 2) {
                        noiseFloor = max(200.0, (noiseFloor + rms) * 0.5)
                    }
                    preRing.addLast(chunk)
                    while (preRing.size > PRE_SPEECH_CHUNKS) {
                        preRing.removeFirst()
                    }
                    val threshold = max(250.0, noiseFloor * 2.2)
                    if (rms >= threshold && waitChunks > 1) {
                        speechStarted = true
                        for (pre in preRing) {
                            out.write(pre)
                        }
                        preRing.clear()
                        speechChunks = 1
                    } else if (waitChunks >= MAX_WAIT_SPEECH_CHUNKS) {
                        return null
                    }
                } else {
                    out.write(chunk)
                    speechChunks++
                    val keepThreshold = max(180.0, noiseFloor * 1.55)
                    if (rms < keepThreshold) {
                        silenceChunks++
                        if (silenceChunks >= SILENCE_END_CHUNKS) break
                    } else {
                        silenceChunks = 0
                    }
                    if (speechChunks >= MAX_SPEECH_CHUNKS) break
                }
            }
            return if (speechStarted && out.size() > CHUNK_BYTES) out.toByteArray() else null
        } catch (_: Throwable) {
            return null
        } finally {
            try {
                activeRec.stop()
            } catch (_: Throwable) {
            }
            try {
                activeRec.release()
            } catch (_: Throwable) {
            }
        }
    }

    private fun computeRmsInt16(pcm: ByteArray): Double {
        val count = pcm.size / 2
        if (count <= 0) return 0.0
        var sumSq = 0.0
        var i = 0
        while (i + 1 < pcm.size) {
            val lo = pcm[i].toInt() and 0xFF
            val hi = pcm[i + 1].toInt()
            val sample = (hi shl 8) or lo
            sumSq += sample.toDouble() * sample.toDouble()
            i += 2
        }
        return sqrt(sumSq / count)
    }

    private fun buildWav(pcm: ByteArray, sampleRate: Int): ByteArray {
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        val byteRate = sampleRate * 2
        header.put("RIFF".toByteArray(Charsets.US_ASCII))
        header.putInt(36 + pcm.size)
        header.put("WAVE".toByteArray(Charsets.US_ASCII))
        header.put("fmt ".toByteArray(Charsets.US_ASCII))
        header.putInt(16)
        header.putShort(1.toShort())
        header.putShort(1.toShort())
        header.putInt(sampleRate)
        header.putInt(byteRate)
        header.putShort(2.toShort())
        header.putShort(16.toShort())
        header.put("data".toByteArray(Charsets.US_ASCII))
        header.putInt(pcm.size)
        val out = ByteArray(44 + pcm.size)
        System.arraycopy(header.array(), 0, out, 0, 44)
        System.arraycopy(pcm, 0, out, 44, pcm.size)
        return out
    }

    private fun transcribeWhisper(cfg: BackgroundVoiceConfig, wav: ByteArray): String? {
        val boundary = "----UltronVoice${System.currentTimeMillis()}"
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(cfg.sttUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 15_000
                readTimeout = 20_000
                doOutput = true
                setRequestProperty("Authorization", "Bearer ${cfg.sttKey}")
                setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
            }
            DataOutputStream(conn.outputStream).use { out ->
                fun writeField(name: String, value: String) {
                    out.writeBytes("--$boundary\r\n")
                    out.writeBytes("Content-Disposition: form-data; name=\"$name\"\r\n\r\n")
                    out.write(value.toByteArray(Charsets.UTF_8))
                    out.writeBytes("\r\n")
                }
                writeField("model", cfg.sttModel)
                if (cfg.sttLanguage.isNotBlank()) {
                    writeField("language", cfg.sttLanguage)
                }
                writeField("response_format", "json")
                out.writeBytes("--$boundary\r\n")
                out.writeBytes("Content-Disposition: form-data; name=\"file\"; filename=\"command.wav\"\r\n")
                out.writeBytes("Content-Type: audio/wav\r\n\r\n")
                out.write(wav)
                out.writeBytes("\r\n--$boundary--\r\n")
                out.flush()
            }
            if (conn.responseCode !in 200..299) return null
            val body = conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            JSONObject(body).optString("text", "").trim()
        } catch (_: Throwable) {
            null
        } finally {
            conn?.disconnect()
        }
    }

    private fun tryLocalSafeAction(context: Context, transcript: String): String? {
        val lower = transcript.lowercase(Locale("pt", "BR"))
        if (lower.contains("que horas") || lower.contains("horário") || lower.contains("hora atual")) {
            val now = SimpleDateFormat("HH:mm", Locale("pt", "BR")).format(Date())
            return "Operador, agora são $now."
        }
        if (lower.contains("que dia") || lower.contains("qual a data") || lower.contains("data de hoje")) {
            val today = SimpleDateFormat("dd 'de' MMMM", Locale("pt", "BR")).format(Date())
            return "Hoje é dia $today, operador."
        }
        val mediaKey = when {
            lower.contains("pausar") || lower.contains("pause") || lower.contains("parar música") ->
                KeyEvent.KEYCODE_MEDIA_PAUSE
            lower.contains("tocar") || lower.contains("continuar música") || lower.contains("play") ->
                KeyEvent.KEYCODE_MEDIA_PLAY
            lower.contains("próxima") || lower.contains("pular música") ->
                KeyEvent.KEYCODE_MEDIA_NEXT
            lower.contains("anterior") || lower.contains("voltar música") ->
                KeyEvent.KEYCODE_MEDIA_PREVIOUS
            else -> null
        }
        if (mediaKey != null) {
            try {
                val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val t = SystemClock.uptimeMillis()
                am.dispatchMediaKeyEvent(KeyEvent(t, t, KeyEvent.ACTION_DOWN, mediaKey, 0))
                am.dispatchMediaKeyEvent(KeyEvent(t, t, KeyEvent.ACTION_UP, mediaKey, 0))
                return "Controle de mídia executado, operador."
            } catch (_: Throwable) {
            }
        }
        return null
    }

    private fun queryAi(cfg: BackgroundVoiceConfig, userPrompt: String): String? {
        val base = cfg.aiBaseUrl.trim().trimEnd('/')
        val chatUrl = if (base.endsWith("/chat/completions")) base else "$base/chat/completions"
        var conn: HttpURLConnection? = null
        return try {
            val payload = JSONObject().apply {
                put("model", cfg.aiModel.ifBlank { "openai" })
                put("temperature", 0.4)
                put("max_tokens", 220)
                put(
                    "messages",
                    JSONArray().apply {
                        put(
                            JSONObject().apply {
                                put("role", "system")
                                put(
                                    "content",
                                    "Você é o U.L.T.R.O.N., assistente de voz em português do Brasil. " +
                                        "Responda em modo mãos-livres com o aplicativo em segundo plano, em no máximo 2 ou 3 frases diretas, sem markdown ou emojis. " +
                                        "Se o usuário pedir ações sensíveis (enviar WhatsApp/SMS, apagar histórico, desligar PC ou acessar dados privados), peça para abrir e desbloquear o U.L.T.R.O.N.",
                                )
                            },
                        )
                        put(
                            JSONObject().apply {
                                put("role", "user")
                                put("content", userPrompt)
                            },
                        )
                    },
                )
            }.toString()

            conn = (URL(chatUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 15_000
                readTimeout = 25_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                if (cfg.aiKey.isNotBlank()) {
                    setRequestProperty("Authorization", "Bearer ${cfg.aiKey}")
                }
            }
            conn.outputStream.use { it.write(payload.toByteArray(Charsets.UTF_8)) }
            if (conn.responseCode !in 200..299) return null
            val raw = conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            val choices = JSONObject(raw).optJSONArray("choices") ?: return null
            if (choices.length() == 0) return null
            choices.getJSONObject(0)
                .optJSONObject("message")
                ?.optString("content", "")
                ?.trim()
        } catch (_: Throwable) {
            null
        } finally {
            conn?.disconnect()
        }
    }

    private fun sanitizeForSpeech(text: String): String {
        return text
            .replace(Regex("\\[(?:ACTION|Hardware)[^\\]]*\\]", RegexOption.IGNORE_CASE), " ")
            .replace(Regex("[*_`#>]"), " ")
            .replace(Regex("\\s{2,}"), " ")
            .trim()
    }

    private fun speakReply(context: Context, cfg: BackgroundVoiceConfig, reply: String) {
        if (cfg.hasFish) {
            val mp3 = synthesizeFishAudio(cfg, reply)
            if (mp3 != null && mp3.isNotEmpty()) {
                val vol = if (cfg.whisperMode) 0.28f else 1.0f
                val played = UltronTtsHelper.playAudioBytesBlocking(context, mp3, vol)
                if (played) return
            }
        }
        UltronTtsHelper.speakBlocking(context, reply)
    }

    private fun synthesizeFishAudio(cfg: BackgroundVoiceConfig, text: String): ByteArray? {
        var conn: HttpURLConnection? = null
        return try {
            val body = JSONObject().apply {
                put("text", text)
                put("reference_id", cfg.fishRefId)
                put("format", "mp3")
                if (cfg.fishLanguage.isNotBlank() && !cfg.fishLanguage.equals("auto", ignoreCase = true)) {
                    put("language", cfg.fishLanguage)
                }
            }.toString()
            conn = (URL("https://api.fish.audio/v1/tts").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 15_000
                readTimeout = 20_000
                doOutput = true
                setRequestProperty("Authorization", "Bearer ${cfg.fishKey}")
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                setRequestProperty("model", cfg.fishModel.ifBlank { "s2.1-pro" })
            }
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            if (conn.responseCode !in 200..299) return null
            conn.inputStream.use { it.readBytes() }
        } catch (_: Throwable) {
            null
        } finally {
            conn?.disconnect()
        }
    }
}
