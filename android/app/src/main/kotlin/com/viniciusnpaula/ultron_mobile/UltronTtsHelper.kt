package com.viniciusnpaula.ultron_mobile

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Wrapper de Voz Offline do U.L.T.R.O.N. com Bloqueio Anti-Eco (Half-Duplex):
 * 1. Mantém flags globais [isSpeaking] e [lastSpeechEndTimestampMs] para garantir que o
 *    microfone (UltronAudioService / SpeechRecognizer) NUNCA seja aberto enquanto o
 *    alto-falante do celular estiver reproduzindo a voz do Ultron.
 * 2. Permite interromper imediatamente qualquer fala ([stopAll]) antes de abrir o microfone.
 */
object UltronTtsHelper {
    private const val VOICE_ASSET_NAME = "ultron_fish_voice.wav"
    private const val IDLE_SHUTDOWN_DELAY_MS = 25_000L

    @Volatile
    var isSpeaking: Boolean = false
        private set

    @Volatile
    var lastSpeechEndTimestampMs: Long = 0L
        private set

    private val mainHandler = Handler(Looper.getMainLooper())
    private val idleShutdownRunnable = Runnable { shutdownTtsOnly() }

    private var player: MediaPlayer? = null
    private var pendingAudioResult: MethodChannel.Result? = null
    private var pendingAudioCallback: ((Boolean) -> Unit)? = null
    private var pendingAudioFile: File? = null
    @Volatile
    private var activeSpeakLatch: CountDownLatch? = null
    private var offlineTts: TextToSpeech? = null
    private var ttsReady: Boolean = false
    private var preferredVoiceName: String? = null
    private var configuredPitch: Float = 0.55f
    private var configuredRate: Float = 0.92f

    fun configure(voiceName: String?, pitch: Float, rate: Float) {
        preferredVoiceName = voiceName?.takeIf { it.isNotBlank() }
        configuredPitch = pitch.coerceIn(0.3f, 2.0f)
        // FlutterTts rate (~0.45..0.58) vs Android TextToSpeech native rate (1.0 normal)
        configuredRate = (rate * 2.0f).coerceIn(0.5f, 2.0f)
        if (ttsReady) {
            applyConfigToEngine(offlineTts)
        }
    }

    private fun applyConfigToEngine(engine: TextToSpeech?) {
        if (engine == null) return
        val name = preferredVoiceName
        if (!name.isNullOrBlank()) {
            try {
                val match = engine.voices?.firstOrNull { it.name == name }
                if (match != null) {
                    engine.voice = match
                }
            } catch (_: Exception) {
            }
        }
        engine.setPitch(configuredPitch)
        engine.setSpeechRate(configuredRate)
    }

    private fun markSpeechStarted() {
        isSpeaking = true
        MainActivity.isUltronSpeakingGlobal = true
    }

    private fun markSpeechEnded() {
        val now = System.currentTimeMillis()
        isSpeaking = false
        lastSpeechEndTimestampMs = now
        MainActivity.isUltronSpeakingGlobal = false
        MainActivity.lastSpeechEndTimestampMs = now
        activeSpeakLatch?.countDown()
        activeSpeakLatch = null
    }

    private fun cleanupPendingAudio(completed: Boolean) {
        val pending = pendingAudioResult
        pendingAudioResult = null
        val cb = pendingAudioCallback
        pendingAudioCallback = null
        val file = pendingAudioFile
        pendingAudioFile = null
        try {
            file?.delete()
        } catch (_: Exception) {
        }
        try {
            pending?.success(completed)
        } catch (_: Exception) {
        }
        try {
            cb?.invoke(completed)
        } catch (_: Exception) {
        }
    }

    private fun failPendingAudio(code: String, message: String) {
        val pending = pendingAudioResult
        pendingAudioResult = null
        val cb = pendingAudioCallback
        pendingAudioCallback = null
        val file = pendingAudioFile
        pendingAudioFile = null
        try {
            file?.delete()
        } catch (_: Exception) {
        }
        try {
            pending?.error(code, message, null)
        } catch (_: Exception) {
        }
        try {
            cb?.invoke(false)
        } catch (_: Exception) {
        }
    }

