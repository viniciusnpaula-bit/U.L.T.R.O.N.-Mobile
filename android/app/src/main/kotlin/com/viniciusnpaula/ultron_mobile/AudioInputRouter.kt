package com.viniciusnpaula.ultron_mobile

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import androidx.core.content.ContextCompat

/**
 * Gerencia a descoberta, persistência e roteamento de microfones nativos Android
 * (Automático, Microfone do Celular, Fone com Fio/USB e Fone Bluetooth SCO/BLE)
 * para captura via `AudioRecord` em 1º e 2º plano, sem depender de serviços Google.
 */
object AudioInputRouter {
    private const val PREFS_NAME = "ultron_audio_input_prefs"
    private const val KEY_ID = "preferred_mic_id"
    private const val KEY_TYPE = "preferred_mic_type"
    private const val KEY_NAME = "preferred_mic_name"

    const val AUTO_ID = -1
    const val AUTO_TYPE = -1

    data class MicSelection(
        val id: Int = AUTO_ID,
        val type: Int = AUTO_TYPE,
        val name: String = "Automático (Padrão do Android)",
    ) {
        val isAuto: Boolean get() = id == AUTO_ID && type == AUTO_TYPE
    }

    data class AudioInputDeviceEntry(
        val id: Int,
        val type: Int,
        val category: String,
        val name: String,
        val typeLabel: String,
        val address: String,
        val isBluetooth: Boolean,
        val isBuiltIn: Boolean,
        val isWiredOrUsb: Boolean,
    ) {
        fun toMap(selectedId: Int, selectedType: Int): Map<String, Any?> = mapOf(
            "id" to id,
            "type" to type,
            "category" to category,
            "name" to name,
            "typeLabel" to typeLabel,
            "address" to address,
            "isBluetooth" to isBluetooth,
            "isBuiltIn" to isBuiltIn,
            "isWiredOrUsb" to isWiredOrUsb,
            "isSelected" to (id == selectedId && (id != AUTO_ID || selectedType == AUTO_TYPE)),
        )
    }

    data class OpenedAudioRecord(
        val record: AudioRecord,
        val sourceUsed: Int,
        val routedDeviceName: String?,
        val routedDeviceType: Int?,
        val cleanupRouting: () -> Unit,
    )

