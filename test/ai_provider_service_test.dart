import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/ai_provider_service.dart';

void main() {
  group('buildAiMessages', () {
    test('drops system turns and empty content', () {
      final messages = buildAiMessages('oi', [
        {'role': 'system', 'content': 'instruções'},
        {'role': 'user', 'content': 'olá'},
        {'role': 'assistant', 'content': '   '},
        {'role': 'assistant', 'content': 'olá, humano'},
      ]);
      expect(messages, [
        {'role': 'user', 'content': 'olá'},
        {'role': 'assistant', 'content': 'olá, humano'},
        {'role': 'user', 'content': 'oi'},
      ]);
    });

    test('caps the history window at 12 turns', () {
      final history = List.generate(
        30,
        (i) => {'role': 'user', 'content': 'm$i'},
      );
      final messages = buildAiMessages('agora', history);
      expect(messages.length, 13);
      expect(messages.first['content'], 'm0');
      expect(messages.last, {'role': 'user', 'content': 'agora'});
    });

    test('formats multimodal vision payload when imageBase64 is supplied', () {
      final messages = buildAiMessages(
        'Analise esta imagem tática',
        const [],
        imageBase64:
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      );
      expect(messages.length, 1);
      final turn = messages.first;
      expect(turn['role'], 'user');
      final content = turn['content'] as List;
      expect(content.length, 2);
      expect(
          content[0], {'type': 'text', 'text': 'Analise esta imagem tática'});
      expect((content[1] as Map)['type'], 'image_url');
      expect(((content[1] as Map)['image_url'] as Map)['url'],
          contains('data:image/jpeg;base64,'));
    });
  });

  group('parseAiReply', () {
    test('returns the assistant content', () {
      final body = jsonEncode({
        'choices': [
          {
            'message': {'content': 'tudo certo'},
          },
        ],
      });
      expect(parseAiReply(body), 'tudo certo');
    });

    test('rejects an empty answer', () {
      final body = jsonEncode({
        'choices': [
          {
            'message': {'content': ''},
          },
        ],
      });
      expect(() => parseAiReply(body), throwsFormatException);
    });

    test('rejects a body without choices', () {
      expect(() => parseAiReply('{}'), throwsA(isA<Exception>()));
    });
  });

  group('redactSecret', () {
    test('removes the key from provider errors', () {
      expect(
        redactSecret('Invalid key sk-abc123 for model', 'sk-abc123'),
        'Invalid key [chave ocultada] for model',
      );
    });

    test('leaves the message alone when there is no key', () {
      expect(redactSecret('falha', '  '), 'falha');
    });
  });

  group('AiProviderConfig & model migration', () {
    test('copyWith and JSON serialization preserve fields', () {
      const original = AiProviderConfig(
        id: 'p1',
        name: 'Groq',
        baseUrl: 'https://api.groq.com/openai/v1',
        model: 'openai/gpt-oss-120b',
        apiKey: 'gsk_1234567890',
        enabled: true,
        priority: 0,
      );
      final updated = original.copyWith(enabled: false, priority: 2);
      final restored = AiProviderConfig.fromJson(updated.toJson());
      expect(restored.id, 'p1');
      expect(restored.name, 'Groq');
      expect(restored.enabled, isFalse);
      expect(restored.priority, 2);
    });

    test('migrates old llama models on Groq to openai/gpt-oss-120b', () {
      expect(
        AiProviderStore.normalizeModelForUrl(
          'https://api.groq.com/openai/v1',
          'llama-3.3-70b-versatile',
        ),
        'openai/gpt-oss-120b',
      );
      expect(
        AiProviderStore.normalizeModelForUrl(
          'https://api.groq.com/openai/v1',
          'llama3-70b-8192',
        ),
        'openai/gpt-oss-120b',
      );
      expect(
        AiProviderStore.normalizeModelForUrl(
          'https://api.openai.com/v1',
          'gpt-4.1-mini',
        ),
        'gpt-4.1-mini',
      );
    });

    test(
        'parseChatModelsList filters audio/guard models and prioritizes GPT-OSS',
        () {
      final raw = jsonEncode({
        'data': [
          {'id': 'whisper-large-v3'},
          {'id': 'meta-llama/llama-prompt-guard-2-86m'},
          {'id': 'qwen/qwen3-32b'},
          {'id': 'openai/gpt-oss-120b'},
        ],
      });
      final models = parseChatModelsList(raw);
      expect(models, ['openai/gpt-oss-120b', 'qwen/qwen3-32b']);
    });

    test(
        'FreeProviderPreset catalog includes 9 free providers and zero-key Pollinations',
        () {
      expect(FreeProviderPreset.catalog.length, 9);
      final zeroKey = FreeProviderPreset.catalog.first;
      expect(zeroKey.requiresKey, isFalse);
      expect(zeroKey.baseUrl, contains('pollinations.ai'));

      const cfg = AiProviderConfig(
        id: 'p_free',
        name: 'Pollinations Free',
        baseUrl: 'https://text.pollinations.ai/openai',
        model: 'openai',
        apiKey: '',
      );
      expect(cfg.isKeylessProvider, isTrue);
      expect(cfg.hasUsableCredentials, isTrue);
      expect(cfg.effectiveToken, 'free');
    });

    test('detects vision-capable models and recommends multimodal fallbacks',
        () {
      expect(AiProviderStore.isVisionCapableModel('gemini-2.5-flash'), isTrue);
      expect(
          AiProviderStore.isVisionCapableModel(
              'qwen/qwen2.5-vl-72b-instruct:free'),
          isTrue);
      expect(
          AiProviderStore.isVisionCapableModel(
              'meta-llama/llama-4-scout-17b-16e-instruct'),
          isTrue);
      expect(
          AiProviderStore.isVisionCapableModel('openai/gpt-oss-120b'), isFalse);

      final visionFallbacks = AiProviderStore.fallbackModelsFor(
        'https://openrouter.ai/api/v1',
        'deepseek/deepseek-r1:free',
        requiresVision: true,
      );
      expect(
          visionFallbacks.any((m) => m.contains('vl') || m.contains('gemini')),
          isTrue);
    });
  });

  group('AiFailover circuit breaker & HTTP failure short-circuit', () {
    setUp(() => AiFailover.resetCircuitBreakers());
    tearDown(() => AiFailover.resetCircuitBreakers());

    test(
        'skips remaining fallback models on 401/429 and opens cooldown circuit breaker',
        () async {
      final calls = <String>[];
      var nowTime = DateTime.utc(2026, 11, 19, 15, 0, 0);

      final store = _InMemoryProviderStore([
        const AiProviderConfig(
          id: 'p_groq',
          name: 'Groq Primary',
          baseUrl: 'https://api.groq.com/openai/v1',
          model: 'openai/gpt-oss-120b',
          apiKey: 'gsk_invalid',
          enabled: true,
          priority: 0,
        ),
        const AiProviderConfig(
          id: 'p_backup',
          name: 'Backup Free',
          baseUrl: 'https://text.pollinations.ai/openai',
          model: 'openai',
          apiKey: 'free',
          enabled: true,
          priority: 1,
        ),
      ]);

      final failover = AiFailover(
        store: store,
        now: () => nowTime,
        httpFactory: () => _FakeHttpClient((uri, bodyMap) {
          final model = '${bodyMap['model']}';
          calls.add('${uri.host}:$model');
          if (uri.host == 'api.groq.com') {
            return const _FakeHttpReply(401, '{"error":"invalid_api_key"}');
          }
          return _FakeHttpReply(
            200,
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'OK backup'},
                },
              ],
            }),
          );
        }),
      );

      final reply1 = await failover.ask('teste');
      expect(reply1.text, 'OK backup');
      expect(reply1.provider, 'Backup Free');
      expect(reply1.failedAttempts, 1);
      expect(reply1.failedProviders, ['Groq Primary']);
      // Should abort Groq immediately after 401 instead of trying all 4 Groq fallback models.
      expect(calls.where((c) => c.startsWith('api.groq.com')).length, 1);

      // Second request within authCooldown skips Groq completely.
      calls.clear();
      final reply2 = await failover.ask('teste 2');
      expect(reply2.text, 'OK backup');
      expect(reply2.failedAttempts, 0);
      expect(calls, ['text.pollinations.ai:openai']);

      // After cooldown expires, Groq is eligible again.
      nowTime = nowTime.add(const Duration(minutes: 3));
      calls.clear();
      await failover.ask('teste 3');
      expect(calls.where((c) => c.startsWith('api.groq.com')).length, 1);

      // Same short-circuit + 45s circuit cooldown applies to HTTP 429 rate-limit.
      AiFailover.resetCircuitBreakers();
      calls.clear();
      final failover429 = AiFailover(
        store: store,
        now: () => nowTime,
        httpFactory: () => _FakeHttpClient((uri, bodyMap) {
          final model = '${bodyMap['model']}';
          calls.add('${uri.host}:$model');
          if (uri.host == 'api.groq.com') {
            return const _FakeHttpReply(429, '{"error":"rate_limit"}');
          }
          return _FakeHttpReply(
            200,
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'OK 429 fallback'},
                },
              ],
            }),
          );
        }),
      );
      final reply429 = await failover429.ask('teste 429');
      expect(reply429.text, 'OK 429 fallback');
      expect(calls.where((c) => c.startsWith('api.groq.com')).length, 1);
      calls.clear();
      await failover429.ask('teste 429 cached');
      expect(calls, ['text.pollinations.ai:openai']);
    });

    test('extracts provider usage tokens when present and estimates when omitted',
        () async {
      final store = _InMemoryProviderStore([
        const AiProviderConfig(
          id: 'p_usage',
          name: 'Groq Usage',
          baseUrl: 'https://api.groq.com/openai/v1',
          model: 'openai/gpt-oss-120b',
          apiKey: 'gsk_valid',
          enabled: true,
          priority: 0,
        ),
      ]);

      final withUsage = AiFailover(
        store: store,
        httpFactory: () => _FakeHttpClient((_, __) => _FakeHttpReply(
              200,
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': 'Resposta com telemetria real'},
                  },
                ],
                'usage': {
                  'prompt_tokens': 120,
                  'completion_tokens': 45,
                  'total_tokens': 165,
                },
              }),
            )),
      );
      final r1 = await withUsage.ask('status do sistema');
      expect(r1.promptTokens, 120);
      expect(r1.completionTokens, 45);
      expect(r1.totalTokens, 165);
      expect(r1.tokensEstimated, isFalse);
      expect(r1.usedFailover, isFalse);

      final withoutUsage = AiFailover(
        store: store,
        httpFactory: () => _FakeHttpClient((_, __) => _FakeHttpReply(
              200,
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': 'Resposta sem campo usage'},
                  },
                ],
              }),
            )),
      );
      final r2 = await withoutUsage.ask(
        'prompt de teste com vinte chars',
        systemPrompt: 'system prompt curto',
      );
      expect(r2.tokensEstimated, isTrue);
      expect(r2.promptTokens, greaterThan(0));
      expect(r2.completionTokens, greaterThan(0));
      expect(r2.totalTokens, r2.promptTokens + r2.completionTokens);

      var telemetry = SessionTelemetry.initial();
      telemetry = telemetry.recordReply(r1);
      telemetry = telemetry.recordReply(
        AiReply(
          provider: 'Pollinations Free',
          text: 'fallback',
          failedAttempts: 1,
          elapsedMs: 910,
          promptTokens: r2.promptTokens,
          completionTokens: r2.completionTokens,
          totalTokens: r2.totalTokens,
          tokensEstimated: true,
          failedProviders: const ['Groq Usage'],
        ),
      );
      expect(telemetry.turns, 2);
      expect(telemetry.promptTokens, 120 + r2.promptTokens);
      expect(telemetry.completionTokens, 45 + r2.completionTokens);
      expect(telemetry.hasEstimatedTokens, isTrue);
      expect(telemetry.lastUsedFailover, isTrue);
      expect(telemetry.failoverEvents, 1);
      expect(telemetry.lastLatencyMs, 910);
      expect(telemetry.realTokens, 165);
      expect(telemetry.estimatedTokens, r2.totalTokens);
      expect(telemetry.totalFailedAttempts, 1);
      expect(telemetry.byProvider['Groq Usage']?.turns, 1);
      expect(telemetry.byProvider['Groq Usage']?.failedAttempts, 1);
      expect(telemetry.byProvider['Groq Usage']?.realTokens, 165);
      expect(telemetry.byProvider['Pollinations Free']?.turns, 1);
      expect(telemetry.byProvider['Pollinations Free']?.failovers, 1);
      expect(telemetry.byProvider['Pollinations Free']?.estimatedTokens, r2.totalTokens);
      expect(telemetry.failoverHistory.length, 1);
      expect(telemetry.failoverHistory.first.resolvedProvider, 'Pollinations Free');
      expect(telemetry.failoverHistory.first.failedProviders, ['Groq Usage']);
      expect(telemetry.withActiveProvider('Outro').byProvider.length, 2);
      expect(SessionTelemetry.formatCompactTokens(1540), '1.5k');
    });
  });
}

class _InMemoryProviderStore extends AiProviderStore {
  _InMemoryProviderStore(this._providers) : super(storage: null);
  final List<AiProviderConfig> _providers;

  @override
  Future<List<AiProviderConfig>> load() async => _providers;
}

class _FakeHttpReply {
  const _FakeHttpReply(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._handler);

  final _FakeHttpReply Function(Uri uri, Map<String, dynamic> body) _handler;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async =>
      _FakeHttpClientRequest(url, _handler);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  ContentType? contentType;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this._uri, this._handler);

  final Uri _uri;
  final _FakeHttpReply Function(Uri uri, Map<String, dynamic> body) _handler;
  final BytesBuilder _buffer = BytesBuilder();

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  void add(List<int> data) => _buffer.add(data);

  @override
  Future<HttpClientResponse> close() async {
    final decoded = utf8.decode(_buffer.takeBytes());
    final map = decoded.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(decoded) as Map);
    final res = _handler(_uri, map);
    return _FakeHttpClientResponse(res.statusCode, res.body);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(this.statusCode, String body)
      : super(Stream<List<int>>.fromIterable([utf8.encode(body)]));

  @override
  final int statusCode;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
