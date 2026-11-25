package com.viniciusnpaula.ultron_mobile

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max

/**
 * Reprodutor PCM16 mono em streaming (24 kHz padrão para Gemini Live) usando
 * Android AudioTrack com flush instantâneo para barge-in em tempo real.
 */
class PcmStreamPlayerHandler(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "com.viniciusnpaula.ultron_mobile/pcm_player"
        private const val DEFAULT_SAMPLE_RATE = 24000
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val writeExecutor: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "ultron-pcm-player").apply { isDaemon = true }
    }
    private val lock = Any()
    private val active = AtomicBoolean(false)
    private var audioTrack: AudioTrack? = null
    private var currentSampleRate: Int = DEFAULT_SAMPLE_RATE

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val sampleRate = (call.argument<Int>("sampleRate") ?: DEFAULT_SAMPLE_RATE)
                    .coerceIn(8000, 48000)
                val ok = startTrack(sampleRate)
                result.success(ok)
            }
            "write" -> {
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes == null || bytes.isEmpty()) {
                    result.success(0)
                    return
                }
                writeExecutor.execute {
                    writeBytes(bytes)
                }
                result.success(bytes.size)
            }
            "flush" -> {
                flushTrack()
                result.success(true)
            }
            "stop" -> {
                stopTrack()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun startTrack(sampleRate: Int): Boolean {
        synchronized(lock) {
            if (audioTrack != null && currentSampleRate == sampleRate && active.get()) {
                return true
            }
            releaseTrackLocked()
            val minBuf = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            if (minBuf <= 0) return false
            val bufferBytes = max(minBuf * 2, sampleRate / 5 * 2) // ~200ms de headroom
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            val format = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(sampleRate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build()

            val builder = AudioTrack.Builder()
                .setAudioAttributes(attrs)
                .setAudioFormat(format)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setBufferSizeInBytes(bufferBytes)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            }

            return try {
                val track = builder.build()
                if (track.state != AudioTrack.STATE_INITIALIZED) {
                    track.release()
                    false
                } else {
                    track.play()
                    audioTrack = track
                    currentSampleRate = sampleRate
                    active.set(true)
                    MainActivity.isUltronSpeakingGlobal = true
                    true
                }
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun writeBytes(bytes: ByteArray) {
        val track = synchronized(lock) {
            if (!active.get()) return
            audioTrack
        } ?: return
        try {
            if (track.playState != AudioTrack.PLAYSTATE_PLAYING) {
                track.play()
            }
            MainActivity.isUltronSpeakingGlobal = true
            track.write(bytes, 0, bytes.size, AudioTrack.WRITE_BLOCKING)
        } catch (_: Exception) {
        }
    }

    /** Interrupção instantânea (barge-in): esvazia o buffer nativo de áudio imediatamente. */
    private fun flushTrack() {
        synchronized(lock) {
            val track = audioTrack ?: return
            try {
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.pause()
                }
                track.flush()
                if (active.get()) {
                    track.play()
                }
            } catch (_: Exception) {
            } finally {
                MainActivity.isUltronSpeakingGlobal = false
                MainActivity.lastSpeechEndTimestampMs = System.currentTimeMillis()
            }
        }
    }

    fun stopTrack() {
        synchronized(lock) {
            active.set(false)
            releaseTrackLocked()
        }
    }

    private fun releaseTrackLocked() {
        val track = audioTrack
        audioTrack = null
        if (track != null) {
            try {
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                    track.pause()
                }
                track.flush()
                track.stop()
            } catch (_: Exception) {
            }
            try {
                track.release()
            } catch (_: Exception) {
            }
        }
        MainActivity.isUltronSpeakingGlobal = false
        MainActivity.lastSpeechEndTimestampMs = System.currentTimeMillis()
    }

    fun release() {
        channel.setMethodCallHandler(null)
        stopTrack()
        writeExecutor.shutdownNow()
    }
}
