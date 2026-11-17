# U.L.T.R.O.N. Mobile

Flutter/Dart Android node autonomous and independent of Desktop. Target: Samsung Galaxy A34 5G (Dimensity 1080, Mali-G68, 6–8 GB RAM). No local large LLM; language reasoning and STT can use remote OpenAI-compatible APIs (e.g. Groq) configured locally.

## Architecture
- `lib/core/security`: biometric/PIN gate (`AuthGate`, `PinVault` with PBKDF2-HMAC-SHA256 + exponential lockout) and SQLCipher key vault (`DatabaseKeyVault`).
- `lib/services`:
  - **Boot & Audio/Voice:** `StartupCoordinator`, `VoiceService` + `TtsTextNormalizer`, `PcmEnergy`, `PreSpeechRingBuffer`, `VadSegmenter`, `WavEncoder`, `GroqWhisperSttService` (RMS gate, confidence hallucination filters, circuit breaker), `AudioCaptureSource` (`AudioRecord` + hardware `AcousticEchoCanceler`/`NoiseSuppressor`/`AutomaticGainControl`), `VoicePipelineController` (Push-to-Talk, foreground continuous listening, selective barge-in, continuity window).
  - **Storage & Memory:** `ConversationHistory` (SQLCipher v2 + atomic migration from legacy v1 `ultron_conversations.db`), `VoiceCorrectionsService`, `VoiceShortcutsService` (fail-closed confirmation), `UserPreferencesService`, `AiProviderStore` (Chat + STT config), `AppUpdateService`, `ObsidianService`.
  - **Android & Desktop LAN:** `AndroidActionsService` (Quick Settings Tile gated by `AuthGate`, opt-in Notification Listener disabled by default), `DesktopPairingService` (LAN/private-host check, HMAC-SHA256 + timestamp + nonce, `ConfirmationGate`).
- `lib/ui/screens` & `lib/ui/widgets`: `AuthScreen`, `BootLoadingScreen`, `CoreScreen`, `CoreOrb` (runtime `shaders/crimson_core.frag` with `CorePainter` fallback and lifecycle-aware `Ticker`), `MemorySettingsScreen`, `DesktopPairingScreen`, `AiSettingsScreen`, `ConversationHistoryScreen`, `UpdateScreen`, `ActionConfirmationDialog`.
- `shaders`: `crimson_core.frag` analytical crimson core shader (`uSize`, `uTime`, `uEnergy`).

Desktop/security conventions: model output cannot authorize actions; sensitive operations require explicit UI/PIN confirmation; memory/preferences remain local.

## Performance
Avoid local model weights, continuous background sensors, polling, and unnecessary animation. Both `CoreOrb`'s `Ticker` and `AudioCaptureSource` stop immediately when `AppLifecycleState != resumed` or `AuthGate.lock()` is called; `CoreOrb` also pauses its `Ticker` when `CoreStage.hidden`.

## Android platform & permissions
`android/` is versioned (`com.viniciusnpaula.ultron_mobile`, `allowBackup=false`, `data_extraction_rules.xml`, desugaring, release signing config):
- `INTERNET`: AI/STT providers, GitHub updater, and LAN Desktop pairing.
- `RECORD_AUDIO`: requested on demand, strictly blocked unless `AuthGate.isAuthenticated == true` and `AppLifecycleState == resumed`.
- `REQUEST_INSTALL_PACKAGES`: in-app APK updater via `open_filex` (OS confirmation still required).
- `UltronTileService` (`BIND_QUICK_SETTINGS_TILE`): launches `MainActivity` and defers action until `AuthGate` unlocks.
- `UltronNotificationListenerService` (`BIND_NOTIFICATION_LISTENER_SERVICE`): opt-in only, disabled by default (`fail-closed`), requires both Android OS permission and `AuthGate.isAuthenticated == true`.

CI still runs `flutter create --platforms=android --org com.viniciusnpaula --project-name=ultron_mobile .` and restores committed `pubspec.yaml` and `android/` before building.

## Setup/build
Install Flutter stable and Android SDK; run `flutter pub get`, `dart analyze`, `flutter test`, then `flutter build apk --release`. APK output: `build/app/outputs/flutter-apk/app-release.apk`. Without `android/key.properties` a local release build is signed with the debug key, so it cannot replace an installed release build.

## Release
Pushing a `vX.Y.Z` tag builds, verifies with `apksigner`, and publishes a GitHub Release containing `app-release.apk`. Required repository secrets: `ANDROID_KEYSTORE_BASE64` (base64 of the `.jks`/PKCS12 store), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. See [docs/release-checklist.md](docs/release-checklist.md) for the full release and Galaxy A34 5G validation checklist.

Keep a backup of the keystore and its password somewhere outside this repository: an update signed with a different key cannot be installed over the previous build, so losing the keystore ends the update path for installed users.

## Security/scope
The app starts locked. Face or fingerprint unlock goes through Android's own biometric prompt (`local_auth`). After `PinVault.freeAttempts` wrong PINs the vault enforces exponential backoff from 30s up to 15 minutes. The PIN is stored as PBKDF2-HMAC-SHA256 (120k iterations, 16-byte random salt) and the SQLCipher passphrase is a 256-bit random key in `flutter_secure_storage`. Audio PCM/WAV is processed strictly in memory without temporary audio files or secret logging.
