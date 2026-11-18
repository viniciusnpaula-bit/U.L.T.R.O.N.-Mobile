package com.viniciusnpaula.ultron_mobile

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlin.math.max

class AudioCaptureHandler(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    PluginRegistry.RequestPermissionsResultListener {

    companion object {
        private const val METHOD_CHANNEL = "com.viniciusnpaula.ultron_mobile/audio_capture"
        private const val EVENT_CHANNEL = "com.viniciusnpaula.ultron_mobile/audio_capture_frames"
        private const val PERMISSION_REQUEST_CODE = 4101
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()

    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var audioRecord: AudioRecord? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var gainControl: AutomaticGainControl? = null
    private var readerThread: Thread? = null

    @Volatile
    private var capturing = false

    @Volatile
    private var captureToken = 0L

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermission" -> result.success(hasRecordPermission())
            "requestPermission" -> requestRecordPermission(result)
            "start" -> {
                val sampleRate = call.argument<Int>("sampleRate") ?: 16000
                startCapture(sampleRate, result)
            }
            "stop" -> {
                stopCapture()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun hasRecordPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestRecordPermission(result: MethodChannel.Result) {
        if (hasRecordPermission()) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("permission_pending", "Audio permission request already in progress.", null)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.RECORD_AUDIO),
            PERMISSION_REQUEST_CODE,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val pending = pendingPermissionResult
        pendingPermissionResult = null
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pending?.success(granted)
        return true
    }

    private fun startCapture(sampleRate: Int, result: MethodChannel.Result) {
        if (!hasRecordPermission()) {
            result.error("permission_denied", "RECORD_AUDIO permission not granted.", null)
            return
        }

        val token: Long
        synchronized(lock) {
            stopCaptureLocked()
            MainActivity.isForegroundCaptureActive = true
            token = ++captureToken
        }

        Thread({
            // Aguarda o sentinela em segundo plano liberar o microfone antes de abrir em 1º plano.
            var waitedMs = 0
            while (UltronAudioService.isRecorderOpen && waitedMs < 400 && captureToken == token) {
                try {
                    Thread.sleep(25)
                } catch (_: InterruptedException) {
                    break
                }
                waitedMs += 25
            }

            if (captureToken != token) {
                mainHandler.post {
                    result.error("capture_cancelled", "Captura cancelada antes de iniciar.", null)
                }
                return@Thread
            }

            synchronized(lock) {
                if (captureToken != token) {
                    mainHandler.post {
                        result.error("capture_cancelled", "Captura cancelada antes de iniciar.", null)
                    }
                    return@Thread
                }

                val minBuf = AudioRecord.getMinBufferSize(
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                )
                if (minBuf <= 0) {
                    MainActivity.isForegroundCaptureActive = false
                    mainHandler.post {
                        result.error("audio_config_error", "Invalid AudioRecord buffer size: $minBuf", null)
                    }
                    return@Thread
                }

                // 20ms frame = sampleRate * 2 bytes / 50; keep internal ring >= 100ms
                val chunkSize = max(320, (sampleRate * 2) / 50)
                val bufferSize = max(minBuf, chunkSize * 5)

                val sources = listOf(
                    MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                    MediaRecorder.AudioSource.VOICE_RECOGNITION,
                    MediaRecorder.AudioSource.MIC,
                    MediaRecorder.AudioSource.DEFAULT,
                )

                var openedRecord: AudioRecord? = null
                var lastReason = "Nenhum microfone inicializou"
                for (source in sources) {
                    val candidate = try {
                        AudioRecord(
                            source,
                            sampleRate,
                            AudioFormat.CHANNEL_IN_MONO,
                            AudioFormat.ENCODING_PCM_16BIT,
                            bufferSize,
                        )
                    } catch (e: SecurityException) {
                        MainActivity.isForegroundCaptureActive = false
                        mainHandler.post {
                            result.error("permission_denied", e.message, null)
                        }
                        return@Thread
                    } catch (e: IllegalArgumentException) {
                        lastReason = "${e.javaClass.simpleName}: ${e.message}"
                        continue
                    }

                    if (candidate.state != AudioRecord.STATE_INITIALIZED) {
                        lastReason = "source=$source state=${candidate.state}"
                        try {
                            candidate.release()
                        } catch (_: Throwable) {
                        }
                        continue
                    }

                    try {
                        candidate.startRecording()
                    } catch (e: IllegalStateException) {
                        lastReason = "source=$source startRecording: ${e.message}"
                        try {
                            candidate.release()
                        } catch (_: Throwable) {
                        }
                        continue
                    }

                    if (candidate.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                        lastReason = "source=$source recordingState=${candidate.recordingState}"
                        try {
                            candidate.release()
                        } catch (_: Throwable) {
                        }
                        continue
                    }

                    openedRecord = candidate
                    break
                }

                val record = openedRecord
                if (record == null) {
                    MainActivity.isForegroundCaptureActive = false
                    mainHandler.post {
                        result.error("audio_init_failed", "Nenhum microfone ativo disponível ($lastReason).", null)
                    }
                    return@Thread
                }

                val sessionId = record.audioSessionId
                var aecEnabled = false
                var nsEnabled = false
                var agcEnabled = false

                try {
                    if (AcousticEchoCanceler.isAvailable()) {
                        echoCanceler = AcousticEchoCanceler.create(sessionId)?.apply {
                            enabled = true
                            aecEnabled = enabled
                        }
                    }
                } catch (_: Throwable) {
                }
                try {
                    if (NoiseSuppressor.isAvailable()) {
                        noiseSuppressor = NoiseSuppressor.create(sessionId)?.apply {
                            enabled = true
                            nsEnabled = enabled
                        }
                    }
                } catch (_: Throwable) {
                }
                try {
                    if (AutomaticGainControl.isAvailable()) {
                        gainControl = AutomaticGainControl.create(sessionId)?.apply {
                            enabled = true
                            agcEnabled = enabled
                        }
                    }
                } catch (_: Throwable) {
                }

                audioRecord = record
                capturing = true

                val thread = Thread({
                    val frame = ByteArray(chunkSize)
                    while (capturing) {
                        val read = try {
                            record.read(frame, 0, frame.size)
                        } catch (_: Throwable) {
                            break
                        }
                        if (!capturing) break
                        if (read > 0) {
                            val copy = frame.copyOf(read)
                            mainHandler.post {
                                if (capturing) {
                                    eventSink?.success(copy)
                                }
                            }
                        }
                    }
                }, "ultron-audio-capture")
                readerThread = thread
                thread.start()

                mainHandler.post {
                    result.success(
                        mapOf(
                            "aecEnabled" to aecEnabled,
                            "nsEnabled" to nsEnabled,
                            "agcEnabled" to agcEnabled,
                            "sampleRate" to sampleRate,
                        ),
                    )
                }
            }
        }, "ultron-audio-open").start()
    }

    fun stopCapture() {
        synchronized(lock) {
            stopCaptureLocked()
        }
    }

    private fun stopCaptureLocked() {
        captureToken++
        capturing = false
        MainActivity.isForegroundCaptureActive = false

        val thread = readerThread
        readerThread = null

        val record = audioRecord
        audioRecord = null
        if (record != null) {
            try {
                if (record.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    record.stop()
                }
            } catch (_: IllegalStateException) {
            }
        }

        if (thread != null && Thread.currentThread() !== thread) {
            try {
                thread.join(300)
            } catch (_: InterruptedException) {
            }
        }

        echoCanceler?.release()
        echoCanceler = null
        noiseSuppressor?.release()
        noiseSuppressor = null
        gainControl?.release()
        gainControl = null

        record?.release()
    }

    fun release() {
        stopCapture()
        pendingPermissionResult = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
    }
}
