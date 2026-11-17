import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import '../core/security/database_key_vault.dart';
import '../models/chat_message.dart';

typedef EncryptedDatabaseOpener = Future<sqlcipher.Database> Function(
  String path, {
  String? password,
  int? version,
  sqlcipher.OnDatabaseCreateFn? onCreate,
  sqlcipher.OnDatabaseVersionChangeFn? onUpgrade,
});

typedef PlaintextDatabaseOpener = Future<sqlcipher.Database> Function(
  String path, {
  bool readOnly,
});

class ConversationHistory {
  ConversationHistory._();

  static final ConversationHistory instance = ConversationHistory._();

  /// Test seam: skips path_provider by taking an already-open database.
  ConversationHistory.forDatabase(sqlcipher.Database db) {
    _database = db;
  }

  static const legacyDatabaseName = 'ultron_conversations.db';
  static const encryptedDatabaseName = 'ultron_conversations_v2.db';
  static const _databaseVersion = 2;

  sqlcipher.Database? _database;
  Future<sqlcipher.Database>? _opening;

  static const schemaV1 = <String>[
    '''
      CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''',
    'CREATE INDEX IF NOT EXISTS messages_conversation_created '
        'ON messages(conversation_id, created_at)',
  ];

  static const schemaV2Additions = <String>[
    '''
      CREATE TABLE IF NOT EXISTS voice_corrections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        wrong_phrase TEXT NOT NULL,
        normalized_wrong TEXT NOT NULL UNIQUE,
        correct_phrase TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''',
    '''
      CREATE TABLE IF NOT EXISTS voice_shortcuts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trigger_phrase TEXT NOT NULL,
        normalized_trigger TEXT NOT NULL UNIQUE,
        action_type TEXT NOT NULL,
        action_payload TEXT NOT NULL,
        requires_confirmation INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''',
    '''
      CREATE TABLE IF NOT EXISTS user_preferences (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''',
  ];

  static const schema = <String>[
    ...schemaV1,
    ...schemaV2Additions,
  ];

  Future<sqlcipher.Database> get database async {
    if (_database != null) return _database!;
    final opening = _opening ??= _openDefault();
    try {
      return await opening;
    } catch (_) {
      if (identical(_opening, opening)) _opening = null;
      rethrow;
    }
  }

  /// Opens an encrypted (or test-injected) v2 database in [directoryPath],
  /// migrating any legacy plaintext v1 `ultron_conversations.db` atomically
  /// before deleting the unencrypted file.
  static Future<ConversationHistory> openWith({
    required String directoryPath,
    DatabaseKeyVault? keyVault,
    EncryptedDatabaseOpener? encryptedOpener,
    PlaintextDatabaseOpener? plaintextOpener,
  }) async {
    final db = await _openAndMigrate(
      directoryPath: directoryPath,
      keyVault: keyVault ?? DatabaseKeyVault(),
      encryptedOpener: encryptedOpener ?? _defaultEncryptedOpener,
      plaintextOpener: plaintextOpener ?? _defaultPlaintextOpener,
    );
    return ConversationHistory.forDatabase(db);
  }

  Future<sqlcipher.Database> _openDefault() async {
    final directory = await getApplicationDocumentsDirectory();
    final db = await _openAndMigrate(
      directoryPath: directory.path,
      keyVault: DatabaseKeyVault(),
      encryptedOpener: _defaultEncryptedOpener,
      plaintextOpener: _defaultPlaintextOpener,
    );
    _database = db;
    return db;
  }

  static Future<sqlcipher.Database> _defaultEncryptedOpener(
    String path, {
    String? password,
    int? version,
    sqlcipher.OnDatabaseCreateFn? onCreate,
    sqlcipher.OnDatabaseVersionChangeFn? onUpgrade,
  }) =>
      sqlcipher.openDatabase(
        path,
        password: password,
        version: version,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
      );

  static Future<sqlcipher.Database> _defaultPlaintextOpener(
    String path, {
    bool readOnly = true,
  }) =>
      sqflite.openDatabase(path, readOnly: readOnly);

  static Future<sqlcipher.Database> _openAndMigrate({
    required String directoryPath,
    required DatabaseKeyVault keyVault,
    required EncryptedDatabaseOpener encryptedOpener,
    required PlaintextDatabaseOpener plaintextOpener,
  }) async {
    final key = await keyVault.getOrCreateKey();
    final encryptedPath = p.join(directoryPath, encryptedDatabaseName);
    final legacyPath = p.join(directoryPath, legacyDatabaseName);

    final targetDb = await encryptedOpener(
      encryptedPath,
      password: key,
      version: _databaseVersion,
      onCreate: (db, version) async {
        for (final statement in schema) {
          await db.execute(statement);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          for (final statement in schemaV2Additions) {
            await db.execute(statement);
          }
        }
      },
    );

    try {
      final legacyFile = File(legacyPath);
      if (await legacyFile.exists()) {
        await _migrateLegacyFile(
          legacyFile: legacyFile,
          targetDb: targetDb,
          plaintextOpener: plaintextOpener,
        );
      }
      return targetDb;
    } catch (_) {
      await targetDb.close();
      rethrow;
    }
  }

  static Future<void> _migrateLegacyFile({
    required File legacyFile,
    required sqlcipher.Database targetDb,
    required PlaintextDatabaseOpener plaintextOpener,
  }) async {
    final legacyDb = await plaintextOpener(legacyFile.path, readOnly: true);
    final List<Map<String, Object?>> legacyRows;
    try {
      legacyRows = await legacyDb.query('messages', orderBy: 'id ASC');
    } finally {
      await legacyDb.close();
    }

    await targetDb.transaction((txn) async {
      final existingCount = sqlcipher.Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM messages'),
          ) ??
          0;
      if (existingCount == 0 && legacyRows.isNotEmpty) {
        for (final row in legacyRows) {
          await txn.insert(
            'messages',
            <String, Object?>{
              'conversation_id': row['conversation_id'],
              'role': row['role'],
              'content': row['content'],
              'created_at': row['created_at'],
            },
            conflictAlgorithm: sqlcipher.ConflictAlgorithm.abort,
          );
        }
      }
      final finalCount = sqlcipher.Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM messages'),
          ) ??
          0;
      if (finalCount < legacyRows.length) {
        throw StateError(
          'Migração incompleta: esperadas ${legacyRows.length} mensagens, gravadas $finalCount.',
        );
      }
    });

    await _deleteIfExists(legacyFile);
    await _deleteIfExists(File('${legacyFile.path}-wal'));
    await _deleteIfExists(File('${legacyFile.path}-shm'));
    await _deleteIfExists(File('${legacyFile.path}-journal'));
  }

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<int> save(ChatMessage message) async {
    final db = await database;
    return db.insert(
      'messages',
      message.toMap()..remove('id'),
      conflictAlgorithm: sqlcipher.ConflictAlgorithm.abort,
    );
  }

  Future<List<ChatMessage>> messages({
    String? conversationId,
    int limit = 200,
  }) async {
    final db = await database;
    final rows = await db.query(
      'messages',
      where: conversationId == null ? null : 'conversation_id = ?',
      whereArgs: conversationId == null ? null : [conversationId],
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(ChatMessage.fromMap).toList().reversed.toList();
  }

  Future<int> deleteConversation(String conversationId) async {
    final db = await database;
    return db.delete(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  Future<int> clear() async {
    final db = await database;
    return db.delete('messages');
  }
}
