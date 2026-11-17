import 'package:sqflite_sqlcipher/sqflite.dart' show ConflictAlgorithm;

import 'conversation_history.dart';
import 'text_normalization.dart';

class VoiceShortcut {
  const VoiceShortcut({
    this.id,
    required this.triggerPhrase,
    required this.normalizedTrigger,
    required this.actionType,
    required this.actionPayload,
    required this.requiresConfirmation,
    required this.createdAt,
  });

  final int? id;
  final String triggerPhrase;
  final String normalizedTrigger;
  final String actionType;
  final String actionPayload;
  final bool requiresConfirmation;
  final DateTime createdAt;

  factory VoiceShortcut.fromMap(Map<String, Object?> map) => VoiceShortcut(
        id: map['id'] as int?,
        triggerPhrase: map['trigger_phrase'] as String,
        normalizedTrigger: map['normalized_trigger'] as String,
        actionType: map['action_type'] as String,
        actionPayload: map['action_payload'] as String,
        requiresConfirmation: (map['requires_confirmation'] as int? ?? 1) != 0,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

class ShortcutExecutionResult {
  const ShortcutExecutionResult({
    required this.executed,
    this.deniedByUser = false,
  });

  final bool executed;
  final bool deniedByUser;
}

/// Persists and resolves local voice-triggered shortcuts with fail-closed
/// user confirmation whenever [VoiceShortcut.requiresConfirmation] is enabled.
class VoiceShortcutsService {
  VoiceShortcutsService({ConversationHistory? history})
      : _history = history ?? ConversationHistory.instance;

  final ConversationHistory _history;

  static String normalize(String text) =>
      PtBrTextNormalizer.normalizePhrase(text);

  Future<VoiceShortcut> add({
    required String triggerPhrase,
    required String actionType,
    required String actionPayload,
    bool requiresConfirmation = true,
  }) async {
    final trigger = triggerPhrase.trim();
    final normalized = normalize(trigger);
    if (normalized.isEmpty || actionType.trim().isEmpty) {
      throw ArgumentError('Gatilho e tipo de ação são obrigatórios.');
    }

    final db = await _history.database;
    final now = DateTime.now().toUtc();
    final id = await db.insert(
      'voice_shortcuts',
      <String, Object?>{
        'trigger_phrase': trigger,
        'normalized_trigger': normalized,
        'action_type': actionType.trim(),
        'action_payload': actionPayload,
        'requires_confirmation': requiresConfirmation ? 1 : 0,
        'created_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return VoiceShortcut(
      id: id,
      triggerPhrase: trigger,
      normalizedTrigger: normalized,
      actionType: actionType.trim(),
      actionPayload: actionPayload,
      requiresConfirmation: requiresConfirmation,
      createdAt: now,
    );
  }

  Future<List<VoiceShortcut>> list() async {
    final db = await _history.database;
    final rows = await db.query(
      'voice_shortcuts',
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(VoiceShortcut.fromMap).toList();
  }

  Future<int> remove(int id) async {
    final db = await _history.database;
    return db.delete('voice_shortcuts', where: 'id = ?', whereArgs: [id]);
  }

  Future<VoiceShortcut?> match(String transcript) async {
    final normalized = normalize(transcript);
    if (normalized.isEmpty) return null;

    final shortcuts = await list();
    shortcuts.sort(
      (a, b) =>
          b.normalizedTrigger.length.compareTo(a.normalizedTrigger.length),
    );
    for (final shortcut in shortcuts) {
      final trigger = shortcut.normalizedTrigger;
      if (trigger.isEmpty) continue;
      if (normalized == trigger) return shortcut;
      final pattern = RegExp('(^|\\s)${RegExp.escape(trigger)}(\\s|\$)');
      if (pattern.hasMatch(normalized)) return shortcut;
    }
    return null;
  }

  Future<ShortcutExecutionResult> execute(
    VoiceShortcut shortcut, {
    required Future<bool> Function(VoiceShortcut shortcut) confirm,
    required Future<void> Function(VoiceShortcut shortcut) run,
  }) async {
    if (shortcut.requiresConfirmation) {
      final allowed = await confirm(shortcut);
      if (!allowed) {
        return const ShortcutExecutionResult(
          executed: false,
          deniedByUser: true,
        );
      }
    }
    await run(shortcut);
    return const ShortcutExecutionResult(executed: true);
  }
}
