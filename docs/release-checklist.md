# U.L.T.R.O.N. Mobile — Release & Physical Device Checklist

## 1. Automated Verification (Desktop VM)
- [ ] `dart analyze` (or `flutter analyze` in an ASCII path / CI runner) reports **0 issues**.
- [ ] `flutter test` passes **100%** (all unit and widget tests, including `shaders/crimson_core.frag` asset compilation, loopback HTTP STT/pairing tests, and `sqflite_common_ffi` v1→v2 migration tests).

## 2. Android Release Build & CI Compatibility
- [ ] Local build or GitHub Actions `.github/workflows/android-release.yml`:
  - `flutter build apk --release` succeeds (or `--debug` when testing without `android/key.properties`).
  - Manifest merge succeeds with `INTERNET`, `RECORD_AUDIO`, `REQUEST_INSTALL_PACKAGES`, `UltronTileService`, `UltronNotificationListenerService`, `allowBackup="false"`, and `data_extraction_rules.xml`.
  - Kotlin compilation succeeds (`MainActivity.kt`, `AudioCaptureHandler.kt`, `UltronTileService.kt`, `UltronNotificationListenerService.kt`).
  - `shaders/crimson_core.frag` compiles and packages cleanly.
  - SQLCipher (`sqflite_sqlcipher`) includes `arm64-v8a` native libraries for Samsung Galaxy A34 5G.

## 3. Physical Device Validation — Samsung Galaxy A34 5G
- [ ] **Authentication & Lockout:**
  - Setup PIN (4–8 digits), verify unlock, test 5+ wrong PIN attempts to confirm 30s→15m exponential lockout, and test `BiometricPrompt` (fingerprint/face) + fallback to PIN.
- [ ] **Boot Flow & Crimson Shader:**
  - Confirm `BootLoadingScreen` displays sequential progress (`vault -> aiProviders -> audio -> shader -> ready`), does not speak before `ready`, renders `CoreOrb` with `crimson_core.frag`, and pauses `Ticker` in `CoreStage.hidden` and on screen lock/background.
- [ ] **Encrypted Storage & Legacy Migration:**
  - Verify legacy `ultron_conversations.db` (if present from v0.3.0) migrates messages to `ultron_conversations_v2.db`, removes the legacy plaintext file, and persists voice corrections/shortcuts/preferences across app restarts.
- [ ] **Voice Pipeline (AEC / VAD / Whisper / Selective Barge-In):**
  - Grant `RECORD_AUDIO` on first Push-to-Talk; verify transcription via Groq Whisper and normalized TTS (`U.L.T.R.O.N.` → `Ultron`).
  - Enable foreground continuous listening while TTS is speaking; verify normal ambient speech/TTS echo is ignored, `"parar"`/`"silêncio"`/`"ei ultron"` stops TTS immediately, and the post-TTS continuity window accepts follow-up speech.
  - Lock screen or switch apps while listening/speaking; confirm `AudioRecord` and `VoiceService` stop immediately.
- [ ] **Quick Settings Tile, Notification Listener & LAN Desktop Pairing:**
  - Tap the `U.L.T.R.O.N.` Quick Settings Tile while the app is locked/closed; confirm `AuthScreen` blocks access until unlocked and never opens the mic beforehand.
  - Verify Notification Listener is disabled by default; test opt-in confirmation + Android system permission toggle + `/desktop` HMAC-SHA256 LAN command confirmation dialog.

## 4. Signing Secrets & Tagging (`vX.Y.Z`)
Before pushing a release tag `git tag vX.Y.Z && git push origin vX.Y.Z`, confirm these GitHub Repository Secrets are configured:
- `ANDROID_KEYSTORE_BASE64` — Base64-encoded PKCS12/JKS keystore (keep an offline backup!).
- `ANDROID_KEYSTORE_PASSWORD` — Keystore password.
- `ANDROID_KEY_ALIAS` — Signing key alias.
- `ANDROID_KEY_PASSWORD` — Key password.
- Post-tag check: verify `.github/workflows/android-release.yml` passes `apksigner verify --print-certs` and publishes `app-release.apk` on GitHub Releases.
