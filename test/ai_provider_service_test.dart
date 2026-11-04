import 'dart:convert';

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

    test('parseChatModelsList filters audio/guard models and prioritizes GPT-OSS', () {
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

    test('FreeProviderPreset catalog includes 9 free providers and zero-key Pollinations', () {
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
  });
}
