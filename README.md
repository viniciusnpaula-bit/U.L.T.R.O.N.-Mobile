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

## Setup/build
Install Flutter stable and Android SDK; run `flutter doctor`, `flutter pub get`, then `flutter build apk --release`. APK output: `build/app/outputs/flutter-apk/app-release.apk`.

## Security/scope
Biometric uses local_auth. PIN verification is delegated; production must implement salted hash verification and key storage via Android Keystore. Session policy does not grant OS permissions. Obsidian needs app-accessible directory; shared Documents requires SAF. Notification listener, quick tile, SQLCipher, runtime shader binding, microphone and full stage are still follow-up work and are not claimed complete.
