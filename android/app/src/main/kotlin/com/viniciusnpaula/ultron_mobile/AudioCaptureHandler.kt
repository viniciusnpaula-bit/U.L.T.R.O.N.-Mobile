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

        synchronized(lock) {
            stopCaptureLocked()

            val minBuf = AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            if (minBuf <= 0) {
                result.error("audio_config_error", "Invalid AudioRecord buffer size: $minBuf", null)
                return
            }

            // 20ms frame = sampleRate * 2 bytes / 50; keep internal ring >= 100ms
            val chunkSize = max(320, (sampleRate * 2) / 50)
            val bufferSize = max(minBuf, chunkSize * 5)

            val record = try {
                AudioRecord(
                    MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufferSize,
                )
            } catch (e: SecurityException) {
                result.error("permission_denied", e.message, null)
                return
            } catch (e: IllegalArgumentException) {
                result.error("audio_init_failed", e.message, null)
                return
            }

            if (record.state != AudioRecord.STATE_INITIALIZED) {
                record.release()
                result.error("audio_init_failed", "AudioRecord failed to initialize.", null)
                return
            }

            val sessionId = record.audioSessionId
            var aecEnabled = false
            var nsEnabled = false
            var agcEnabled = false

            if (AcousticEchoCanceler.isAvailable()) {
                echoCanceler = AcousticEchoCanceler.create(sessionId)?.apply {
                    enabled = true
                    aecEnabled = enabled
                }
            }
            if (NoiseSuppressor.isAvailable()) {
                noiseSuppressor = NoiseSuppressor.create(sessionId)?.apply {
                    enabled = true
                    nsEnabled = enabled
                }
            }
            if (AutomaticGainControl.isAvailable()) {
                gainControl = AutomaticGainControl.create(sessionId)?.apply {
                    enabled = true
                    agcEnabled = enabled
                }
            }

            audioRecord = record
            capturing = true
            MainActivity.isForegroundCaptureActive = true

            try {
                record.startRecording()
            } catch (e: IllegalStateException) {
                stopCaptureLocked()
                result.error("audio_start_failed", e.message, null)
                return
            }

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

    fun stopCapture() {
        synchronized(lock) {
            stopCaptureLocked()
        }
    }

    private fun stopCaptureLocked() {
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
