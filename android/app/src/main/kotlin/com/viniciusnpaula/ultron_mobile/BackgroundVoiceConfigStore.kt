package com.viniciusnpaula.ultron_mobile

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class BackgroundVoiceConfig(
    val sttUrl: String = "",
    val sttKey: String = "",
    val sttModel: String = "whisper-large-v3-turbo",
    val sttLanguage: String = "pt",
    val aiBaseUrl: String = "https://text.pollinations.ai/openai",
    val aiKey: String = "",
    val aiModel: String = "openai",
    val fishEnabled: Boolean = false,
    val fishKey: String = "",
    val fishRefId: String = "",
    val fishLanguage: String = "pt",
    val fishModel: String = "s2.1-pro",
    val whisperMode: Boolean = false,
) {
    val hasStt: Boolean get() = sttKey.isNotBlank() && sttUrl.isNotBlank()
    val hasFish: Boolean get() = fishEnabled && fishKey.isNotBlank() && fishRefId.isNotBlank()
}

/**
 * Persiste as credenciais de STT, IA e Fish Audio cifradas com AES-256-GCM
 * via AndroidKeyStore para que o serviço em 2º plano responda mesmo com o app fechado.
 */
object BackgroundVoiceConfigStore {
    private const val PREFS_NAME = "ultron_bg_voice_prefs"
    private const val KEY_PAYLOAD = "encrypted_cfg_v1"
    private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
    private const val KEY_ALIAS = "ultron_bg_voice_cfg_key_v1"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val IV_LENGTH_BYTES = 12
    private const val TAG_LENGTH_BITS = 128

    fun save(context: Context, cfg: BackgroundVoiceConfig) {
        try {
            val json = JSONObject().apply {
                put("sttUrl", cfg.sttUrl)
                put("sttKey", cfg.sttKey)
                put("sttModel", cfg.sttModel)
                put("sttLanguage", cfg.sttLanguage)
                put("aiBaseUrl", cfg.aiBaseUrl)
                put("aiKey", cfg.aiKey)
                put("aiModel", cfg.aiModel)
                put("fishEnabled", cfg.fishEnabled)
                put("fishKey", cfg.fishKey)
                put("fishRefId", cfg.fishRefId)
                put("fishLanguage", cfg.fishLanguage)
                put("fishModel", cfg.fishModel)
                put("whisperMode", cfg.whisperMode)
            }.toString()

            val encoded = encryptString(json) ?: return
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_PAYLOAD, encoded)
                .apply()
        } catch (_: Exception) {
        }
    }

    fun load(context: Context): BackgroundVoiceConfig {
        return try {
            val encoded = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(KEY_PAYLOAD, null) ?: return BackgroundVoiceConfig()
            val raw = decryptString(encoded) ?: return BackgroundVoiceConfig()
            val obj = JSONObject(raw)

            BackgroundVoiceConfig(
                sttUrl = obj.optString("sttUrl", ""),
                sttKey = obj.optString("sttKey", ""),
                sttModel = obj.optString("sttModel", "whisper-large-v3-turbo"),
                sttLanguage = obj.optString("sttLanguage", "pt"),
                aiBaseUrl = obj.optString("aiBaseUrl", "https://text.pollinations.ai/openai"),
                aiKey = obj.optString("aiKey", ""),
                aiModel = obj.optString("aiModel", "openai"),
                fishEnabled = obj.optBoolean("fishEnabled", false),
                fishKey = obj.optString("fishKey", ""),
                fishRefId = obj.optString("fishRefId", ""),
                fishLanguage = obj.optString("fishLanguage", "pt"),
                fishModel = obj.optString("fishModel", "s2.1-pro"),
                whisperMode = obj.optBoolean("whisperMode", false),
            )
        } catch (_: Exception) {
            BackgroundVoiceConfig()
        }
    }

    internal fun encryptString(plain: String): String? {
        return try {
            val key = getOrCreateSecretKey() ?: return null
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, key)
            val iv = cipher.iv
            val ciphertext = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))

            val combined = ByteArray(iv.size + ciphertext.size)
            System.arraycopy(iv, 0, combined, 0, iv.size)
            System.arraycopy(ciphertext, 0, combined, iv.size, ciphertext.size)

            Base64.encodeToString(combined, Base64.NO_WRAP)
        } catch (_: Exception) {
            null
        }
    }

    internal fun decryptString(encoded: String): String? {
        return try {
            val combined = Base64.decode(encoded, Base64.NO_WRAP)
            if (combined.size <= IV_LENGTH_BYTES) return null

            val iv = combined.copyOfRange(0, IV_LENGTH_BYTES)
            val ciphertext = combined.copyOfRange(IV_LENGTH_BYTES, combined.size)

            val key = getExistingSecretKey() ?: return null
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_LENGTH_BITS, iv))
            String(cipher.doFinal(ciphertext), Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    private fun getExistingSecretKey(): SecretKey? {
        val ks = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        return ks.getKey(KEY_ALIAS, null) as? SecretKey
    }

    private fun getOrCreateSecretKey(): SecretKey? {
        getExistingSecretKey()?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }
}
