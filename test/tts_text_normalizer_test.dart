import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/tts_text_normalizer.dart';

void main() {
  test('normalizes dotted U.L.T.R.O.N. variants to Ultron', () {
    expect(TtsTextNormalizer.normalize('U.L.T.R.O.N. online'), 'Ultron online');
    expect(TtsTextNormalizer.normalize('u.l.t.r.o.n'), 'Ultron');
    expect(TtsTextNormalizer.normalize('U.L.T.R.O.N pronto'), 'Ultron pronto');
  });

  test('removes dots from dotted alphabetical acronyms', () {
    expect(TtsTextNormalizer.normalize('I.A. local'), 'IA local');
    expect(
      TtsTextNormalizer.normalize('P.I.N. e A.P.I. configurados'),
      'PIN e API configurados',
    );
  });

  test('preserves version numbers, IP addresses, decimals, and URLs', () {
    expect(TtsTextNormalizer.normalize('v0.3.0'), 'v0.3.0');
    expect(TtsTextNormalizer.normalize('192.168.0.1'), '192.168.0.1');
    expect(TtsTextNormalizer.normalize('pi = 3.14'), 'pi = 3.14');
    expect(
      TtsTextNormalizer.normalize('Veja https://api.groq.com/openai/v1'),
      'Veja https://api.groq.com/openai/v1',
    );
  });
}
