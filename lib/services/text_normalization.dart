/// Shared accent-folding and phrase-normalization helpers for Brazilian
/// Portuguese voice matching, barge-in detection, corrections, and shortcuts.
class PtBrTextNormalizer {
  PtBrTextNormalizer._();

  static const Map<String, String> _diacriticMap = <String, String>{
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
  };

  /// Returns a lowercase ASCII string with the exact same character length as
  /// [text], folding Portuguese diacritics 1:1 and replacing punctuation with
  /// spaces.
  static String foldSameLength(String text) {
    final lower = text.toLowerCase();
    final buffer = StringBuffer();
    for (var i = 0; i < lower.length; i++) {
      final ch = _diacriticMap[lower[i]] ?? lower[i];
      final code = ch.codeUnitAt(0);
      final isAlphaNum =
          (code >= 97 && code <= 122) || (code >= 48 && code <= 57);
      buffer.write(isAlphaNum ? ch : ' ');
    }
    return buffer.toString();
  }

  /// Normalizes [text] into collapsed lowercase ASCII words.
  static String normalizePhrase(String text) {
    return foldSameLength(text).replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
