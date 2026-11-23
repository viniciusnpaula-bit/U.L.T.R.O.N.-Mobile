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

  group('WakeWord phonetic & fuzzy matcher (Multi-Profile)', () {
    setUp(() {
      WakeWord.setActiveProfile(WakeWordProfile.ultron);
    });

    tearDown(() {
      WakeWord.setActiveProfile(WakeWordProfile.ultron);
    });

    test('detects Ultron and common pt-BR STT phonetic variations', () {
      expect(WakeWord.contains('Ei Ultron que horas são'), isTrue);
      expect(WakeWord.contains('Oi Outron ligar lanterna'), isTrue);
      expect(WakeWord.contains('Ei Uoltron ler mensagens'), isTrue);
      expect(WakeWord.contains('Fala Ultrom tudo bem'), isTrue);
      expect(WakeWord.contains('Bom dia pessoal'), isFalse);
    });

    test('supports Jarvis, Edith, and Visão profiles with aliases and Levenshtein <= 1', () {
      // Jarvis
      WakeWord.setActiveProfile(WakeWordProfile.jarvis);
      expect(WakeWord.contains('Ei Jarvis ligar a lanterna'), isTrue);
      expect(WakeWord.contains('Oi Jarves que horas são'), isTrue);
      expect(WakeWord.contains('Fala Djarvis abrir agenda'), isTrue);
      expect(WakeWord.contains('Jarvis'), isTrue);
      expect(WakeWord.contains('Ei Ultron ligar a lanterna'), isFalse);

      // Edith
      WakeWord.setActiveProfile(WakeWordProfile.edith);
      expect(WakeWord.contains('Ei Edith status do sistema'), isTrue);
      expect(WakeWord.contains('Oi Edite ler mensagens'), isTrue);
      expect(WakeWord.contains('Fala Edit tocar música'), isTrue);
      expect(WakeWord.contains('Edith'), isTrue);
      expect(WakeWord.contains('Ei Jarvis status do sistema'), isFalse);

      // Visão
      WakeWord.setActiveProfile(WakeWordProfile.visao);
      expect(WakeWord.contains('Ei Visão previsão do tempo'), isTrue);
      expect(WakeWord.contains('Oi Vizão que horas são'), isTrue);
      expect(WakeWord.contains('Ok Vision pesquisar notícias'), isTrue);
      expect(WakeWord.contains('Visao'), isTrue);
      expect(WakeWord.contains('que horas são'), isFalse);
    });

    test('detectProfile identifies which wake-word profile triggered the phrase', () {
      expect(
        WakeWord.detectProfile('Ei Ultron abrir spotify'),
        WakeWordProfile.ultron,
      );
      expect(
        WakeWord.detectProfile('Oi Jarvis qual a temperatura'),
        WakeWordProfile.jarvis,
      );
      expect(
        WakeWord.detectProfile('Ok Edite ler notificações'),
        WakeWordProfile.edith,
      );
      expect(
        WakeWord.detectProfile('Fala Visão criar lembrete'),
        WakeWordProfile.visao,
      );
      expect(WakeWord.detectProfile('Bom dia operador'), isNull);
    });

    test('extracts inline command after wake word across all profiles', () {
      expect(
        WakeWord.extractCommand('Ei Ultron, ligar a lanterna'),
        'ligar a lanterna',
      );
      expect(
        WakeWord.extractCommand('Oi Outron que horas são?'),
        'que horas são?',
      );
      expect(
        WakeWord.extractCommand('Ei Jarvis, tocar rock no spotify'),
        'tocar rock no spotify',
      );
      expect(
        WakeWord.extractCommand('Ok Edite, verificar bateria'),
        'verificar bateria',
      );
      expect(
        WakeWord.extractCommand('Oi Visão, como está o clima hoje?'),
        'como está o clima hoje?',
      );
      expect(WakeWord.extractCommand('Ultron'), isEmpty);
      expect(WakeWord.extractCommand('Jarvis'), isEmpty);
    });
  });
}
