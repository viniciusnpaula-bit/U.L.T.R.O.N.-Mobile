import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import '../core/security/database_key_vault.dart';
import '../models/chat_message.dart';
import 'text_normalization.dart';

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

  static const Set<String> _ptStopwords = <String>{
    'a', 'o', 'e', 'de', 'da', 'do', 'das', 'dos', 'em', 'no', 'na', 'nos',
    'nas', 'um', 'uma', 'uns', 'umas', 'para', 'pra', 'por', 'com', 'sem',
    'que', 'como', 'qual', 'quais', 'quem', 'onde', 'quando', 'porque',
    'por que', 'eu', 'voce', 'vc', 'ele', 'ela', 'eles', 'meu',
    'minha', 'seu', 'sua', 'isso', 'isto', 'esse', 'essa', 'esta', 'este',
    'ser', 'estar', 'ter', 'foi', 'era', 'sao', 'tem', 'mais', 'muito',
    'ja', 'so', 'nao', 'sim', 'mas', 'ou', 'se', 'ao', 'aos', 'sobre',
    'ultron', 'jarvis', 'edith', 'visao', 'ola', 'oi', 'ei',
  };

  static Set<String> _tokenize(String text) {
    final norm = PtBrTextNormalizer.normalizePhrase(text);
    if (norm.isEmpty) return const <String>{};
    return norm
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !_ptStopwords.contains(w))
        .toSet();
  }

  /// Compacta o histórico de mensagens mantendo os últimos [keepRecent] turnos
  /// intactos e resumindo mensagens mais antigas em um bloco enxuto para
  /// economizar tokens nos provedores gratuitos.
  static CompactedHistory compactHistory(
    List<ChatMessage> history, {
    int keepRecent = 8,
    int maxSummaryChars = 900,
  }) {
    if (history.length <= keepRecent) {
      return CompactedHistory(recentMessages: history, summaryDigest: '');
    }
    final splitAt = history.length - keepRecent;
    final older = history.sublist(0, splitAt);
    final recent = history.sublist(splitAt);

    final sb = StringBuffer();
    for (final msg in older) {
      if (msg.role == ChatRole.system) continue;
      final clean = msg.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (clean.isEmpty) continue;
      final who = msg.role == ChatRole.user ? 'Operador' : 'Assistente';
      final snippet =
          clean.length > 120 ? '${clean.substring(0, 117)}...' : clean;
      final line = '- $who: $snippet\n';
      if (sb.length + line.length > maxSummaryChars) break;
      sb.write(line);
    }

    return CompactedHistory(
      recentMessages: recent,
      summaryDigest: sb.toString().trim(),
    );
  }

  /// Extrai fatos duradouros e preferências declaradas pelo operador
  /// (gostos, rotina, objetivos, ferramentas, BPM/treino) para memória de longo prazo.
  static List<String> extractLongTermFacts(
    List<ChatMessage> history, {
    int maxFacts = 8,
  }) {
    final durablePattern = RegExp(
      r'\b(eu\s+(?:prefiro|gosto|uso|treino|trabalho|estudo|ou[cç]o|quero|moro|fa[cç]o)|'
      r'meu\s+(?:objetivo|treino|foco|bpm|estilo|player|projeto|app)|'
      r'minha\s+(?:rotina|meta|playlist|dieta|faculdade|empresa)|'
      r'lembre(?:-se)?\s+que|sempre\s+que\s+eu|nunca\s+(?:use|fa[cç]a))\b',
      caseSensitive: false,
    );
    final seen = <String>{};
    final out = <String>[];
    for (final msg in history.reversed) {
      if (msg.role != ChatRole.user) continue;
      final clean = msg.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (clean.length < 12 || clean.startsWith('/')) continue;
      if (!durablePattern.hasMatch(clean)) continue;
      final norm = PtBrTextNormalizer.normalizePhrase(clean);
      if (norm.isEmpty || !seen.add(norm)) continue;
      out.add(clean.length > 180 ? '${clean.substring(0, 177)}...' : clean);
      if (out.length >= maxFacts) break;
    }
    return out;
  }

  /// Recall lexical local de longo prazo (até 365 dias) por sobreposição de tokens
  /// + bônus de recência + prioridade para a conversa ativa, com fallback entre sessões.
  Future<List<HistoryRecallMatch>> recallRelevant(
    String query, {
    String? conversationId,
    int maxDays = 365,
    int limit = 6,
    int scanLimit = 1500,
    bool includeCrossSession = true,
    DateTime? now,
  }) async {
    final queryTokens = _tokenize(query);
    if (queryTokens.isEmpty) return const <HistoryRecallMatch>[];

    final refNow = (now ?? DateTime.now()).toUtc();
    final cutoff = refNow.subtract(Duration(days: maxDays)).toIso8601String();
    final db = await database;

    final targetConv = conversationId?.trim() ?? '';
    final whereParts = <String>['created_at >= ?'];
    final whereArgs = <Object?>[cutoff];
    if (!includeCrossSession && targetConv.isNotEmpty) {
      whereParts.add('conversation_id = ?');
      whereArgs.add(targetConv);
    }

    final rows = await db.query(
      'messages',
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'created_at DESC, id DESC',
      limit: scanLimit,
    );
    if (rows.isEmpty) return const <HistoryRecallMatch>[];

    final scored = <HistoryRecallMatch>[];
    for (final row in rows) {
      final msg = ChatMessage.fromMap(row);
      if (msg.role == ChatRole.system) continue;
      final msgTokens = _tokenize(msg.content);
      if (msgTokens.isEmpty) continue;

      final overlap = queryTokens.intersection(msgTokens);
      if (overlap.isEmpty) continue;

      final coverage = overlap.length / queryTokens.length;
      final ageDays =
          refNow.difference(msg.createdAt.toUtc()).inHours.abs() / 24.0;
      final recencyBonus = (1.0 - (ageDays / maxDays)).clamp(0.0, 1.0) * 0.25;
      final sameConvBonus =
          (targetConv.isNotEmpty && msg.conversationId == targetConv)
              ? 0.16
              : 0.0;
      final score = coverage + recencyBonus + sameConvBonus;

      if (score >= 0.30) {
        scored.add(
          HistoryRecallMatch(
            message: msg,
            score: score,
            matchedTokens: overlap.toList(growable: false),
          ),
        );
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).toList(growable: false);
  }

  /// Monta bloco pronto para injeção no System Prompt com memórias recuperadas.
  Future<String> buildRecallContext(
    String query, {
    String? conversationId,
    int maxDays = 365,
    int limit = 6,
    int maxChars = 1200,
    bool includeCrossSession = true,
    DateTime? now,
  }) async {
    final matches = await recallRelevant(
      query,
      conversationId: conversationId,
      maxDays: maxDays,
      limit: limit,
      includeCrossSession: includeCrossSession,
      now: now,
    );
    if (matches.isEmpty) return '';
    final sb = StringBuffer();
    for (final m in matches) {
      final dt = m.message.createdAt.toLocal();
      final dateStr =
          '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
      final who = m.message.role == ChatRole.user ? 'Operador' : 'Assistente';
      final clean = m.message.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      final snippet =
          clean.length > 180 ? '${clean.substring(0, 177)}...' : clean;
      final line = '- [$dateStr] $who: $snippet\n';
      if (sb.length + line.length > maxChars) break;
      sb.write(line);
    }
    return sb.toString().trim();
  }
}

class CompactedHistory {
  const CompactedHistory({
    required this.recentMessages,
    required this.summaryDigest,
  });

  final List<ChatMessage> recentMessages;
  final String summaryDigest;

  bool get hasDigest => summaryDigest.trim().isNotEmpty;
}

class HistoryRecallMatch {
  const HistoryRecallMatch({
    required this.message,
    required this.score,
    required this.matchedTokens,
  });

  final ChatMessage message;
  final double score;
  final List<String> matchedTokens;
}