    fun hasBluetoothConnectPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.BLUETOOTH_CONNECT,
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun saveSelection(context: Context, id: Int, type: Int, name: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_ID, id)
            .putInt(KEY_TYPE, type)
            .putString(KEY_NAME, name.trim())
            .apply()
    }

    fun loadSelection(context: Context): MicSelection {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val id = prefs.getInt(KEY_ID, AUTO_ID)
        val type = prefs.getInt(KEY_TYPE, AUTO_TYPE)
        val name = prefs.getString(KEY_NAME, "")?.trim().orEmpty()
        if (id == AUTO_ID && type == AUTO_TYPE) {
            return MicSelection()
        }
        return MicSelection(
            id = id,
            type = type,
            name = name.ifBlank { typeLabelFor(type) },
        )
    }

    fun listInputDevices(context: Context): List<Map<String, Any?>> {
        val sel = loadSelection(context)
        val entries = mutableListOf<AudioInputDeviceEntry>()
        entries += AudioInputDeviceEntry(
            id = AUTO_ID,
            type = AUTO_TYPE,
            category = "auto",
            name = "Automático (Padrão do Android)",
            typeLabel = "Roteamento padrão",
            address = "",
            isBluetooth = false,
            isBuiltIn = false,
            isWiredOrUsb = false,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            val rawDevices = am?.getDevices(AudioManager.GET_DEVICES_INPUTS) ?: emptyArray()
            val usable = rawDevices.filter { isUserMicDevice(it.type) }
            val builtInCount = usable.count { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
            for (dev in usable) {
                entries += toEntry(dev, builtInCount)
            }
        }

        // Ordena mantendo Auto primeiro, depois Bluetooth/Fio/USB e por fim Celular.
        val sorted = listOf(entries.first()) + entries.drop(1).sortedBy { entry ->
            when {
                entry.isWiredOrUsb -> 0
                entry.isBluetooth -> 1
                entry.isBuiltIn -> 2
                else -> 3
            }
        }

        // Resolve qual item deve aparecer selecionado (por id exato ou fallback por tipo/nome).
        var matchedIndex = sorted.indexOfFirst { it.id == sel.id && sel.id != AUTO_ID }
        if (matchedIndex < 0 && !sel.isAuto) {
            matchedIndex = sorted.indexOfFirst {
                it.type == sel.type && (sel.name.isBlank() || it.name.equals(sel.name, ignoreCase = true))
            }
            if (matchedIndex < 0) {
                matchedIndex = sorted.indexOfFirst { it.type == sel.type }
            }
        }
        if (matchedIndex < 0) matchedIndex = 0

        return sorted.mapIndexed { idx, entry ->
            entry.toMap(
                selectedId = sorted[matchedIndex].id,
                selectedType = sorted[matchedIndex].type,
            ).let { base ->
                if (idx == matchedIndex) base + ("isSelected" to true) else base + ("isSelected" to false)
            }
        }
    }

    private fun isUserMicDevice(type: Int): Boolean {
        return when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_MIC,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE -> true
            else -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    type == AudioDeviceInfo.TYPE_BLE_HEADSET
                ) {
                    true
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                    type == AudioDeviceInfo.TYPE_HEARING_AID
                ) {
                    true
                } else {
                    false
                }
            }
        }
    }

    private fun isBluetoothType(type: Int): Boolean {
        if (type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            type == AudioDeviceInfo.TYPE_BLE_HEADSET
        ) {
            return true
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            type == AudioDeviceInfo.TYPE_HEARING_AID
        ) {
            return true
        }
        return false
    }

    private fun isWiredOrUsbType(type: Int): Boolean {
        return type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
            type == AudioDeviceInfo.TYPE_USB_HEADSET ||
            type == AudioDeviceInfo.TYPE_USB_DEVICE
    }

    private fun typeLabelFor(type: Int): String {
        return when (type) {
            AUTO_TYPE -> "Automático"
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> "Microfone do aparelho"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Fone com fio (P2)"
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE -> "Microfone USB / USB-C"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth (HFP/SCO)"
            else -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    type == AudioDeviceInfo.TYPE_BLE_HEADSET
                ) {
                    "Bluetooth LE Audio"
                } else {
                    "Microfone externo"
                }
            }
        }
    }

    private fun deviceDisplayName(dev: AudioDeviceInfo, builtInCount: Int): String {
        val rawProduct = dev.productName?.toString()?.trim().orEmpty()
        val addr = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            dev.address.trim()
        } else {
            ""
        }
        return when (dev.type) {
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> {
                if (builtInCount > 1 && addr.isNotBlank()) {
                    val pos = when (addr.lowercase()) {
                        "bottom" -> "inferior"
                        "top" -> "superior"
                        "back" -> "traseiro"
                        "front" -> "frontal"
                        else -> addr
                    }
                    "Microfone do Celular ($pos)"
                } else {
                    "Microfone do Celular"
                }
            }
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> {
                if (rawProduct.isNotBlank() && !rawProduct.equals(Build.MODEL, ignoreCase = true)) {
                    "$rawProduct (Fone P2)"
                } else {
                    "Microfone do Fone com Fio"
                }
            }
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE -> {
                if (rawProduct.isNotBlank() && !rawProduct.equals(Build.MODEL, ignoreCase = true)) {
                    "$rawProduct (USB)"
                } else {
                    "Microfone do Fone USB-C"
                }
            }
            else -> {
                if (isBluetoothType(dev.type)) {
                    if (rawProduct.isNotBlank() && !rawProduct.equals(Build.MODEL, ignoreCase = true)) {
                        "$rawProduct (Bluetooth)"
                    } else {
                        "Microfone do Fone Bluetooth"
                    }
                } else {
                    rawProduct.ifBlank { typeLabelFor(dev.type) }
                }
            }
        }
    }

    private fun toEntry(dev: AudioDeviceInfo, builtInCount: Int): AudioInputDeviceEntry {
        val addr = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            dev.address.trim()
        } else {
            ""
        }
        val bt = isBluetoothType(dev.type)
        val builtIn = dev.type == AudioDeviceInfo.TYPE_BUILTIN_MIC
        val wired = isWiredOrUsbType(dev.type)
        val cat = when {
            bt -> "bluetooth"
            wired -> "wired"
            builtIn -> "builtin"
            else -> "other"
        }
        return AudioInputDeviceEntry(
            id = dev.id,
            type = dev.type,
            category = cat,
            name = deviceDisplayName(dev, builtInCount),
            typeLabel = typeLabelFor(dev.type),
            address = addr,
            isBluetooth = bt,
            isBuiltIn = builtIn,
            isWiredOrUsb = wired,
        )
    }

    private fun resolvePreferredDevice(context: Context, selection: MicSelection): AudioDeviceInfo? {
        if (selection.isAuto || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return null
        val inputs = am.getDevices(AudioManager.GET_DEVICES_INPUTS).filter { isUserMicDevice(it.type) }
        if (inputs.isEmpty()) return null
        val builtInCount = inputs.count { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }

        if (selection.id != AUTO_ID) {
            inputs.firstOrNull { it.id == selection.id }?.let { return it }
        }
        if (selection.name.isNotBlank()) {
            inputs.firstOrNull {
                it.type == selection.type &&
                    deviceDisplayName(it, builtInCount).equals(selection.name, ignoreCase = true)
            }?.let { return it }
        }
        return inputs.firstOrNull { it.type == selection.type }
    }

    /**
     * Abre e inicia um `AudioRecord` respeitando o microfone escolhido pelo usuário.
     *
     * @param enableBluetoothSco `true` para captura de fala sob demanda (1º/2º plano);
     * `false` para sentinela contínua 24/7 (evita degradar música A2DP em HFP contínuo).
     */
    fun openAudioRecord(
        context: Context,
        sampleRate: Int,
        bufferSize: Int,
        defaultSources: List<Int>,
        enableBluetoothSco: Boolean,
    ): OpenedAudioRecord? {
        val selection = loadSelection(context)
        val preferred = resolvePreferredDevice(context, selection)
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager

        var btRoutingActivated = false
        var previousMode: Int? = null
        val cleanup: () -> Unit = {
            if (btRoutingActivated && am != null) {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        am.clearCommunicationDevice()
                    } else {
                        @Suppress("DEPRECATION")
                        am.isBluetoothScoOn = false
                        @Suppress("DEPRECATION")
                        am.stopBluetoothSco()
                    }
                    if (previousMode != null) {
                        am.mode = previousMode!!
                    }
                } catch (_: Throwable) {
                }
            }
        }

        val effectivePreferred: AudioDeviceInfo?
        val sources: List<Int>
        if (preferred != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (isBluetoothType(preferred.type)) {
                if (enableBluetoothSco && am != null && hasBluetoothConnectPermission(context)) {
                    btRoutingActivated = activateBluetoothInputRouting(am, preferred).also {
                        if (it) {
                            previousMode = try {
                                am.mode
                            } catch (_: Throwable) {
                                null
                            }
                        }
                    }
                    effectivePreferred = preferred
                    sources = listOf(
                        MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                        MediaRecorder.AudioSource.MIC,
                        MediaRecorder.AudioSource.VOICE_RECOGNITION,
                        MediaRecorder.AudioSource.DEFAULT,
                    )
                } else if (!enableBluetoothSco) {
                    // Sentinela 24/7: se o usuário escolheu Bluetooth, tenta preferredDevice sem forçar SCO
                    // permanente; se o SO exigir SCO, o fallback continua seguro no aparelho.
                    effectivePreferred = null
                    sources = defaultSources
                } else {
                    effectivePreferred = preferred
                    sources = listOf(
                        MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                        MediaRecorder.AudioSource.VOICE_RECOGNITION,
                        MediaRecorder.AudioSource.MIC,
                        MediaRecorder.AudioSource.DEFAULT,
                    )
                }
            } else if (preferred.type == AudioDeviceInfo.TYPE_BUILTIN_MIC) {
                // Garante que nenhum SCO antigo prenda a captura no fone.
                if (am != null) {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            am.clearCommunicationDevice()
                        } else {
                            @Suppress("DEPRECATION")
                            if (am.isBluetoothScoOn) {
                                am.isBluetoothScoOn = false
                                am.stopBluetoothSco()
                            }
                        }
                    } catch (_: Throwable) {
                    }
                }
                effectivePreferred = preferred
                // Evita VOICE_COMMUNICATION primeiro porque OEMs costumam redirecioná-lo para o fone.
                sources = listOf(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION,
                    MediaRecorder.AudioSource.MIC,
                    MediaRecorder.AudioSource.DEFAULT,
                )
            } else {
                effectivePreferred = preferred
                sources = listOf(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION,
                    MediaRecorder.AudioSource.MIC,
                    MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                    MediaRecorder.AudioSource.DEFAULT,
                )
            }
        } else {
            effectivePreferred = null
            sources = defaultSources
        }

        for (source in sources) {
            val candidate = try {
                AudioRecord(
                    source,
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufferSize,
                )
            } catch (se: SecurityException) {
                cleanup()
                throw se
            } catch (_: IllegalArgumentException) {
                continue
            }

            if (candidate.state != AudioRecord.STATE_INITIALIZED) {
                try {
                    candidate.release()
                } catch (_: Throwable) {
                }
                continue
            }

            if (effectivePreferred != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                try {
                    candidate.setPreferredDevice(effectivePreferred)
                } catch (_: Throwable) {
                }
            }

            try {
                candidate.startRecording()
            } catch (_: IllegalStateException) {
                try {
                    candidate.release()
                } catch (_: Throwable) {
                }
                continue
            }

            if (candidate.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                try {
                    candidate.release()
                } catch (_: Throwable) {
                }
                continue
            }

            var routedName: String? = null
            var routedType: Int? = null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                try {
                    val routed = candidate.routedDevice
                    if (routed != null) {
                        val builtInCount = am
                            ?.getDevices(AudioManager.GET_DEVICES_INPUTS)
                            ?.count { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC } ?: 1
                        routedName = deviceDisplayName(routed, builtInCount)
                        routedType = routed.type
                    }
                } catch (_: Throwable) {
                }
            }

            return OpenedAudioRecord(
                record = candidate,
                sourceUsed = source,
                routedDeviceName = routedName,
                routedDeviceType = routedType,
                cleanupRouting = cleanup,
            )
        }

        cleanup()
        return null
    }

    private fun activateBluetoothInputRouting(
        am: AudioManager,
        preferredInput: AudioDeviceInfo,
    ): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val commDevices = am.availableCommunicationDevices
                val target = commDevices.firstOrNull { it.id == preferredInput.id }
                    ?: commDevices.firstOrNull { isBluetoothType(it.type) }
                if (target != null) {
                    am.setCommunicationDevice(target)
                } else {
                    false
                }
            } else {
                am.mode = AudioManager.MODE_IN_COMMUNICATION
                @Suppress("DEPRECATION")
                am.startBluetoothSco()
                @Suppress("DEPRECATION")
                am.isBluetoothScoOn = true
                true
            }
        } catch (_: Throwable) {
            false
        }
    }
}
