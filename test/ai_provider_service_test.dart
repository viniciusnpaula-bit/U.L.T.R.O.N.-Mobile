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
}
