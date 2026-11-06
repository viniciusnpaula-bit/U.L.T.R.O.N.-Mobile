import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/fish_audio_tts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  final stored = <String, String>{};

  setUp(() {
    stored.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (call) async {
      final args = (call.arguments as Map?) ?? const {};
      switch (call.method) {
        case 'read':
          final key = args['key'] as String?;
          return key == null ? null : stored[key];
        case 'write':
          final key = args['key'] as String?;
          if (key == null) return null;
          stored[key] = args['value'] as String? ?? '';
          return null;
        case 'delete':
          stored.remove(args['key'] as String?);
          return null;
        case 'readAll':
          return Map<String, String>.from(stored);
        case 'deleteAll':
          stored.clear();
          return null;
        default:
          return null;
      }
    });
  });

  test('configuração só fica ativa com chave e voz preenchidas', () async {
    final fish = FishAudioTts();
    expect((await fish.loadConfig()).isConfigured, isFalse);

    await fish.saveConfig(apiKey: 'chave', voiceId: 'voz-123');
    final config = await fish.loadConfig();

    expect(config.isConfigured, isTrue);
    expect(config.apiKey, 'chave');
    expect(config.voiceId, 'voz-123');
  });

  test('payload do Fish Audio aponta para o modelo e pede MP3', () {
    final payload = FishAudioTts.buildPayload(
      'Sistemas online.',
      voiceId: 'voz-123',
    );

    expect(payload['text'], 'Sistemas online.');
    expect(payload['reference_id'], 'voz-123');
    expect(payload['format'], 'mp3');
    expect(payload.containsKey('references'), isFalse);
  });

  test('sem configuração não faz requisição', () async {
    var requested = false;
    final fish = FishAudioTts(
      httpFactory: () {
        requested = true;
        throw StateError('não deveria abrir conexão');
      },
    );

    final audio = await fish.synthesize(
      const FishAudioConfig(apiKey: '', voiceId: ''),
      'teste',
    );

    expect(audio, isNull);
    expect(requested, isFalse);
  });
}
