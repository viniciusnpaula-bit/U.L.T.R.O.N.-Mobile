/// Normalizes text before sending it to the native TTS engine.
class TtsTextNormalizer {
  TtsTextNormalizer._();

  static final RegExp _dottedAcronymPattern = RegExp(
    r'(?<![A-Za-z0-9_/:.-])(?:(?:[A-Za-z]\.){2,}|(?:[A-Za-z]\.)+[A-Za-z])(?![A-Za-z0-9_/:.-])',
  );

  static const Map<String, String> _wordOverrides = <String, String>{
    'ultron': 'Ultron',
  };

  /// Collapses dotted alphabetical acronyms (for example `U.L.T.R.O.N.` ->
  /// `Ultron`, `I.A.` -> `IA`) while leaving decimals, versions, IPs, and URLs
  /// untouched.
  static String normalize(String text) {
    return text.replaceAllMapped(_dottedAcronymPattern, (match) {
      final compact = match.group(0)!.replaceAll('.', '');
      return _wordOverrides[compact.toLowerCase()] ?? compact;
    });
  }
}
