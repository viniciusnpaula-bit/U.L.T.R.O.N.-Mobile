package com.viniciusnpaula.ultron_mobile

import android.app.KeyguardManager
import android.content.Context
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.ToneGenerator
import android.net.Uri
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
 * microfone nativo AudioRecord -> STT não-Google (Groq/Whisper) -> ações locais ou IA + [ACTION:...] ->
 * grava no histórico criptografado -> Fish Audio API (ou TTS offline Android).
 */
object BackgroundVoiceResponder {
    private const val SAMPLE_RATE_HZ = 16000
    private const val CHUNK_SAMPLES = 1600 // 100 ms
    private const val CHUNK_BYTES = CHUNK_SAMPLES * 2
    private const val MAX_WAIT_SPEECH_CHUNKS = 75 // 7.5 s esperando começar a falar
    private const val SILENCE_END_CHUNKS = 7 // 0.7 s de silêncio encerra comando
    private const val MAX_SPEECH_CHUNKS = 100 // 10 s máx. por turno
    private const val PRE_SPEECH_CHUNKS = 4 // 400 ms pré-fala

    private data class BackgroundTurnResult(
        val speakText: String,
        val displayText: String,
        val senderLabel: String,
    )

    @JvmOverloads
    fun runBackgroundTurn(
        context: Context,
        onStatusUpdate: (String) -> Unit,
        onReplyNotification: (String, String) -> Unit,
        onRequireUnlock: (() -> Unit)? = null,
    ) {
        val cfg = BackgroundVoiceConfigStore.load(context)

        try {
            playReadyBeep()
            FloatingOrbService.updateState(OrbState.LISTENING)
            onStatusUpdate("Ouvindo comando em segundo plano…")

            val pcm = captureCommandPcm()
            if (pcm == null || pcm.isEmpty()) {
                return
            }

            if (!cfg.hasStt) {
                val msg = "Operador, configure uma chave Groq nas configurações de IA para comandos em segundo plano."
                onReplyNotification("Chave STT necessária", msg)
                FloatingOrbService.updateState(OrbState.SPEAKING)
                UltronTtsHelper.speakBlocking(context, msg)
                return
            }

            FloatingOrbService.updateState(OrbState.PROCESSING)
            onStatusUpdate("Transcrevendo comando…")
            val wav = buildWav(pcm, SAMPLE_RATE_HZ)
            val transcript = transcribeWhisper(cfg, wav)?.trim().orEmpty()
            if (transcript.length < 2) {
                return
            }

            val userTs = System.currentTimeMillis()
            val result = tryLocalAction(context, transcript) ?: run {
                FloatingOrbService.updateState(OrbState.PROCESSING)
                onStatusUpdate("Consultando U.L.T.R.O.N…")
                val rawReply = queryAi(context, cfg, transcript)
                if (rawReply.isNullOrBlank()) {
                    val fallback = "Não consegui consultar o provedor de inteligência artificial agora, operador."
                    BackgroundTurnResult(
                        speakText = fallback,
                        displayText = fallback,
                        senderLabel = "U.L.T.R.O.N. (2º plano)",
                    )
                } else {
                    executeAiActionTags(context, rawReply, cfg.aiModel, onRequireUnlock)
                }
            }

            val cleanSpeech = sanitizeForSpeech(result.speakText)
            val replyTs = System.currentTimeMillis()
            if (result.displayText.isNotBlank()) {
                BackgroundChatStore.enqueueTurn(
                    context,
                    BackgroundChatTurn(
                        userText = transcript,
                        assistantText = result.displayText,
                        senderLabel = result.senderLabel,
                        userTimestampMs = userTs,
                        replyTimestampMs = replyTs,
                    ),
                )
                MainActivity.notifyBackgroundTurn()
            }

            if (cleanSpeech.isEmpty()) return

            onReplyNotification(transcript, cleanSpeech)
            FloatingOrbService.updateState(OrbState.SPEAKING)
            onStatusUpdate("Respondendo…")
            speakReply(context, cfg, cleanSpeech)
        } finally {
            FloatingOrbService.updateState(OrbState.IDLE)
        }
    }

