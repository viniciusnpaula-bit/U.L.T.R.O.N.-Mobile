import 'package:sqflite_sqlcipher/sqflite.dart' show ConflictAlgorithm;

import 'conversation_history.dart';

class UserPreference {
  const UserPreference({
    required this.key,
    required this.value,
    required this.updatedAt,
  });

  final String key;
  final String value;
  final DateTime updatedAt;

  factory UserPreference.fromMap(Map<String, Object?> map) => UserPreference(
        key: map['key'] as String,
        value: map['value'] as String,
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}

/// Key-value local user preferences persisted in SQLite.
class UserPreferencesService {
  UserPreferencesService({ConversationHistory? history})
      : _history = history ?? ConversationHistory.instance;

  final ConversationHistory _history;

  Future<void> set(String key, String value) async {
    final cleanKey = key.trim();
    if (cleanKey.isEmpty) {
      throw ArgumentError('Chave de preferência não pode ser vazia.');
    }
    final db = await _history.database;
    await db.insert(
      'user_preferences',
      <String, Object?>{
        'key': cleanKey,
        'value': value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> get(String key) async {
    final db = await _history.database;
    final rows = await db.query(
      'user_preferences',
      where: 'key = ?',
      whereArgs: [key.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<List<UserPreference>> list() async {
    final db = await _history.database;
    final rows = await db.query(
      'user_preferences',
      orderBy: 'updated_at DESC, key ASC',
    );
    return rows.map(UserPreference.fromMap).toList();
  }

  Future<int> remove(String key) async {
    final db = await _history.database;
    return db.delete(
      'user_preferences',
      where: 'key = ?',
      whereArgs: [key],
    );
  }
}
