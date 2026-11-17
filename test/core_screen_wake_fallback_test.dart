import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ultron_mobile/core/security/auth_gate.dart';
import 'package:ultron_mobile/core/security/pin_vault.dart';
import 'package:ultron_mobile/services/audio_capture_service.dart';
import 'package:ultron_mobile/services/stt_service.dart';
import 'package:ultron_mobile/services/voice_service.dart';
import 'package:ultron_mobile/ui/screens/core_screen.dart';

class _QuietTts extends FlutterTts {
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

class _NoopCapture implements AudioCaptureSource {
  @override
  Stream<Uint8List> get frames => const Stream.empty();

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
  testWidgets(
    'CoreScreen hearing button falls back to offline sherpa sentinel when no STT key is configured and handles wake event',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues(const <String, String>{});
      const deviceChannel =
          MethodChannel('com.viniciusnpaula.ultron_mobile/device');
      final calls = <MethodCall>[];
      var sentinelEnabled = false;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(deviceChannel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'setAudioSentinel':
            sentinelEnabled = (call.arguments as Map)['enabled'] as bool;
            return sentinelEnabled;
          case 'isAudioSentinelRunning':
            return sentinelEnabled;
          case 'listenVoice':
            return 'que horas são';
          case 'speakOfflineFishVoice':
            return 'São dez horas.';
          case 'getDeviceStatus':
            return {
              'batteryLevel': 80,
              'isCharging': false,
              'batteryTempC': 30.0,
              'ramTotalMb': 6000,
              'ramFreeMb': 3000,
              'volumePercent': 50,
              'ringerMode': 'normal',
              'deviceModel': 'Galaxy A34 5G',
              'androidVersion': '14',
              'torchOn': false,
              'wifiConnected': true,
            };
          case 'isNotificationListenerEnabled':
            return false;
          default:
            return null;
        }
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(deviceChannel, null);
      });

      final gate = AuthGate();
      await gate.authenticatePin('1234', (_) async => true);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: CoreScreen(
            gate: gate,
            vault: PinVault(),
            voiceService: VoiceService(tts: _QuietTts()),
            captureSource: _NoopCapture(),
            sttService: GroqWhisperSttService(
              config: const SttConfig(
                  endpointUrl:
                      'https://api.groq.com/openai/v1/audio/transcriptions',
                  apiKey: ''),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      calls.clear();
      await tester.tap(find.byIcon(Icons.hearing_disabled));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        calls.any(
          (c) =>
              c.method == 'setAudioSentinel' &&
              (c.arguments as Map)['enabled'] == true,
        ),
        isTrue,
      );

      // Simulate native sherpa-onnx wake-word detection callback
      calls.clear();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        deviceChannel.name,
        deviceChannel.codec.encodeMethodCall(
          const MethodCall('onWakeWordDetected', 'Ultron'),
        ),
        (_) {},
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(calls.any((c) => c.method == 'listenVoice'), isTrue);
    },
  );
}
