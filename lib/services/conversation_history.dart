import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/chat_message.dart';

class ConversationHistory {
  ConversationHistory._();

  static final ConversationHistory instance = ConversationHistory._();

  /// Test seam: skips path_provider by taking an already-open database.
  ConversationHistory.forDatabase(Database db) {
    _database = db;
  }

  static const _databaseName = 'ultron_conversations.db';
  static const _databaseVersion = 1;
  Database? _database;

  static const schema = [
    '''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            conversation_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''',
    'CREATE INDEX messages_conversation_created '
        'ON messages(conversation_id, created_at)',
  ];

  Future<Database> get database async {
    if (_database != null) return _database!;
    final directory = await getApplicationDocumentsDirectory();
    _database = await openDatabase(
      p.join(directory.path, _databaseName),
      version: _databaseVersion,
      onCreate: (db, version) async {
        for (final statement in schema) {
          await db.execute(statement);
        }
      },
    );
    return _database!;
  }


  Future<int> save(ChatMessage message) async {
    final db = await database;
    return db.insert(
      'messages',
      message.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
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
