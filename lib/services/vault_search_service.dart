import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

enum VaultSearchEngine { fts5, fts4, lexicalFallback }

class VaultDocumentRecord {
  const VaultDocumentRecord({
    required this.path,
    required this.folder,
    required this.title,
    required this.content,
    required this.modifiedMs,
    required this.sizeBytes,
  });

  final String path;
  final String folder;
  final String title;
  final String content;
  final int modifiedMs;
  final int sizeBytes;
}

class VaultSearchHit {
  const VaultSearchHit({
    required this.path,
    required this.folder,
    required this.title,
    required this.snippet,
    required this.score,
    required this.modifiedAt,
  });

  final String path;
  final String folder;
  final String title;
  final String snippet;
  final double score;
  final DateTime modifiedAt;
}

class VaultSyncStats {
  const VaultSyncStats({
    required this.indexed,
    required this.updated,
    required this.removed,
    required this.totalDocuments,
  });

  final int indexed;
  final int updated;
  final int removed;
  final int totalDocuments;
}

/// Indexador e buscador léxico local (SQLite FTS5 com fallback FTS4/Dart)
/// para o cofre Markdown do Obsidian (`ULTRON-Vault`).
class VaultSearchService {
  VaultSearchService._({
    required this.vaultRoot,
    required Database db,
    required VaultSearchEngine engine,
  })  : _db = db,
        _engine = engine;

  final Directory vaultRoot;
  final Database _db;
  final VaultSearchEngine _engine;

  VaultSearchEngine get engine => _engine;

  static const _stopwords = <String>{
    'a',
    'ao',
    'aos',
    'as',
    'com',
    'como',
    'da',
    'das',
    'de',
    'do',
    'dos',
    'e',
    'em',
    'entre',
    'era',
    'essa',
    'esse',
    'esta',
    'este',
    'eu',
    'foi',
    'isso',
    'isto',
    'ja',
    'lembra',
    'lembrar',
    'me',
    'meu',
    'minha',
    'na',
    'nas',
    'no',
    'nos',
    'nota',
    'notas',
    'o',
    'os',
    'ou',
    'para',
    'pela',
    'pelo',
    'por',
    'pra',
    'quais',
    'qual',
    'quando',
    'que',
    'quem',
    'sao',
    'se',
    'sem',
    'sobre',
    'sua',
    'seu',
    'ta',
    'tem',
    'ultron',
    'um',
    'uma',
    'uns',
    'umas',
    'voce',
    'anotei',
    'anotado',
    'anotar',
    'anotacao',
    'anotacoes',
    'buscar',
    'procurar',
    'pesquisar',
  };