    private fun playReadyBeep() {
        var tg: ToneGenerator? = null
        try {
            tg = ToneGenerator(AudioManager.STREAM_MUSIC, 65)
            tg.startTone(ToneGenerator.TONE_PROP_BEEP, 80)
            Thread.sleep(95)
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
                    if (waitChunks == 1 && rms < 450.0) {
                        noiseFloor = max(180.0, rms)
                    }
                    preRing.addLast(chunk)
                    while (preRing.size > PRE_SPEECH_CHUNKS) {
                        preRing.removeFirst()
                    }
                    val threshold = max(240.0, noiseFloor * 2.1)
                    if (rms >= threshold) {
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

    private fun isDeviceLocked(context: Context): Boolean {
        val km = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        return km?.isDeviceLocked == true
    }

    private fun stripConversationalFillers(text: String): String {
        var current = text.trim()
            .trimEnd('.', '!', '?', ',', ';', ':')
            .trim()
        val leadingPatterns = listOf(
            Regex("""^(?:(?:ei|oi|ol[aá]|ok|e\s*a[ií]|fala)\s+)?(?:ultron|jarvis|edith|edite|vis[aã]o|viz[aã]o|vision)[,\s]+""", RegexOption.IGNORE_CASE),
            Regex("""^(?:por\s+favor|pfv|por\s+gentileza)[,\s]+""", RegexOption.IGNORE_CASE),
            Regex("""^(?:voc[eê]|vc)\s+(?:pode|poderia|consegue)\s+""", RegexOption.IGNORE_CASE),
            Regex("""^(?:pode|poderia|consegue|tem\s+como|faz\s+o\s+favor\s+de|quero\s+que(?:\s+voc[eê]|\s+vc)?)\s+""", RegexOption.IGNORE_CASE),
        )
        val trailingPattern = Regex(
            """(?:\s+(?:para\s+mim|pra\s+mim|por\s+favor|por\s+gentileza|pfv|aqui|a[ií]|agora|r[aá]pido|logo|se\s+puder|se\s+conseguir|por\s+obs[eé]quio|ok|t[aá]|viu|ultron|jarvis|edith|vis[aã]o))+$""",
            RegexOption.IGNORE_CASE,
        )
        var prev: String
        do {
            prev = current
            for (p in leadingPatterns) {
                current = p.replace(current, "").trim()
            }
            current = trailingPattern.replace(current, "").trim()
        } while (current != prev && current.isNotEmpty())
        if (WakeWordMatcher.hotwordIndex(current, anyProfile = true) == 0) {
            current = WakeWordMatcher.extractCommand(current, anyProfile = true)
        }
        return current
    }

    private fun tryLocalAction(context: Context, rawTranscript: String): BackgroundTurnResult? {
        val clean = stripConversationalFillers(rawTranscript)
        if (clean.isEmpty()) return null
        val lower = clean.lowercase(Locale("pt", "BR"))

        // Frases compostas / multi-intenção ("abra o whatsapp e veja...", "liga a lanterna depois...")
        // vão direto para a IA interpretar o pedido completo com todas as ações juntas.
        val hasMultiClause = Regex(
            """\b(?:e\s+(?:tamb[eé]m|depois|j[aá]|me|liga|desliga|abre|abra|aumenta|diminui|abaixa|pausa|toca|coloca|bota|manda|envia|v[eê]|veja|leia)|ent[aã]o|mas\s|antes\s+de|depois\s+de)\b""",
        ).containsMatchIn(lower)
        if (hasMultiClause) return null

        fun actionTurn(speak: String, log: String): BackgroundTurnResult = BackgroundTurnResult(
            speakText = speak,
            displayText = "$speak\n\n[Hardware: $log]",
            senderLabel = "Hardware Bridge (2º plano)",
        )

        // 1. Horas / Data
        if (lower.contains("que horas") || lower.contains("horário") || lower.contains("hora atual")) {
            val now = SimpleDateFormat("HH:mm", Locale("pt", "BR")).format(Date())
            val speak = "Operador, agora são $now."
            return BackgroundTurnResult(speak, speak, "U.L.T.R.O.N. (2º plano)")
        }
        if (lower.contains("que dia") || lower.contains("qual a data") || lower.contains("data de hoje")) {
            val today = SimpleDateFormat("dd 'de' MMMM", Locale("pt", "BR")).format(Date())
            val speak = "Hoje é dia $today, operador."
            return BackgroundTurnResult(speak, speak, "U.L.T.R.O.N. (2º plano)")
        }

        // 2. Lanterna
        if (Regex("""\b(ligar|acender|ativar|liga|acende|ativa)\b.*\b(lanterna|flash|luz)\b|\b(lanterna|flash)\s+(on|ligar|acesa)\b""").containsMatchIn(lower)) {
            return try {
                val on = DeviceHardwareHelper.setTorch(context, true)
                actionTurn("Lanterna ligada.", "🔦 Lanterna: ${if (on) "ON" else "OFF"}")
            } catch (e: Throwable) {
                actionTurn("Não consegui ligar a lanterna.", "⚠️ Lanterna: ${e.message}")
            }
        }
        if (Regex("""\b(desligar|apagar|desativar|desliga|apaga|desativa)\b.*\b(lanterna|flash|luz)\b|\b(lanterna|flash)\s+(off|desligar|apagada)\b""").containsMatchIn(lower)) {
            return try {
                val on = DeviceHardwareHelper.setTorch(context, false)
                actionTurn("Lanterna desligada.", "🔦 Lanterna: ${if (on) "ON" else "OFF"}")
            } catch (e: Throwable) {
                actionTurn("Não consegui desligar a lanterna.", "⚠️ Lanterna: ${e.message}")
            }
        }
        if (lower == "lanterna" || lower == "alternar lanterna" || lower == "flash") {
            return try {
                val on = DeviceHardwareHelper.toggleTorch(context)
                actionTurn(if (on) "Lanterna ligada." else "Lanterna desligada.", "🔦 Lanterna: ${if (on) "ON" else "OFF"}")
            } catch (e: Throwable) {
                actionTurn("Não consegui alternar a lanterna.", "⚠️ Lanterna: ${e.message}")
            }
        }

        // 3. Volume
        Regex("""\bvolume\s*(?:em|para|no|na|a)?\s*(\d{1,3})\s*%?""").find(lower)?.let { m ->
            val target = (m.groupValues[1].toIntOrNull() ?: 50).coerceIn(0, 100)
            val updated = DeviceHardwareHelper.setMediaVolumePercent(context, target, showUi = true)
            return actionTurn("Volume em $updated por cento.", "🔊 Volume: $updated%")
        }
        if (Regex("""\b(aumentar|subir|aumenta|sobe|mais)\s+(?:o\s+)?volume\b""").containsMatchIn(lower)) {
            val updated = DeviceHardwareHelper.adjustMediaVolume(context, "up", showUi = true)
            return actionTurn("Volume aumentado para $updated por cento.", "🔊 Volume: $updated%")
        }
        if (Regex("""\b(diminuir|abaixar|baixar|reduzir|diminui|abaixa|baixa|menos)\s+(?:o\s+)?volume\b""").containsMatchIn(lower)) {
            val updated = DeviceHardwareHelper.adjustMediaVolume(context, "down", showUi = true)
            return actionTurn("Volume reduzido para $updated por cento.", "🔉 Volume: $updated%")
        }
        if (Regex("""\b(silenciar|mutar|mudo|deixar no mudo|tirar o som)\b""").containsMatchIn(lower)) {
            DeviceHardwareHelper.adjustMediaVolume(context, "mute", showUi = true)
            return actionTurn("Áudio silenciado.", "🔇 Áudio silenciado")
        }
        if (Regex("""\b(desmutar|ativar o som|ligar o som|tirar do mudo)\b""").containsMatchIn(lower)) {
            val updated = DeviceHardwareHelper.adjustMediaVolume(context, "unmute", showUi = true)
            return actionTurn("Som reativado em $updated por cento.", "🔊 Volume: $updated%")
        }

        // 4. Controle de Mídia
        val mediaAction = when {
            Regex("""\b(pr[oó]xima|avan[cç]ar|pular)\s+(?:a\s+)?(?:m[uú]sica|faixa|v[ií]deo|m[ií]dia)\b|^(?:pr[oó]xima|pular)$""").containsMatchIn(lower) ->
                Triple("next", "Próxima faixa.", "⏭️ Próxima faixa")
            Regex("""\b(?:m[uú]sica|faixa|v[ií]deo)\s+anterior\b|\bvoltar\s+(?:a\s+)?(?:m[uú]sica|faixa)\b""").containsMatchIn(lower) ->
                Triple("previous", "Faixa anterior.", "⏮️ Faixa anterior")
            Regex("""\b(pausar|pausa)\s+(?:a\s+)?(?:m[uú]sica|m[ií]dia|reprodu[cç][aã]o|v[ií]deo|spotify|player)\b|^(?:pausar|pausa|parar\s+m[uú]sica)$""").containsMatchIn(lower) ->
                Triple("pause", "Mídia pausada.", "⏸️ Mídia pausada")
            Regex("""\b(tocar|reproduzir|continuar|retomar|dar\s+play|play\s+na)\s+(?:a\s+)?(?:m[uú]sica|m[ií]dia|reprodu[cç][aã]o|v[ií]deo|spotify|player)\b|^(?:dar\s+)?play$|^(?:retomar|continuar)\s+m[uú]sica$""").containsMatchIn(lower) ->
                Triple("play", "Reproduzindo mídia.", "▶️ Reprodução retomada")
            else -> null
        }
        if (mediaAction != null) {
            val prefApp = when {
                lower.contains("spotify") -> "spotify"
                lower.contains("youtube") -> "youtube"
                else -> ""
            }
            val mediaRes = DeviceHardwareHelper.dispatchMediaControlVerified(
                context,
                mediaAction.first,
                prefApp,
            )
            return when (mediaRes.status) {
                "confirmed" -> if (mediaRes.launchedApp.isNotEmpty()) {
                    actionTurn(
                        "Abri o ${mediaRes.launchedApp} e retomei a reprodução.",
                        "▶️ ${mediaRes.launchedApp} aberto e tocando",
                    )
                } else {
                    actionTurn(mediaAction.second, mediaAction.third)
                }
                "opened_needs_play" -> {
                    val appName = mediaRes.launchedApp.ifEmpty { "aplicativo de música" }
                    actionTurn(
                        "O $appName estava fechado, então abri o aplicativo para você. Toque em play para continuar.",
                        "📱 $appName aberto (aguardando play)",
                    )
                }
                "no_active_session" -> {
                    val appHint = if (prefApp.isNotEmpty()) prefApp.replaceFirstChar { it.uppercase() } else "player de mídia"
                    actionTurn(
                        "Não há nenhuma reprodução ativa no $appHint.",
                        "⚠️ Sem sessão de mídia ativa ($appHint)",
                    )
                }
                else -> actionTurn(
                    "Enviei o comando de mídia, mas não consegui confirmar se o player respondeu.",
                    "❔ Comando de mídia enviado (efeito não confirmado)",
                )
            }
        }

        // 5. Bateria e status do aparelho
        if (Regex("""\b(bateria|quanta bateria|status do celular|status do sistema|mem[oó]ria ram)\b""").containsMatchIn(lower)) {
            val st = DeviceHardwareHelper.readDeviceStatus(context)
            val bat = st["batteryLevel"] as? Int ?: -1
            val charging = if (st["isCharging"] == true) " carregando" else ""
            val ramFree = st["ramFreeMb"] as? Int ?: 0
            val vol = st["volumePercent"] as? Int ?: 0
            val speak = "Bateria em $bat por cento$charging, volume em $vol por cento e $ramFree megabytes de RAM livres."
            return actionTurn(speak, "📊 Bateria: $bat% • RAM livre: $ramFree MB")
        }

        // 6. Vibração
        if (lower == "vibrar" || lower == "testar vibração" || lower == "vibracao") {
            DeviceHardwareHelper.triggerVibration(context, 350L)
            return actionTurn("Vibrando dispositivo.", "📳 Vibração executada")
        }

        // 7. Alarme e Timer
        Regex("""\b(?:alarme|despertador)\s+(?:para\s+|às\s+|as\s+)?(\d{1,2})[:h](\d{2})\b""").find(lower)?.let { m ->
            val h = (m.groupValues[1].toIntOrNull() ?: 7).coerceIn(0, 23)
            val min = (m.groupValues[2].toIntOrNull() ?: 0).coerceIn(0, 59)
            DeviceHardwareHelper.setAlarm(context, h, min, "U.L.T.R.O.N.", skipUi = true)
            val hh = h.toString().padStart(2, '0')
            val mm = min.toString().padStart(2, '0')
            return actionTurn("Alarme definido para $hh horas e $mm minutos.", "⏰ Alarme $hh:$mm")
        }
        Regex("""\b(?:timer|temporizador|cron[oô]metro)\s+(?:de\s+)?(\d+)\s*(seg|segundo|segundos|s|min|minuto|minutos|m)?\b""").find(lower)?.let { m ->
            val amount = (m.groupValues[1].toIntOrNull() ?: 1).coerceAtLeast(1)
            val unit = m.groupValues[2].ifBlank { "m" }
            val isSec = unit.startsWith("s")
            val secs = if (isSec) amount else amount * 60
            DeviceHardwareHelper.setTimer(context, secs, "U.L.T.R.O.N. Timer", skipUi = true)
            val unitLabel = if (isSec) "segundos" else "minutos"
            return actionTurn("Timer de $amount $unitLabel iniciado.", "⏱️ Timer (${secs}s)")
        }

        // 8. Nota rápida / Inbox Obsidian
        Regex("""^(?:ultron[,\s]+)?(?:anote|anotar|nota\s+r[aá]pida|salvar\s+nota)[:\s]+(.+)$""").find(clean)?.let { m ->
            val body = m.groupValues[1].trim()
            if (body.isNotEmpty()) {
                val fname = DeviceHardwareHelper.appendObsidianEntry(context, "Diario", "", body)
                val log = if (fname != null) "📝 Nota salva ($fname)" else "📝 Nota registrada"
                return actionTurn("Nota registrada no seu cofre.", log)
            }
        }
        Regex("""^(?:capturar\s+ideia|anotar\s+ideia|ideia|inbox)[:\s]+(.+)$""", RegexOption.IGNORE_CASE).find(clean)?.let { m ->
            val body = m.groupValues[1].trim()
            if (body.isNotEmpty()) {
                val fname = DeviceHardwareHelper.appendObsidianEntry(context, "Inbox", "", body)
                val log = if (fname != null) "💡 Ideia salva ($fname)" else "💡 Ideia registrada"
                return actionTurn("Ideia salva no Inbox do seu segundo cérebro.", log)
            }
        }

        // 9. Pesquisa Web
        Regex("""^(?:pesquisar|buscar na web|procurar no google)\s+(.+)$""", RegexOption.IGNORE_CASE).find(clean)?.let { m ->
            val q = m.groupValues[1].trim()
            if (q.isNotEmpty()) {
                DeviceHardwareHelper.openUrl(context, "https://www.google.com/search?q=${Uri.encode(q)}")
                return actionTurn("Pesquisando $q.", "🌐 Busca: $q")
            }
        }

        // 10. Abrir aplicativos e configurações (se não achar app literal, deixa a IA entender o contexto)
        Regex("""^(?:(?:ei|ok|oi)\s+)?(?:ultron\s*[,\s]+)?(?:(?:aqui\s+)?no\s+(?:meu\s+)?celular\s*[,\s]+)?(?:(?:por\s+favor|pfv|pode|poderia|quero)\s+)*(?:abrir|iniciar|abre|abra|executar)\s+(.+)$""").find(lower)?.let { m ->
            val target = DeviceHardwareHelper.sanitizeAppQuery(m.groupValues[1])
            val wordCount = target.split(Regex("""\s+""")).count { it.isNotBlank() }
            if (target.isNotEmpty() && wordCount <= 3 && target != "palco" && target != "documento") {
                try {
                    val launch = DeviceHardwareHelper.launchInstalledAppWithStatus(context, target)
                    return if (launch.openedImmediately) {
                        actionTurn("Abrindo ${launch.label}.", "📱 App aberto: ${launch.label}")
                    } else {
                        actionTurn(
                            "Permissão Aparecer sobre outros apps necessária para abrir ${launch.label} em segundo plano. Deixei o atalho na notificação.",
                            "🔒 Permissão 'Aparecer sobre outros apps' pendente para abrir ${launch.label}",
                        )
                    }
                } catch (_: Throwable) {
                    // Cai para a IA responder ou escolher a melhor ação com base no contexto.
                }
            }
        }

        return null
    }

    private fun queryAi(context: Context, cfg: BackgroundVoiceConfig, userPrompt: String): String? {
        val base = cfg.aiBaseUrl.trim().trimEnd('/')
        val chatUrl = if (base.endsWith("/chat/completions")) base else "$base/chat/completions"
        var conn: HttpURLConnection? = null
        return try {
            val status = DeviceHardwareHelper.readDeviceStatus(context)
            val bat = status["batteryLevel"] as? Int ?: -1
            val charging = if (status["isCharging"] == true) "carregando" else "bateria"
            val torch = if (status["torchOn"] == true) "LIGADA" else "DESLIGADA"
            val vol = status["volumePercent"] as? Int ?: 0
            val locked = isDeviceLocked(context)
            val appsSample = DeviceHardwareHelper.listInstalledAppSample(context, 30)
            val appsHint = if (appsSample.isNotEmpty()) {
                " | Apps instalados: ${appsSample.joinToString(", ")}"
            } else {
                ""
            }

            val nowFmt = SimpleDateFormat("yyyy-MM-dd (EEEE) HH:mm:ss Z", Locale("pt", "BR")).format(Date())
            val systemPrompt = "Você é o U.L.T.R.O.N., assistente pessoal tático Android em português do Brasil, respondendo em 2º plano (mãos-livres). " +
                "Entenda linguagem natural, pedidos indiretos, gírias, ordens compostas e o contexto das mensagens anteriores da conversa. " +
                "Responda de forma natural em no máximo 2 ou 3 frases diretas, sem markdown ou emojis. " +
                "DATA/HORA ATUAL DO CELULAR: $nowFmt (use este horário real para calcular alarmes relativos, timers e datas sem perguntar a hora ao operador). " +
                "TELEMETRIA: Bateria $bat% ($charging) | Lanterna $torch | Volume $vol% | Tela ${if (locked) "BLOQUEADA" else "DESBLOQUEADA"}$appsHint. " +
                "Sempre que o operador pedir ou sugerir uma ação (mesmo de forma indireta, ex: 'tá escuro' -> ligar lanterna), inclua as tags exatas no final: " +
                "[ACTION:TORCH_ON], [ACTION:TORCH_OFF], [ACTION:TORCH_TOGGLE], " +
                "[ACTION:VOLUME_SET:N], [ACTION:VOLUME_UP], [ACTION:VOLUME_DOWN], [ACTION:VOLUME_MUTE], " +
                "[ACTION:MEDIA_PLAY], [ACTION:MEDIA_PAUSE], [ACTION:MEDIA_PLAY_PAUSE], [ACTION:MEDIA_NEXT], [ACTION:MEDIA_PREVIOUS], [ACTION:MEDIA_STOP], " +
                "[ACTION:OPEN_CAMERA], [ACTION:OPEN_APP:nome], [ACTION:OPEN_SETTINGS:wifi|bluetooth|display|sound|general], " +
                "[ACTION:ALARM:HH:MM:Motivo], [ACTION:TIMER:SEGUNDOS:Motivo], [ACTION:VIBRATE], [ACTION:SEARCH:termo], " +
                "[ACTION:NOTE:texto], [ACTION:INBOX:texto], [ACTION:READ_MESSAGES], [ACTION:REPLY_MESSAGE:contato:texto]. " +
                "Ações sensíveis (ler/responder notificações, enviar WhatsApp/SMS, desligar PC) exigem tela desbloqueada."

            val messages = JSONArray().apply {
                put(JSONObject().apply {
                    put("role", "system")
                    put("content", systemPrompt)
                })
                for ((pastUser, pastAssistant) in BackgroundChatStore.recentHistoryPairs(context)) {
                    put(JSONObject().apply {
                        put("role", "user")
                        put("content", pastUser)
                    })
                    put(JSONObject().apply {
                        put("role", "assistant")
                        put("content", pastAssistant)
                    })
                }
                put(JSONObject().apply {
                    put("role", "user")
                    put("content", userPrompt)
                })
            }

            val payload = JSONObject().apply {
                put("model", cfg.aiModel.ifBlank { "openai" })
                put("temperature", 0.4)
                put("max_tokens", 320)
                put("messages", messages)
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

    private fun executeAiActionTags(
        context: Context,
        rawReply: String,
        aiModel: String,
        onRequireUnlock: (() -> Unit)? = null,
    ): BackgroundTurnResult {
        val pattern = Regex("""\[ACTION:([^\]]+)\]""", RegexOption.IGNORE_CASE)
        val matches = pattern.findAll(rawReply).toList()
        val logs = mutableListOf<String>()
        val locked = isDeviceLocked(context) || FloatingOrbService.isSessionLocked
        var requestedUnlock = false

        for (match in matches) {
            val content = match.groupValues[1].trim()
            val parts = content.split(':')
            val cmd = parts.firstOrNull()?.trim()?.uppercase().orEmpty()
            val arg1 = parts.getOrNull(1)?.trim().orEmpty()
            val arg2 = parts.getOrNull(2)?.trim().orEmpty()
            val arg3 = if (parts.size > 3) parts.drop(3).joinToString(":").trim() else ""

            if (FloatingOrbService.requiresUnlockForBackgroundAction(context, cmd)) {
                logs.add("🔒 Desbloqueio AuthGate exigido para $cmd")
                if (!requestedUnlock) {
                    requestedUnlock = true
                    onRequireUnlock?.invoke()
                }
                continue
            }

            try {
                when (cmd) {
                    "TORCH_ON" -> {
                        DeviceHardwareHelper.setTorch(context, true)
                        logs.add("🔦 Lanterna ligada")
                    }
                    "TORCH_OFF" -> {
                        DeviceHardwareHelper.setTorch(context, false)
                        logs.add("🔦 Lanterna desligada")
                    }
                    "TORCH_TOGGLE" -> {
                        val on = DeviceHardwareHelper.toggleTorch(context)
                        logs.add("🔦 Lanterna: ${if (on) "ON" else "OFF"}")
                    }
                    "VOLUME_SET" -> {
                        val updated = DeviceHardwareHelper.setMediaVolumePercent(context, arg1.toIntOrNull() ?: 50)
                        logs.add("🔊 Volume: $updated%")
                    }
                    "VOLUME_UP" -> {
                        val updated = DeviceHardwareHelper.adjustMediaVolume(context, "up")
                        logs.add("🔊 Volume: $updated%")
                    }
                    "VOLUME_DOWN" -> {
                        val updated = DeviceHardwareHelper.adjustMediaVolume(context, "down")
                        logs.add("🔉 Volume: $updated%")
                    }
                    "VOLUME_MUTE" -> {
                        DeviceHardwareHelper.adjustMediaVolume(context, "mute")
                        logs.add("🔇 Áudio silenciado")
                    }
                    "MEDIA_PLAY", "MEDIA_PAUSE", "MEDIA_PLAY_PAUSE", "MEDIA_NEXT", "MEDIA_PREVIOUS", "MEDIA_STOP" -> {
                        val actionName = when (cmd) {
                            "MEDIA_PLAY" -> "play"
                            "MEDIA_PAUSE" -> "pause"
                            "MEDIA_PLAY_PAUSE" -> "play_pause"
                            "MEDIA_NEXT" -> "next"
                            "MEDIA_PREVIOUS" -> "previous"
                            else -> "stop"
                        }
                        val okLabel = when (cmd) {
                            "MEDIA_PLAY" -> "▶️ Reprodução retomada"
                            "MEDIA_PAUSE" -> "⏸️ Mídia pausada"
                            "MEDIA_PLAY_PAUSE" -> "⏯️ Play/Pause confirmado"
                            "MEDIA_NEXT" -> "⏭️ Próxima faixa"
                            "MEDIA_PREVIOUS" -> "⏮️ Faixa anterior"
                            else -> "⏹️ Mídia parada"
                        }
                        val mRes = DeviceHardwareHelper.dispatchMediaControlVerified(context, actionName)
                        logs.add(
                            when (mRes.status) {
                                "confirmed" -> if (mRes.launchedApp.isNotEmpty()) {
                                    "▶️ ${mRes.launchedApp} aberto e reprodução retomada"
                                } else {
                                    okLabel
                                }
                                "opened_needs_play" -> "📱 ${mRes.launchedApp.ifEmpty { "Player" }} estava fechado e foi aberto (aguardando play)"
                                "no_active_session" -> "⚠️ Sem player/sessão de mídia ativa (ação não concluída)"
                                else -> "❔ Comando de mídia enviado (não confirmado)"
                            }
                        )
                    }
                    "OPEN_CAMERA" -> {
                        val res = DeviceHardwareHelper.launchInstalledAppWithStatus(context, "camera")
                        logs.add(if (res.openedImmediately) "📷 Câmera aberta" else "🔒 Atalho Câmera na notificação (sem permissão sobrepor apps)")
                    }
                    "OPEN_APP" -> if (arg1.isNotEmpty()) {
                        val res = DeviceHardwareHelper.launchInstalledAppWithStatus(context, arg1)
                        logs.add(
                            if (res.openedImmediately) "📱 App aberto: ${res.label}"
                            else "🔒 Atalho ${res.label} na notificação (ative Aparecer sobre outros apps)"
                        )
                    }
                    "OPEN_SETTINGS" -> {
                        val target = arg1.ifEmpty { "general" }
                        val ok = DeviceHardwareHelper.openSettingsPanel(context, target)
                        logs.add(if (ok) "⚙️ Configurações abertas ($target)" else "🔒 Atalho Configurações na notificação")
                    }
                    "ALARM" -> {
                        val h = (arg1.toIntOrNull() ?: 7).coerceIn(0, 23)
                        val m = (arg2.toIntOrNull() ?: 0).coerceIn(0, 59)
                        DeviceHardwareHelper.setAlarm(context, h, m, arg3.ifEmpty { "U.L.T.R.O.N." }, skipUi = true)
                        logs.add("⏰ Alarme ${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}")
                    }
                    "TIMER" -> {
                        val secs = (arg1.toIntOrNull() ?: 60).coerceAtLeast(1)
                        DeviceHardwareHelper.setTimer(context, secs, arg2.ifEmpty { "U.L.T.R.O.N. Timer" }, skipUi = true)
                        logs.add("⏱️ Timer (${secs}s)")
                    }
                    "VIBRATE" -> {
                        DeviceHardwareHelper.triggerVibration(context, 280L)
                        logs.add("📳 Vibração")
                    }
                    "SEARCH" -> {
                        val q = parts.drop(1).joinToString(":").trim()
                        if (q.isNotEmpty()) {
                            DeviceHardwareHelper.openUrl(context, "https://www.google.com/search?q=${Uri.encode(q)}")
                            logs.add("🌐 Busca: $q")
                        }
                    }
                    "NOTE" -> {
                        val body = parts.drop(1).joinToString(":").trim()
                        if (body.isNotEmpty()) {
                            DeviceHardwareHelper.appendObsidianEntry(context, "Diario", "", body)
                            logs.add("📝 Nota salva no Obsidian")
                        }
                    }
                    "INBOX" -> {
                        val body = parts.drop(1).joinToString(":").trim()
                        if (body.isNotEmpty()) {
                            DeviceHardwareHelper.appendObsidianEntry(context, "Inbox", "", body)
                            logs.add("💡 Ideia salva no Inbox")
                        }
                    }
                    "READ_MESSAGES" -> {
                        if (locked) {
                            logs.add("🔒 Desbloqueie para ler notificações")
                        } else {
                            val msgs = UltronNotificationService.getRecentMessages(3)
                            logs.add(
                                if (msgs.isEmpty()) "📭 Sem novas mensagens"
                                else "📨 ${msgs.size} mensagens recentes"
                            )
                        }
                    }
                    "REPLY_MESSAGE" -> {
                        if (locked) {
                            logs.add("🔒 Desbloqueie para responder mensagens")
                        } else {
                            val target = if (arg1.equals("ultimo", true) || arg1.equals("último", true)) "" else arg1
                            val body = parts.drop(2).joinToString(":").trim()
                            if (body.isNotEmpty()) {
                                val res = UltronNotificationService.replyToMessage(context, target, body)
                                logs.add("↩️ $res")
                            }
                        }
                    }
                }
            } catch (e: Throwable) {
                logs.add("⚠️ Falha em $cmd: ${e.message}")
            }
        }

        val clean = pattern.replace(rawReply, "").trim().ifEmpty {
            if (logs.isNotEmpty()) "Comando executado no dispositivo." else rawReply.trim()
        }
        val display = if (logs.isEmpty()) {
            clean
        } else {
            "$clean\n\n[Hardware: ${logs.joinToString(" • ")}]"
        }
        return BackgroundTurnResult(
            speakText = clean,
            displayText = display,
            senderLabel = if (aiModel.isNotBlank()) "U.L.T.R.O.N. ($aiModel)" else "U.L.T.R.O.N. (2º plano)",
        )
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
