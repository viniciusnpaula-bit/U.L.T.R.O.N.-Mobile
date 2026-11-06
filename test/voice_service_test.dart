import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/voice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const ttsChannel = MethodChannel('flutter_tts');
  const storageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getEngines':
          return ['com.samsung.android.tts', 'com.google.android.tts'];
        case 'getDefaultEngine':
          return 'com.samsung.android.tts';
        case 'getVoices':
          return [
            {
              'name': 'samsung',
              'locale': 'pt-BR',
              'quality': 'normal',
              'network_required': '0',
            },
            {
              'name': 'google',
              'locale': 'pt-BR',
              'quality': 'very high',
              'network_required': '0',
            },
          ];
        default:
          return 1;
      }
    });
  });

  test('prefere o motor Google e aplica o timbre depois da voz', () async {
    final service = VoiceService();
    await service.initialize();

    final engine = calls.firstWhere((c) => c.method == 'setEngine');
    expect(engine.arguments, 'com.google.android.tts');

    final voiceIndex = calls.indexWhere((c) => c.method == 'setVoice');
    final pitchIndex = calls.indexWhere((c) => c.method == 'setPitch');
    expect(voiceIndex, greaterThan(-1));
    expect(pitchIndex, greaterThan(voiceIndex));
    expect(service.activeVoiceName, 'google');
  });
}
