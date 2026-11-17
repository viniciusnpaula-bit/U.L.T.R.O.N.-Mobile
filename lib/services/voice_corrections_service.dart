import 'package:sqflite_sqlcipher/sqflite.dart' show ConflictAlgorithm;

import 'conversation_history.dart';
import 'text_normalization.dart';

class VoiceCorrection {
  const VoiceCorrection({
    this.id,
    required this.wrongPhrase,
    required this.normalizedWrong,
    required this.correctPhrase,
    required this.createdAt,
  });

  final int? id;
  final String wrongPhrase;
  final String normalizedWrong;
  final String correctPhrase;
  final DateTime createdAt;

  factory VoiceCorrection.fromMap(Map<String, Object?> map) => VoiceCorrection(
        id: map['id'] as int?,
        wrongPhrase: map['wrong_phrase'] as String,
        normalizedWrong: map['normalized_wrong'] as String,
        correctPhrase: map['correct_phrase'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

class VoiceCorrectionDraft {
  const VoiceCorrectionDraft({
    required this.wrongPhrase,
    required this.correctPhrase,
  });

  final String wrongPhrase;
  final String correctPhrase;
}

/// Manages user-taught STT vocabulary corrections persisted in SQLite.
class VoiceCorrectionsService {
  VoiceCorrectionsService({ConversationHistory? history})
      : _history = history ?? ConversationHistory.instance;

  final ConversationHistory _history;

  static final List<RegExp> _extractPatterns = <RegExp>[
    RegExp(
      r'^(?:nao|não)\s+(?:e|é)\s+(.+?),\s*(?:e|é)\s+(.+)$',
      caseSensitive: false,
    ),
    RegExp(
      r'^quis\s+dizer\s+(.+?)(?:,|\s+e)?\s+(?:nao|não)\s+(.+)$',
      caseSensitive: false,
    ),
    RegExp(
      r'^(?:corrija|troque|substitua)\s+(.+?)\s+(?:para|por)\s+(.+)$',
      caseSensitive: false,
    ),
  ];

  static String normalize(String text) =>
      PtBrTextNormalizer.normalizePhrase(text);

  /// Extracts a `(wrong, correct)` pair from explicit Portuguese correction
  /// utterances (`"não é X, é Y"`, `"corrija X para Y"`, `"quis dizer Y, não X"`).
  static VoiceCorrectionDraft? extractFromSentence(String sentence) {
    final trimmed = sentence.trim().replaceAll(RegExp(r'[.!?]+$'), '').trim();
    if (trimmed.isEmpty) return null;

    for (var i = 0; i < _extractPatterns.length; i++) {
      final match = _extractPatterns[i].firstMatch(trimmed);
      if (match == null) continue;
      final first = match.group(1)!.trim();
      final second = match.group(2)!.trim();
      if (first.isEmpty || second.isEmpty) continue;
      if (i == 1) {
        return VoiceCorrectionDraft(wrongPhrase: second, correctPhrase: first);
      }
      return VoiceCorrectionDraft(wrongPhrase: first, correctPhrase: second);
    }
    return null;
  }

  Future<VoiceCorrection> add(String wrongPhrase, String correctPhrase) async {
    final wrong = wrongPhrase.trim();
    final correct = correctPhrase.trim();
    final normalized = normalize(wrong);
    if (normalized.isEmpty || correct.isEmpty) {
      throw ArgumentError('Frase incorreta e correção não podem ser vazias.');
    }

    final db = await _history.database;
    final now = DateTime.now().toUtc();
    final id = await db.insert(
      'voice_corrections',
      <String, Object?>{
        'wrong_phrase': wrong,
        'normalized_wrong': normalized,
        'correct_phrase': correct,
        'created_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return VoiceCorrection(
      id: id,
      wrongPhrase: wrong,
      normalizedWrong: normalized,
      correctPhrase: correct,
      createdAt: now,
    );
  }

  Future<List<VoiceCorrection>> list() async {
    final db = await _history.database;
    final rows = await db.query(
      'voice_corrections',
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(VoiceCorrection.fromMap).toList();
  }

  Future<int> remove(int id) async {
    final db = await _history.database;
    return db.delete('voice_corrections', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> clear() async {
    final db = await _history.database;
    return db.delete('voice_corrections');
  }

  /// Applies saved corrections longest-first at whole-word boundaries while
  /// preserving original casing and punctuation of surrounding text.
  Future<String> apply(String transcript) async {
    if (transcript.trim().isEmpty) return transcript;
    final rules = await list();
    if (rules.isEmpty) return transcript;

    rules.sort(
      (a, b) => b.normalizedWrong.length.compareTo(a.normalizedWrong.length),
    );

    final folded = PtBrTextNormalizer.foldSameLength(transcript);
    final replacements = <({int start, int end, String text})>[];

    for (final rule in rules) {
      if (rule.normalizedWrong.isEmpty) continue;
      final tokenPattern = RegExp.escape(rule.normalizedWrong)
          .replaceAll(' ', r'\s+');
      final pattern = RegExp('(?:^|(?<=\\s))($tokenPattern)(?=\\s|\$)');

      for (final match in pattern.allMatches(folded)) {
        final start = match.start;
        final end = match.end;
        final overlaps = replacements.any(
          (r) => start < r.end && end > r.start,
        );
        if (!overlaps) {
          replacements.add((start: start, end: end, text: rule.correctPhrase));
        }
      }
    }

    if (replacements.isEmpty) return transcript;
    replacements.sort((a, b) => b.start.compareTo(a.start));

    var updated = transcript;
    for (final r in replacements) {
      updated = updated.replaceRange(r.start, r.end, r.text);
    }
    return updated;
  }

  /// Builds a comma-separated vocabulary hint for Whisper `prompt`, bounded
  /// to [maxChars].
  Future<String> buildWhisperPrompt({int maxChars = 900}) async {
    final rules = await list();
    if (rules.isEmpty || maxChars <= 0) return '';

    final seen = <String>{};
    final buffer = StringBuffer();
    for (final rule in rules) {
      final term = rule.correctPhrase.trim();
      if (term.isEmpty || !seen.add(term.toLowerCase())) continue;
      final next = buffer.isEmpty ? term : ', $term';
      if (buffer.length + next.length > maxChars) break;
      buffer.write(next);
    }
    return buffer.toString();
  }
}
