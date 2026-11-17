import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ultron_mobile/core/security/auth_gate.dart';
import 'package:ultron_mobile/core/security/pin_vault.dart';
import 'package:ultron_mobile/main.dart';
import 'package:ultron_mobile/services/audio_capture_service.dart';
import 'package:ultron_mobile/services/startup_coordinator.dart';
import 'package:ultron_mobile/services/stt_service.dart';
import 'package:ultron_mobile/services/voice_service.dart';
import 'package:ultron_mobile/ui/screens/boot_loading_screen.dart';
import 'package:ultron_mobile/ui/screens/core_screen.dart';

class _RecordingTts extends FlutterTts {
  final List<String> spoken = <String>[];

  @override
  Future<dynamic> setLanguage(String language) async => 1;

  @override
  Future<dynamic> setPitch(double pitch) async => 1;

  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;

  @override
  Future<dynamic> setVolume(double volume) async => 1;

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => 1;

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spoken.add(text);
    return 1;
  }

  @override
  Future<dynamic> get getVoices async => const <dynamic>[];

  @override
  Future<dynamic> stop() async => 1;
}

class _InMemoryStorage extends FlutterSecureStorage {
  const _InMemoryStorage();

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      null;
}

class _StubCapture implements AudioCaptureSource {
  @override
  Stream<Never> get frames => const Stream.empty();

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<AudioEffectsReport> start({int sampleRate = 16000}) async =>
      const AudioEffectsReport();

  @override
  Future<void> stop() async {}
}

void main() {
  testWidgets('UltronApp shows BootLoadingScreen while loading and speaks Ultron online only when ready', (tester) async {
    final gate = AuthGate();
    await gate.authenticatePin('1234', (_) async => true);

    final vaultCompleter = Completer<void>();
    final shaderCompleter = Completer<void>();
    final fakeTts = _RecordingTts();
    final voiceService = VoiceService(
      tts: fakeTts,
      storage: const _InMemoryStorage(),
    );
    final coordinator = StartupCoordinator(
      initVault: () => vaultCompleter.future,
      initAiProviders: () async {},
      initAudio: () => voiceService.initialize(),
      loadShader: () async {
        await shaderCompleter.future;
        return null;
      },
    );

    await tester.pumpWidget(
      UltronApp(
        gate: gate,
        vault: PinVault(),
        voiceService: voiceService,
        startupCoordinator: coordinator,
        audioCapture: _StubCapture(),
        sttService: GroqWhisperSttService(
          config: const SttConfig(endpointUrl: 'http://127.0.0.1:1', apiKey: 'k'),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(BootLoadingScreen), findsOneWidget);
    expect(find.byType(CoreScreen), findsNothing);
    expect(fakeTts.spoken, isEmpty);

    vaultCompleter.complete();
    await tester.pump();
    expect(find.byType(BootLoadingScreen), findsOneWidget);
    expect(find.byType(CoreScreen), findsNothing);
    expect(fakeTts.spoken, isEmpty);

    shaderCompleter.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(BootLoadingScreen), findsNothing);
    expect(find.byType(CoreScreen), findsOneWidget);
    expect(fakeTts.spoken, hasLength(1));
    expect(fakeTts.spoken.single.toLowerCase(), contains('ultron online'));
  });
}
