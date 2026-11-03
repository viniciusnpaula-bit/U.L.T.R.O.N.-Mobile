# U.L.T.R.O.N. Mobile

Flutter/Dart Android node autonomous and independent of Desktop. Target: Samsung Galaxy A34 5G (Dimensity 1080, Mali-G68, 6–8 GB RAM). No local large LLM; language reasoning can use remote API configured locally.

## Architecture
- `lib/core/security`: biometric gate; PIN verifier injected, no hardcoded PIN.
- `lib/ui/screens`: access HUD and core stage UI.
- `lib/services`: native TTS and local Markdown vault.
- `shaders`: crimson fragment shader source.
Desktop conventions: model output cannot authorize actions; sensitive operations require confirmation; memory/preferences remain local.

## Performance
Avoid local model weights, continuous sensors, polling and unnecessary animation. Ticker stops when lifecycle is not resumed. Test profile/release builds on device; shader uses analytic rings without loops.

## Android platform
`android/` is versioned, not generated ad hoc: the manifest (INTERNET, REQUEST_INSTALL_PACKAGES, `allowBackup=false`), the app id `com.viniciusnpaula.ultron_mobile`, core library desugaring and the release signing config live here. CI still runs `flutter create --platforms=android --org com.viniciusnpaula --project-name=ultron_mobile .` to fill the files Flutter owns (Gradle plugin versions, wrapper, icons) and then restores the versioned copies. Use the same `--org` locally: a different id puts `MainActivity` in another package and the app crashes at launch.

## Setup/build
Install Flutter stable and Android SDK; run `flutter doctor`, `flutter pub get`, then `flutter build apk --release`. APK output: `build/app/outputs/flutter-apk/app-release.apk`. Without `android/key.properties` a local release build is signed with the debug key, so it cannot replace an installed release build.

## Release
Pushing a `vX.Y.Z` tag builds, verifies with `apksigner` and publishes a GitHub Release containing `app-release.apk`; that release is what the in-app updater reads. Required repository secrets: `ANDROID_KEYSTORE_BASE64` (base64 of the `.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. The job fails instead of publishing when they are missing.

## Security/scope
Biometric uses local_auth: the app starts locked and the core screen only opens after biometrics or the PIN. The PIN is stored as PBKDF2-HMAC-SHA256 (120k iterations, 16-byte random salt) in `flutter_secure_storage`; the plain PIN is never persisted. `/security` reports the real gate state and can lock the session. There is no brute-force lockout yet. Conversation history is excluded from cloud backup and device transfer (`allowBackup=false` plus `data_extraction_rules.xml`). Session policy does not grant OS permissions. Obsidian needs app-accessible directory; shared Documents requires SAF. Notification listener, quick tile, SQLCipher, runtime shader binding, microphone and full stage are still follow-up work and are not claimed complete.
