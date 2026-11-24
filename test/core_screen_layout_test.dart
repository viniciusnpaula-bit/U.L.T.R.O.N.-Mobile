import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ultron_mobile/core/security/auth_gate.dart';
import 'package:ultron_mobile/core/security/pin_vault.dart';
import 'package:ultron_mobile/services/audio_capture_service.dart';
import 'package:ultron_mobile/services/stt_service.dart';
import 'package:ultron_mobile/services/voice_service.dart';
import 'package:ultron_mobile/ui/screens/core_screen.dart';

class _SilentTts extends FlutterTts {
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
  Future<dynamic> speak(String text, {bool focus = false}) async => 1;

  @override
  Future<dynamic> stop() async => 1;
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
  testWidgets('CoreScreen fits 360x800 portrait Galaxy A34 viewport without overflow and keeps TextField usable', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final gate = AuthGate();
    await gate.authenticatePin('1234', (_) async => true);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: CoreScreen(
          gate: gate,
          vault: PinVault(),
          voiceService: VoiceService(tts: _SilentTts()),
          captureSource: _StubCapture(),
          sttService: GroqWhisperSttService(
            config: const SttConfig(endpointUrl: 'http://127.0.0.1:1', apiKey: 'k'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('cockpit_telemetry_bar')), findsOneWidget);
    expect(find.text('Voz'), findsOneWidget);
    expect(find.text('Visão'), findsOneWidget);
    expect(find.text('Dispositivos'), findsOneWidget);
    final fieldSize = tester.getSize(find.byType(TextField));
    expect(fieldSize.width, greaterThanOrEqualTo(150));

    // Abre a gaveta lateral e navega para Engenharia sem erros
    await tester.tap(find.byKey(const Key('ultron_menu_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
    expect(find.text('Início'), findsOneWidget);
    expect(find.text('Celular'), findsOneWidget);
    expect(find.text('Inteligência'), findsOneWidget);
    expect(find.text('Memória'), findsOneWidget);
    expect(find.text('Engenharia'), findsOneWidget);
    expect(find.text('Configurações'), findsOneWidget);

    await tester.tap(find.text('Engenharia'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('NBR 5410'), findsOneWidget);
  });

  testWidgets('CoreScreen shows permanent sidebar on wide tablet layout', (tester) async {
    tester.view.physicalSize = const Size(1024, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final gate = AuthGate();
    await gate.authenticatePin('1234', (_) async => true);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: CoreScreen(
          gate: gate,
          vault: PinVault(),
          voiceService: VoiceService(tts: _SilentTts()),
          captureSource: _StubCapture(),
          sttService: GroqWhisperSttService(
            config: const SttConfig(endpointUrl: 'http://127.0.0.1:1', apiKey: 'k'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('ultron_menu_button')), findsNothing);
    expect(find.text('Engenharia'), findsOneWidget);
    expect(find.text('Segurança'), findsOneWidget);
  });
}
