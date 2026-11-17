import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/speech_text.dart';

void main() {
  group('SpeechText.sanitize', () {
    test('strips Markdown, action tags, emojis, and expands U.L.T.R.O.N.', () {
      const raw =
          '🔦 **U.L.T.R.O.N.** ativou a `lanterna` em 32.5°C! [ACTION:TORCH_ON]';
      final clean = SpeechText.sanitize(raw);
      expect(clean, contains('Ultron ativou a lanterna'));
      expect(clean, contains('32.5 graus'));
      expect(clean, isNot(contains('**')));
      expect(clean, isNot(contains('`')));
      expect(clean, isNot(contains('ACTION:TORCH_ON')));
      expect(clean, isNot(contains('🔦')));
    });

    test('removes code blocks and replaces with natural speech summary', () {
      const raw = 'Segue o script:\n```python\nprint("hello")\n```\nPronto!';
      final clean = SpeechText.sanitize(raw);
      expect(clean, contains('Trecho de código exibido na tela'));
      expect(clean, isNot(contains('print')));
    });
  });

  group('SpeechText.prepareChunks', () {
    test('splits long paragraphs into natural sentence chunks <= 220 chars', () {
      final longText = List.generate(
        8,
        (i) => 'Esta é a sentença número ${i + 1} do relatório tático do núcleo.',
      ).join(' ');
      final chunks = SpeechText.prepareChunks(longText);
      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(220));
      }
    });
  });

  group('WakeWord phonetic & fuzzy matcher', () {
    test('detects Ultron and common pt-BR STT phonetic variations', () {
      expect(WakeWord.contains('Ei Ultron que horas são'), isTrue);
      expect(WakeWord.contains('Oi Outron ligar lanterna'), isTrue);
      expect(WakeWord.contains('Ei Uoltron ler mensagens'), isTrue);
      expect(WakeWord.contains('Fala Ultrom tudo bem'), isTrue);
      expect(WakeWord.contains('Bom dia pessoal'), isFalse);
    });

    test('extracts inline command after wake word', () {
      expect(
        WakeWord.extractCommand('Ei Ultron, ligar a lanterna'),
        'ligar a lanterna',
      );
      expect(
        WakeWord.extractCommand('Oi Outron que horas são?'),
        'que horas são?',
      );
      expect(WakeWord.extractCommand('Ultron'), isEmpty);
    });
  });
}
