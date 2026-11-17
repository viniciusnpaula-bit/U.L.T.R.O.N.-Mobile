import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/ai_provider_service.dart';
import 'package:ultron_mobile/services/stt_service.dart';

Uint8List _speechPcm({int samples = 320, int amplitude = 500}) {
  final bytes = Uint8List(samples * 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < samples; i++) {
    data.setInt16(i * 2, i.isEven ? amplitude : -amplitude, Endian.little);
  }
  return bytes;
}

class _InMemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = <String, String>{};

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
      _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }
}

void main() {
  test('rejects empty PCM and low-RMS silence without opening HTTP connection', () async {
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) {
      requests += 1;
      req.response.statusCode = 200;
      req.response.close();
    });

    final stt = GroqWhisperSttService(
      config: SttConfig(
        endpointUrl: 'http://127.0.0.1:${server.port}/transcriptions',
        apiKey: 'gsk_test_secret_123',
      ),
    );

    final emptyResult = await stt.transcribe(Uint8List(0));
    expect(emptyResult.error, 'sem_audio');

    final silentPcm = _speechPcm(amplitude: 10);
    final silenceResult = await stt.transcribe(silentPcm);
    expect(silenceResult.reason, 'sem_fala');
    expect(silenceResult.error, isNull);
    expect(requests, 0);
  });

  test('sends valid multipart/form-data with fala.wav and truncated prompt', () async {
    String? authHeader;
    String? contentTypeHeader;
    List<int> rawBody = <int>[];

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      authHeader = req.headers.value(HttpHeaders.authorizationHeader);
      contentTypeHeader = req.headers.contentType?.toString();
      rawBody = await req.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'text': '  Abrir histórico  ',
          'segments': [
            {
              'avg_logprob': -0.22,
              'no_speech_prob': 0.05,
              'compression_ratio': 1.15,
            }
          ],
        }));
      await req.response.close();
    });

    final stt = GroqWhisperSttService(
      config: SttConfig(
        endpointUrl: 'http://127.0.0.1:${server.port}/transcriptions',
        apiKey: 'gsk_test_secret_123',
      ),
    );

    final longPrompt = 'A' * 1200;
    final result = await stt.transcribe(_speechPcm(), prompt: longPrompt);

    expect(result.error, isNull);
    expect(result.text, 'Abrir histórico');
    expect(result.confidence?.avgLogprob, -0.22);
    expect(authHeader, 'Bearer gsk_test_secret_123');
    expect(contentTypeHeader, contains('multipart/form-data'));

    final bodyText = latin1.decode(rawBody);
    expect(bodyText, contains('name="file"; filename="fala.wav"'));
    expect(bodyText, contains('RIFF'));
    expect(bodyText, contains('name="model"\r\n\r\nwhisper-large-v3'));
    expect(bodyText, contains('name="language"\r\n\r\npt'));
    expect(bodyText, contains('name="response_format"\r\n\r\nverbose_json'));
    expect(bodyText, contains('name="temperature"\r\n\r\n0'));
    expect(bodyText, contains('name="prompt"\r\n\r\n${'A' * 900}\r\n'));
    expect(bodyText, isNot(contains('A' * 901)));
  });

  test('discards Whisper hallucinations failing confidence thresholds', () async {
    final payloads = <Map<String, dynamic>>[
      {
        'text': 'Obrigado por assistir',
        'segments': [
          {'no_speech_prob': 0.60, 'compression_ratio': 1.1, 'avg_logprob': -0.2}
        ],
      },
      {
        'text': 'teste teste teste',
        'segments': [
          {'no_speech_prob': 0.1, 'compression_ratio': 2.40, 'avg_logprob': -0.2}
        ],
      },
      {
        'text': 'barulho incerto',
        'segments': [
          {'no_speech_prob': 0.1, 'compression_ratio': 1.2, 'avg_logprob': -1.0}
        ],
      },
    ];
    var idx = 0;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      await req.drain<void>();
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(payloads[idx++]));
      await req.response.close();
    });

    final stt = GroqWhisperSttService(
      config: SttConfig(
        endpointUrl: 'http://127.0.0.1:${server.port}/transcriptions',
        apiKey: 'gsk_test_secret_123',
      ),
    );

    for (var i = 0; i < payloads.length; i++) {
      final result = await stt.transcribe(_speechPcm());
      expect(result.text, isNull);
      expect(result.reason, 'baixa_confianca');
    }
  });

  test('retries once on 429/5xx, never retries 401/403, and redacts API key', () async {
    var calls = 0;
    final statuses = <int>[429, 200, 401];

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      await req.drain<void>();
      final code = statuses[calls++];
      req.response.statusCode = code;
      if (code == 200) {
        req.response.write(jsonEncode({'text': 'OK'}));
      } else {
        req.response.write(jsonEncode({
          'error': {'message': 'Invalid key gsk_super_secret_999'},
        }));
      }
      await req.response.close();
    });

    final stt = GroqWhisperSttService(
      config: SttConfig(
        endpointUrl: 'http://127.0.0.1:${server.port}/transcriptions',
        apiKey: 'gsk_super_secret_999',
      ),
    );

    final retried = await stt.transcribe(_speechPcm());
    expect(retried.text, 'OK');
    expect(calls, 2);

    final unauthorized = await stt.transcribe(_speechPcm());
    expect(calls, 3);
    expect(unauthorized.error, isNotNull);
    expect(unauthorized.error, isNot(contains('gsk_super_secret_999')));
    expect(unauthorized.error, contains('[chave ocultada]'));
  });

  test('opens circuit breaker after 2 consecutive failures and recovers after cooldown', () async {
    var serverCalls = 0;
    var returnError = true;
    var currentTime = DateTime.utc(2026, 11, 16, 12, 0, 0);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      serverCalls += 1;
      await req.drain<void>();
      if (returnError) {
        req.response.statusCode = 503;
      } else {
        req.response.statusCode = 200;
        req.response.write(jsonEncode({'text': 'Recuperado'}));
      }
      await req.response.close();
    });

    final stt = GroqWhisperSttService(
      config: SttConfig(
        endpointUrl: 'http://127.0.0.1:${server.port}/transcriptions',
        apiKey: 'gsk_test_secret_123',
      ),
      circuitCooldown: const Duration(seconds: 30),
      now: () => currentTime,
    );

    // 1st failure (initial + 1 retry = 2 HTTP calls)
    final f1 = await stt.transcribe(_speechPcm());
    expect(f1.error, isNotNull);
    expect(f1.error, isNot('disjuntor'));

    // 2nd failure opens circuit (initial + 1 retry = 4 total HTTP calls)
    final f2 = await stt.transcribe(_speechPcm());
    expect(f2.error, isNotNull);
    expect(serverCalls, 4);

    // Inside cooldown -> blocked locally without hitting server
    currentTime = currentTime.add(const Duration(seconds: 15));
    final blocked = await stt.transcribe(_speechPcm());
    expect(blocked.error, 'disjuntor');
    expect(serverCalls, 4);

    // After cooldown -> calls server again and recovers
    returnError = false;
    currentTime = currentTime.add(const Duration(seconds: 20));
    final recovered = await stt.transcribe(_speechPcm());
    expect(recovered.text, 'Recuperado');
    expect(serverCalls, 5);
  });

  test('AiProviderStore.resolveSttConfig reuses enabled Groq key automatically', () async {
    final store = AiProviderStore(storage: _InMemorySecureStorage());
    await store.save([
      const AiProviderConfig(
        id: '1',
        name: 'Groq',
        baseUrl: 'https://api.groq.com/openai/v1',
        model: 'openai/gpt-oss-120b',
        apiKey: 'gsk_auto_key',
      ),
    ]);

    final resolved = await store.resolveSttConfig();
    expect(resolved.endpointUrl, SttConfig.defaultEndpointUrl);
    expect(resolved.model, SttConfig.defaultModel);
    expect(resolved.apiKey, 'gsk_auto_key');

    await store.saveSttConfig(const SttConfig(
      endpointUrl: 'https://custom.stt/v1/audio/transcriptions',
      model: 'whisper-1',
      apiKey: 'sk_stt_dedicated',
    ));
    final explicit = await store.resolveSttConfig();
    expect(explicit.endpointUrl, 'https://custom.stt/v1/audio/transcriptions');
    expect(explicit.model, 'whisper-1');
    expect(explicit.apiKey, 'sk_stt_dedicated');
  });
}