    /** Reproduz bytes de áudio TTS (ex.: Fish Audio MP3) e bloqueia até terminar. */
    fun playAudioBytesBlocking(
        context: Context,
        bytes: ByteArray,
        volume: Float = 1.0f,
        timeoutMs: Long = 25_000L
    ): Boolean {
        if (bytes.isEmpty()) return false
        val latch = CountDownLatch(1)
        var ok = false
        playAudioBytes(context, bytes, volume, result = null) { completed ->
            ok = completed
            latch.countDown()
        }
        try {
            latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
        }
        return ok
    }

    /** Fala via motor offline do Android e aguarda término antes de retomar o KWS. */
    fun speakBlocking(
        context: Context,
        text: String,
        timeoutMs: Long = 25_000L
    ) {
        val clean = text.trim()
        if (clean.isEmpty()) return
        val latch = CountDownLatch(1)
        activeSpeakLatch?.countDown()
        activeSpeakLatch = latch
        speakWithOfflineEngine(context.applicationContext, clean)
        try {
            latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
        } finally {
            if (activeSpeakLatch === latch) {
                activeSpeakLatch = null
            }
        }
    }

    /** Reproduz bytes de áudio TTS (ex.: Fish Audio MP3) respeitando o bloqueio anti-eco. */
    fun playAudioBytes(
        context: Context,
        bytes: ByteArray,
        volume: Float,
        result: MethodChannel.Result?,
        onComplete: ((Boolean) -> Unit)? = null
    ) {
        val task = Runnable {
            if (MainActivity.isForegroundRecognizerActive || bytes.isEmpty()) {
                try {
                    result?.success(false)
                } catch (_: Exception) {
                }
                onComplete?.invoke(false)
                return@Runnable
            }
            releasePlayer()
            var tempFile: File? = null
            try {
                tempFile = File.createTempFile("ultron_fish_tts_", ".mp3", context.cacheDir)
                tempFile.writeBytes(bytes)
                pendingAudioResult = result
                pendingAudioCallback = onComplete
                pendingAudioFile = tempFile
                markSpeechStarted()

                val safeVol = volume.coerceIn(0.05f, 1.0f)
                val mp = MediaPlayer()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    mp.setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                    )
                }
                mp.setVolume(safeVol, safeVol)
                mp.setDataSource(tempFile.absolutePath)
                mp.setOnCompletionListener {
                    releasePlayer(completed = true)
                    markSpeechEnded()
                }
                mp.setOnErrorListener { _, what, extra ->
                    releasePlayer(completed = false, errorCode = "fish_audio_playback", errorMessage = "Erro MediaPlayer ($what/$extra)")
                    markSpeechEnded()
                    true
                }
                mp.prepare()
                mp.start()
                player = mp
            } catch (e: Exception) {
                try {
                    tempFile?.delete()
                } catch (_: Exception) {
                }
                pendingAudioFile = null
                pendingAudioResult = null
                pendingAudioCallback = null
                markSpeechEnded()
                try {
                    result?.error("fish_audio_playback", e.message ?: "Falha ao reproduzir áudio", null)
                } catch (_: Exception) {
                }
                onComplete?.invoke(false)
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            task.run()
        } else {
            mainHandler.post(task)
        }
    }

    fun playFishVoiceAsset(context: Context, onComplete: (() -> Unit)? = null): Boolean {
        // Nunca toca se o microfone de reconhecimento estiver aberto!
        if (MainActivity.isForegroundRecognizerActive) {
            onComplete?.invoke()
            return false
        }
        return try {
            releasePlayer()
            markSpeechStarted()
            val afd = context.assets.openFd(VOICE_ASSET_NAME)
            val mp = MediaPlayer()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                mp.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
            }
            mp.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            afd.close()
            mp.setOnCompletionListener {
                releasePlayer()
                markSpeechEnded()
                onComplete?.invoke()
            }
            mp.setOnErrorListener { _, _, _ ->
                releasePlayer()
                markSpeechEnded()
                onComplete?.invoke()
                true
            }
            mp.prepare()
            mp.start()
            player = mp
            true
        } catch (_: Exception) {
            markSpeechEnded()
            onComplete?.invoke()
            false
        }
    }

    fun speak(context: Context, text: String, playSampleFirst: Boolean = false) {
        if (MainActivity.isForegroundRecognizerActive) return
        val clean = text.trim()
        if (clean.isEmpty()) {
            playFishVoiceAsset(context)
            return
        }
        if (playSampleFirst) {
            playFishVoiceAsset(context) {
                speakWithOfflineEngine(context.applicationContext, clean)
            }
        } else {
            speakWithOfflineEngine(context.applicationContext, clean)
        }
    }

    fun answerQuickOfflineQuery(context: Context, query: String): String {
        val lower = query.lowercase(Locale("pt", "BR"))
        val reply = when {
            lower.contains("que horas") || lower.contains("horário") || lower.contains("hora") -> {
                val now = SimpleDateFormat("HH:mm", Locale("pt", "BR")).format(Date())
                "Operador, agora são exatamente $now."
            }
            lower.contains("data") || lower.contains("que dia") -> {
                val today = SimpleDateFormat("dd 'de' MMMM 'de' yyyy", Locale("pt", "BR")).format(Date())
                "Hoje é dia $today."
            }
            else -> query
        }
        speak(context, reply, playSampleFirst = false)
        return reply
    }

    private fun scheduleIdleShutdown() {
        mainHandler.removeCallbacks(idleShutdownRunnable)
        mainHandler.postDelayed(idleShutdownRunnable, IDLE_SHUTDOWN_DELAY_MS)
    }

    private fun speakWithOfflineEngine(appContext: Context, text: String) {
        if (MainActivity.isForegroundRecognizerActive) return
        scheduleIdleShutdown()
        markSpeechStarted()
        if (offlineTts != null && ttsReady) {
            applyConfigToEngine(offlineTts)
            offlineTts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "ultron_offline_utt")
            return
        }
        offlineTts = TextToSpeech(appContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                ttsReady = true
                offlineTts?.language = Locale("pt", "BR")
                applyConfigToEngine(offlineTts)
                offlineTts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {
                        mainHandler.removeCallbacks(idleShutdownRunnable)
                        markSpeechStarted()
                    }

                    override fun onDone(utteranceId: String?) {
                        markSpeechEnded()
                        scheduleIdleShutdown()
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {
                        markSpeechEnded()
                        scheduleIdleShutdown()
                    }

                    override fun onStop(utteranceId: String?, interrupted: Boolean) {
                        markSpeechEnded()
                    }
                })
                if (!MainActivity.isForegroundRecognizerActive) {
                    offlineTts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "ultron_offline_utt")
                } else {
                    markSpeechEnded()
                }
            } else {
                markSpeechEnded()
            }
        }
    }

    fun stopAll() {
        releasePlayer()
        try {
            offlineTts?.stop()
        } catch (_: Exception) {
        }
        markSpeechEnded()
    }

    fun releasePlayer(
        completed: Boolean = false,
        errorCode: String? = null,
        errorMessage: String? = null
    ) {
        try {
            player?.stop()
        } catch (_: Exception) {
        }
        try {
            player?.release()
        } catch (_: Exception) {
        }
        player = null
        if (errorCode != null) {
            failPendingAudio(errorCode, errorMessage ?: "Falha ao reproduzir áudio")
        } else {
            cleanupPendingAudio(completed)
        }
    }

    private fun shutdownTtsOnly() {
        try {
            offlineTts?.stop()
            offlineTts?.shutdown()
        } catch (_: Exception) {
        }
        offlineTts = null
        ttsReady = false
        markSpeechEnded()
    }

    fun shutdown() {
        mainHandler.removeCallbacks(idleShutdownRunnable)
        releasePlayer()
        shutdownTtsOnly()
    }
}
