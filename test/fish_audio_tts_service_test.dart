import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:ultron_mobile/services/voice_service.dart';

class _SilentTts extends FlutterTts {
  final List<String> spoken = <String>[];

  @override
  Future<dynamic> get getVoices async => const [
        {
          'name': 'pt-br-x-ptd-local',
          'locale': 'pt-BR',
          'network_required': '0',
          'quality': 'very high',
        },
      ];

  @override
  Future<dynamic> setLanguage(String language) async => 1;

  @override
  Future<dynamic> setPitch(double pitch) async => 1;

  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;

  @override
  Future<dynamic> setVolume(double volume) async => 1;

  @override
  Future<dynamic> setVoice(Map<String, String> voice) async => 1;

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => 1;

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    spoken.add(text);
    return 1;
  }

  @override
  Future<dynamic> stop() async => 1;
}

class _RealHttpOverrides extends HttpOverrides {}

HttpClient _realHttpClient() =>
    HttpOverrides.runWithHttpOverrides(HttpClient.new, _RealHttpOverrides());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FishAudioTtsService persists config and builds language payload',
      () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final service = FishAudioTtsService();
    await service.saveConfig(
      const FishAudioConfig(
        enabled: true,
        apiKey: ' secret-key ',
        referenceId: ' ref-ultron-123 ',
        language: 'pt',
        model: 's2-pro',
      ),
    );

    final reloaded = FishAudioTtsService();
    final cfg = await reloaded.loadConfig();
    expect(cfg.isActive, isTrue);
    expect(cfg.apiKey, 'secret-key');
    expect(cfg.referenceId, 'ref-ultron-123');
    expect(cfg.language, 'pt');
    expect(cfg.model, 's2-pro');

    final ptPayload = FishAudioTtsService.buildPayload('Olá', cfg);
    expect(ptPayload['language'], 'pt');
    expect(ptPayload['reference_id'], 'ref-ultron-123');
    expect(ptPayload['format'], 'mp3');

    final autoPayload = FishAudioTtsService.buildPayload(
      'Olá',
      cfg.copyWith(language: 'auto'),
    );
    expect(autoPayload.containsKey('language'), isFalse);
  });

  test('FishAudioTtsService sends headers + JSON body and handles HTTP errors',
      () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final requests = <Map<String, Object?>>[];
    var nextStatus = HttpStatus.ok;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      final rawBody = await utf8.decoder.bind(req).join();
      requests.add({
        'auth': req.headers.value(HttpHeaders.authorizationHeader),
        'model': req.headers.value('model'),
        'body': jsonDecode(rawBody),
      });
      req.response.statusCode = nextStatus;
      if (nextStatus == HttpStatus.ok) {
        req.response.add([1, 2, 3, 4, 5]);
      } else {
        req.response.write('{"message":"Invalid token"}');
      }
      await req.response.close();
    });

    final service = FishAudioTtsService(
      endpoint:
          Uri.parse('http://${server.address.address}:${server.port}/tts'),
      httpClientFactory: _realHttpClient,
      initialConfig: const FishAudioConfig(
        enabled: true,
        apiKey: 'fish-key-xyz',
        referenceId: 'ultron-ref-id',
        language: 'pt',
        model: 's2.1-pro',
      ),
    );

    final audio = await service.synthesize('Sistemas online.');
    expect(audio, Uint8List.fromList([1, 2, 3, 4, 5]));
    expect(requests.length, 1);
    expect(requests.first['auth'], 'Bearer fish-key-xyz');
    expect(requests.first['model'], 's2.1-pro');
    final body = requests.first['body']! as Map<String, dynamic>;
    expect(body['reference_id'], 'ultron-ref-id');
    expect(body['language'], 'pt');
    expect(body['text'], 'Sistemas online.');

    nextStatus = HttpStatus.unauthorized;
    await expectLater(
      service.synthesize('Falha esperada'),
      throwsA(
        isA<FishAudioException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', 'Invalid token'),
      ),
    );
  });

  test(
      'VoiceService uses Fish Audio via native audio channel and falls back to Android TTS on API failure',
      () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    var serverStatus = HttpStatus.ok;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      await utf8.decoder.bind(req).join();
      req.response.statusCode = serverStatus;
      if (serverStatus == HttpStatus.ok) {
        req.response.add([9, 8, 7]);
      } else {
        req.response.write('{"detail":"quota exceeded"}');
      }
      await req.response.close();
    });

    const channel = MethodChannel('com.viniciusnpaula.ultron_mobile/device');
    final playedCalls = <Map<Object?, Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'playTtsAudioBytes') {
        playedCalls.add(call.arguments as Map<Object?, Object?>);
        return true;
      }
      return true;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final fish = FishAudioTtsService(
      endpoint:
          Uri.parse('http://${server.address.address}:${server.port}/tts'),
      httpClientFactory: _realHttpClient,
      initialConfig: const FishAudioConfig(
        enabled: true,
        apiKey: 'fish-key',
        referenceId: 'ultron-id',
        language: 'pt',
        model: 's2.1-pro',
      ),
    );
    final fakeTts = _SilentTts();
    final voice = VoiceService(tts: fakeTts, fishService: fish);

    expect(voice.activeVoiceLabel, 'Fish Audio (pt • s2.1-pro)');

    await voice.speak('Olá operador.');
    expect(playedCalls.length, 1);
    expect(playedCalls.first['bytes'], Uint8List.fromList([9, 8, 7]));
    expect(fakeTts.spoken, isEmpty);
    expect(voice.lastFishError, isNull);

    // Fallback when Fish Audio fails
    serverStatus = HttpStatus.paymentRequired;
    await voice.speak('Modo offline.');
    expect(fakeTts.spoken, ['Modo offline.']);
    expect(voice.lastFishError, contains('quota exceeded'));
  });
}