  /// Abre ou inicializa o índice de busca para [vaultRoot].
  static Future<VaultSearchService> open({
    required Directory vaultRoot,
    Database? database,
    String? dbPath,
  }) async {
    late final Database db;
    if (database != null) {
      db = database;
    } else {
      final path = dbPath ??
          p.join(
            (await getApplicationDocumentsDirectory()).path,
            'ultron_vault_index.db',
          );
      db = await openDatabase(path, version: 1);
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS vault_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vault_docs (
        path TEXT PRIMARY KEY,
        folder TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        modified_ms INTEGER NOT NULL,
        size_bytes INTEGER NOT NULL
      )
    ''');

    final engine = await _ensureFtsTable(db);
    await _resetIfVaultRootChanged(db, vaultRoot.path, engine);
    return VaultSearchService._(
      vaultRoot: vaultRoot,
      db: db,
      engine: engine,
    );
  }

  static Future<VaultSearchEngine> _ensureFtsTable(Database db) async {
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS vault_fts USING fts5(
          path UNINDEXED,
          title,
          content,
          tokenize='unicode61 remove_diacritics 2'
        )
      ''');
      return VaultSearchEngine.fts5;
    } catch (_) {
      try {
        await db.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS vault_fts USING fts5(
            path UNINDEXED,
            title,
            content,
            tokenize='unicode61'
          )
        ''');
        return VaultSearchEngine.fts5;
      } catch (_) {}
    }

    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS vault_fts USING fts4(
          path,
          title,
          content,
          notindexed=path,
          tokenize=unicode61
        )
      ''');
      return VaultSearchEngine.fts4;
    } catch (_) {
      return VaultSearchEngine.lexicalFallback;
    }
  }

  static Future<void> _resetIfVaultRootChanged(
    Database db,
    String rootPath,
    VaultSearchEngine engine,
  ) async {
    final rows = await db.query(
      'vault_meta',
      where: 'key = ?',
      whereArgs: ['vault_root'],
    );
    final previous = rows.isEmpty ? null : rows.first['value'] as String?;
    if (previous != null && previous != rootPath) {
      await db.delete('vault_docs');
      if (engine != VaultSearchEngine.lexicalFallback) {
        await db.delete('vault_fts');
      }
    }
    await db.insert(
      'vault_meta',
      {'key': 'vault_root', 'value': rootPath},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Sincroniza incrementalmente arquivos `.md` de [vaultRoot] no índice SQLite.
  Future<VaultSyncStats> sync() async {
    final diskFiles = await _scanMarkdownFiles();
    final existingRows = await _db.query(
      'vault_docs',
      columns: ['path', 'modified_ms', 'size_bytes'],
    );
    final existingMap = <String, ({int modifiedMs, int sizeBytes})>{
      for (final r in existingRows)
        r['path'] as String: (
          modifiedMs: (r['modified_ms'] as num).toInt(),
          sizeBytes: (r['size_bytes'] as num).toInt(),
        ),
    };

    final toUpsert = <VaultDocumentRecord>[];
    var inserted = 0;
    var updated = 0;

    for (final entry in diskFiles.entries) {
      final relPath = entry.key;
      final file = entry.value;
      final stat = await file.stat();
      final modMs = stat.modified.millisecondsSinceEpoch;
      final sizeBytes = stat.size;
      final prev = existingMap[relPath];

      if (prev != null &&
          prev.modifiedMs == modMs &&
          prev.sizeBytes == sizeBytes) {
        continue;
      }

      final content = await _readSafe(file);
      if (content == null) continue;
      final folder = relPath.contains('/') ? relPath.split('/').first : '';
      final title = _extractTitle(relPath, content);

      if (prev == null) {
        inserted++;
      } else {
        updated++;
      }
      toUpsert.add(
        VaultDocumentRecord(
          path: relPath,
          folder: folder,
          title: title,
          content: content,
          modifiedMs: modMs,
          sizeBytes: sizeBytes,
        ),
      );
    }

    final removedPaths =
        existingMap.keys.where((path) => !diskFiles.containsKey(path)).toList();

    if (toUpsert.isNotEmpty || removedPaths.isNotEmpty) {
      await _db.transaction((txn) async {
        for (final doc in toUpsert) {
          await txn.insert(
            'vault_docs',
            {
              'path': doc.path,
              'folder': doc.folder,
              'title': doc.title,
              'content': doc.content,
              'modified_ms': doc.modifiedMs,
              'size_bytes': doc.sizeBytes,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          if (_engine != VaultSearchEngine.lexicalFallback) {
            await txn.delete(
              'vault_fts',
              where: 'path = ?',
              whereArgs: [doc.path],
            );
            await txn.insert('vault_fts', {
              'path': doc.path,
              'title': doc.title,
              'content': doc.content,
            });
          }
        }
        for (final path in removedPaths) {
          await txn.delete(
            'vault_docs',
            where: 'path = ?',
            whereArgs: [path],
          );
          if (_engine != VaultSearchEngine.lexicalFallback) {
            await txn.delete(
              'vault_fts',
              where: 'path = ?',
              whereArgs: [path],
            );
          }
        }
      });
    }

    final total = existingMap.length + inserted - removedPaths.length;
    return VaultSyncStats(
      indexed: inserted,
      updated: updated,
      removed: removedPaths.length,
      totalDocuments: total,
    );
  }

  Future<Map<String, File>> _scanMarkdownFiles() async {
    final result = <String, File>{};
    if (!await vaultRoot.exists()) return result;

    await for (final entity in vaultRoot.list(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.md')) continue;
      final rel =
          p.relative(entity.path, from: vaultRoot.path).replaceAll('\\', '/');
      final segments = rel.split('/');
      if (segments.any((s) => s.startsWith('.'))) continue;
      result[rel] = entity;
    }
    return result;
  }

  static Future<String?> _readSafe(File file) async {
    try {
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  static String _extractTitle(String relPath, String content) {
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#')) {
        final heading = trimmed.replaceFirst(RegExp(r'^#+\s*'), '').trim();
        if (heading.isNotEmpty) return heading;
      }
    }
    return p.basenameWithoutExtension(relPath);
  }

  /// Executa busca ranqueada nas notas indexadas usando o melhor motor disponível.
  Future<List<VaultSearchHit>> search(String query, {int limit = 3}) async {
    if (limit <= 0) return const [];
    final terms = extractQueryTerms(query);
    if (terms.isEmpty) return const [];

    if (_engine == VaultSearchEngine.fts5) {
      final ftsHits = await _searchFts5(terms, limit: limit);
      if (ftsHits.isNotEmpty) return ftsHits;
    } else if (_engine == VaultSearchEngine.fts4) {
      final fts4Hits = await _searchFts4(terms, limit: limit);
      if (fts4Hits.isNotEmpty) return fts4Hits;
    }

    // Fallback léxico (ou se FTS não cobrir alguma variação sem acento)
    final allRows = await _db.query('vault_docs');
    final docs = allRows.map(_rowToRecord).toList();
    return rankLexicalDocuments(docs, query, limit: limit);
  }

  Future<List<VaultSearchHit>> _searchFts5(
    List<String> terms, {
    required int limit,
  }) async {
    final ftsQuery = _buildFtsMatchQuery(terms);
    try {
      final rows = await _db.rawQuery(
        '''
        SELECT d.path, d.folder, d.title, d.content, d.modified_ms,
               bm25(vault_fts, 0.0, 2.0, 1.0) AS rank
        FROM vault_fts
        JOIN vault_docs d ON vault_fts.path = d.path
        WHERE vault_fts MATCH ?
        ORDER BY rank ASC, d.modified_ms DESC
        LIMIT ?
        ''',
        [ftsQuery, limit],
      );
      return rows.map((row) {
        final content = row['content'] as String;
        final rawRank = (row['rank'] as num?)?.toDouble() ?? -1.0;
        return VaultSearchHit(
          path: row['path'] as String,
          folder: row['folder'] as String,
          title: row['title'] as String,
          snippet: extractSnippet(content, terms),
          score: max(0.01, -rawRank),
          modifiedAt: DateTime.fromMillisecondsSinceEpoch(
            (row['modified_ms'] as num).toInt(),
          ),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<VaultSearchHit>> _searchFts4(
    List<String> terms, {
    required int limit,
  }) async {
    final ftsQuery = _buildFtsMatchQuery(terms);
    try {
      final rows = await _db.rawQuery(
        '''
        SELECT d.path, d.folder, d.title, d.content, d.modified_ms
        FROM vault_fts
        JOIN vault_docs d ON vault_fts.path = d.path
        WHERE vault_fts MATCH ?
        LIMIT ?
        ''',
        [ftsQuery, limit * 4],
      );
      final docs = rows.map(_rowToRecord).toList();
      return rankLexicalDocuments(docs, terms.join(' '), limit: limit);
    } catch (_) {
      return const [];
    }
  }

  static VaultDocumentRecord _rowToRecord(Map<String, Object?> row) =>
      VaultDocumentRecord(
        path: row['path'] as String,
        folder: row['folder'] as String,
        title: row['title'] as String,
        content: row['content'] as String,
        modifiedMs: (row['modified_ms'] as num).toInt(),
        sizeBytes: (row['size_bytes'] as num?)?.toInt() ?? 0,
      );

  /// Formata os melhores trechos recuperados para injeção direta no prompt do LLM.
  Future<String> buildRagContext(
    String query, {
    int limit = 3,
    int maxChars = 1400,
  }) async {
    final hits = await search(query, limit: limit);
    if (hits.isEmpty) return '';

    final buffer = StringBuffer();
    for (var i = 0; i < hits.length; i++) {
      final h = hits[i];
      final entry = '[${i + 1}] ${h.path} (${h.title}):\n${h.snippet}\n';
      if (buffer.isNotEmpty && buffer.length + entry.length > maxChars) {
        break;
      }
      buffer.writeln(entry);
    }

    final formatted = buffer.toString().trim();
    if (formatted.length > maxChars) {
      return formatted.substring(0, maxChars).trimRight();
    }
    return formatted;
  }

  /// Motor léxico puro usado como fallback quando FTS5/FTS4 não está disponível.
  static List<VaultSearchHit> rankLexicalDocuments(
    List<VaultDocumentRecord> docs,
    String query, {
    int limit = 3,
  }) {
    if (limit <= 0 || docs.isEmpty) return const [];
    final terms = extractQueryTerms(query);
    if (terms.isEmpty) return const [];

    final scored = <VaultSearchHit>[];
    for (final doc in docs) {
      final normTitle = normalizeText(doc.title);
      final normContent = normalizeText(doc.content);
      final normPath = normalizeText(doc.path);

      var score = 0.0;
      var matchedTerms = 0;
      for (final term in terms) {
        final titleMatches = _countOccurrences(normTitle, term);
        final pathMatches = _countOccurrences(normPath, term);
        final contentMatches = _countOccurrences(normContent, term);
        if (titleMatches > 0 || pathMatches > 0 || contentMatches > 0) {
          matchedTerms++;
          score += titleMatches * 3.0 +
              pathMatches * 2.0 +
              min(contentMatches, 6) * 1.0;
        }
      }
      if (matchedTerms == 0) continue;

      // Boost documents covering a higher fraction of distinct query terms.
      score *= 1.0 + (matchedTerms / terms.length);
      scored.add(
        VaultSearchHit(
          path: doc.path,
          folder: doc.folder,
          title: doc.title,
          snippet: extractSnippet(doc.content, terms),
          score: score,
          modifiedAt: DateTime.fromMillisecondsSinceEpoch(doc.modifiedMs),
        ),
      );
    }

    scored.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      return cmp != 0 ? cmp : b.modifiedAt.compareTo(a.modifiedAt);
    });
    return scored.take(limit).toList();
  }

  static int _countOccurrences(String haystack, String needle) {
    if (needle.isEmpty) return 0;
    var count = 0;
    var idx = 0;
    while (true) {
      idx = haystack.indexOf(needle, idx);
      if (idx < 0) break;
      count++;
      idx += needle.length;
    }
    return count;
  }

  static List<String> extractQueryTerms(String query) {
    final normalized = normalizeText(query);
    final rawTokens = RegExp(r'[a-z0-9]+')
        .allMatches(normalized)
        .map((m) => m.group(0)!)
        .where((t) => t.length >= 2)
        .toList();
    if (rawTokens.isEmpty) return const [];

    final meaningful = rawTokens.where((t) => !_stopwords.contains(t)).toList();
    final selected = meaningful.isNotEmpty ? meaningful : rawTokens;
    return selected.toSet().toList();
  }

  static String _buildFtsMatchQuery(List<String> terms) =>
      terms.map((t) => '"$t"*').join(' OR ');

  static String extractSnippet(
    String content,
    List<String> terms, {
    int maxLength = 260,
  }) {
    final compact = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= maxLength) return compact;

    final normCompact = normalizeText(compact);
    var hitPos = -1;
    for (final term in terms) {
      final idx = normCompact.indexOf(term);
      if (idx >= 0 && (hitPos < 0 || idx < hitPos)) {
        hitPos = idx;
      }
    }

    if (hitPos < 0) {
      return '${compact.substring(0, maxLength - 1).trimRight()}…';
    }

    final half = maxLength ~/ 2;
    final start = max(0, min(hitPos - half ~/ 2, compact.length - maxLength));
    final end = min(compact.length, start + maxLength);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < compact.length ? '…' : '';
    return '$prefix${compact.substring(start, end).trim()}$suffix';
  }

  static String normalizeText(String input) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    final lower = input.toLowerCase();
    final out = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      final idx = from.indexOf(ch);
      out.write(idx >= 0 ? to[idx] : ch);
    }
    return out.toString();
  }

  Future<void> close() => _db.close();
}
