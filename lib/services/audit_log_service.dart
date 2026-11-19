import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Entrada individual no log imutável encadeado por SHA-256.
class AuditEntry {
  const AuditEntry({
    required this.seq,
    required this.timestamp,
    required this.actor,
    required this.action,
    required this.target,
    required this.status,
    required this.detail,
    required this.prevHash,
    required this.hash,
  });

  factory AuditEntry.fromRow(Map<String, Object?> row) => AuditEntry(
        seq: (row['seq'] as num).toInt(),
        timestamp: row['timestamp'] as String? ?? '',
        actor: row['actor'] as String? ?? '',
        action: row['action'] as String? ?? '',
        target: row['target'] as String? ?? '',
        status: row['status'] as String? ?? '',
        detail: row['detail'] as String? ?? '',
        prevHash: row['prev_hash'] as String? ?? '',
        hash: row['hash'] as String? ?? '',
      );

  final int seq;
  final String timestamp;
  final String actor;
  final String action;
  final String target;
  final String status;
  final String detail;
  final String prevHash;
  final String hash;

  String computeExpectedHash() => AuditLogService.computeEntryHash(
        seq: seq,
        timestamp: timestamp,
        actor: actor,
        action: action,
        target: target,
        status: status,
        detail: detail,
        prevHash: prevHash,
      );

  String formatSummaryLine() {
    final shortTs = timestamp.length >= 19
        ? timestamp.substring(0, 19).replaceFirst('T', ' ')
        : timestamp;
    final shortHash = hash.length >= 10 ? hash.substring(0, 10) : hash;
    final targetPart = target.trim().isEmpty ? '' : ' [$target]';
    final detailPart = detail.trim().isEmpty ? '' : ' — $detail';
    return '#$seq ($shortTs) [$status] $actor/$action$targetPart$detailPart · sha256:$shortHash';
  }
}

class AuditChainVerification {
  const AuditChainVerification({
    required this.valid,
    required this.totalEntries,
    this.brokenAtSeq,
    this.lastHash = AuditLogService.genesisHash,
  });

  final bool valid;
  final int totalEntries;
  final int? brokenAtSeq;
  final String lastHash;
}

/// Serviço append-only de auditoria tática com encadeamento criptográfico SHA-256 (P5).
///
/// Cada registro referencia o `hash` do registro anterior, tornando qualquer edição
/// ou remoção retroativa detectável via `verifyChain()`.
class AuditLogService {
  AuditLogService._(this._db);

  static const genesisHash =
      '0000000000000000000000000000000000000000000000000000000000000000';

  final Database _db;
  static AuditLogService? _sharedInstance;

  /// Abre o banco SQLite padrão de auditoria (append-only).
  static Future<AuditLogService> instance() async {
    if (_sharedInstance != null && _sharedInstance!._db.isOpen) {
      return _sharedInstance!;
    }
    final svc = await open();
    _sharedInstance = svc;
    return svc;
  }

  static Future<AuditLogService> open({
    Database? database,
    String? dbPath,
  }) async {
    late final Database db;
    if (database != null) {
      db = database;
    } else {
      final resolved =
          dbPath ?? p.join(await getDatabasesPath(), 'ultron_audit.db');
      db = await openDatabase(resolved, version: 1);
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_log (
        seq INTEGER PRIMARY KEY,
        timestamp TEXT NOT NULL,
        actor TEXT NOT NULL,
        action TEXT NOT NULL,
        target TEXT NOT NULL,
        status TEXT NOT NULL,
        detail TEXT NOT NULL,
        prev_hash TEXT NOT NULL,
        hash TEXT NOT NULL
      )
    ''');
    return AuditLogService._(db);
  }

  static String computeEntryHash({
    required int seq,
    required String timestamp,
    required String actor,
    required String action,
    required String target,
    required String status,
    required String detail,
    required String prevHash,
  }) {
    final canonical = jsonEncode([
      seq,
      timestamp,
      actor,
      action,
      target,
      status,
      detail,
      prevHash,
    ]);
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  Future<AuditEntry> record({
    required String actor,
    required String action,
    String target = '',
    required String status,
    String detail = '',
    DateTime? timestamp,
  }) async {
    final ts = (timestamp ?? DateTime.now()).toUtc().toIso8601String();
    final cleanActor = actor.trim().toUpperCase();
    final cleanAction = action.trim().toUpperCase();
    final cleanTarget = target.trim();
    final cleanStatus = status.trim().toUpperCase();
    final cleanDetail = detail.trim();

    return _db.transaction((txn) async {
      final lastRows = await txn.query(
        'audit_log',
        columns: ['seq', 'hash'],
        orderBy: 'seq DESC',
        limit: 1,
      );
      final nextSeq =
          lastRows.isEmpty ? 1 : ((lastRows.first['seq'] as num).toInt() + 1);
      final prevHash = lastRows.isEmpty
          ? genesisHash
          : (lastRows.first['hash'] as String? ?? genesisHash);
      final hash = computeEntryHash(
        seq: nextSeq,
        timestamp: ts,
        actor: cleanActor,
        action: cleanAction,
        target: cleanTarget,
        status: cleanStatus,
        detail: cleanDetail,
        prevHash: prevHash,
      );

      await txn.insert('audit_log', {
        'seq': nextSeq,
        'timestamp': ts,
        'actor': cleanActor,
        'action': cleanAction,
        'target': cleanTarget,
        'status': cleanStatus,
        'detail': cleanDetail,
        'prev_hash': prevHash,
        'hash': hash,
      });

      return AuditEntry(
        seq: nextSeq,
        timestamp: ts,
        actor: cleanActor,
        action: cleanAction,
        target: cleanTarget,
        status: cleanStatus,
        detail: cleanDetail,
        prevHash: prevHash,
        hash: hash,
      );
    });
  }

  Future<List<AuditEntry>> recent({int limit = 25}) async {
    final rows = await _db.query(
      'audit_log',
      orderBy: 'seq DESC',
      limit: limit.clamp(1, 200),
    );
    return rows.map(AuditEntry.fromRow).toList();
  }

  Future<AuditChainVerification> verifyChain() async {
    final rows = await _db.query('audit_log', orderBy: 'seq ASC');
    var expectedPrev = genesisHash;
    var expectedSeq = 1;
    for (final row in rows) {
      final entry = AuditEntry.fromRow(row);
      if (entry.seq != expectedSeq ||
          entry.prevHash != expectedPrev ||
          entry.hash != entry.computeExpectedHash()) {
        return AuditChainVerification(
          valid: false,
          totalEntries: rows.length,
          brokenAtSeq: entry.seq,
          lastHash: entry.hash,
        );
      }
      expectedPrev = entry.hash;
      expectedSeq += 1;
    }
    return AuditChainVerification(
      valid: true,
      totalEntries: rows.length,
      lastHash: expectedPrev,
    );
  }

  Future<String> formatReport({int limit = 15}) async {
    final verification = await verifyChain();
    final entries = await recent(limit: limit);
    final statusBadge = verification.valid
        ? '✅ CADEIA ÍNTEGRA (${verification.totalEntries} registros verificados)'
        : '🚨 ADULTERAÇÃO DETECTADA no registro #${verification.brokenAtSeq}';
    final buf = StringBuffer()
      ..writeln('📜 LOG IMUTÁVEL DE AUDITORIA (SHA-256)')
      ..writeln(statusBadge)
      ..writeln('');
    if (entries.isEmpty) {
      buf.writeln('• Nenhum evento crítico ou webhook registrado ainda.');
    } else {
      for (final e in entries) {
        buf.writeln('• ${e.formatSummaryLine()}');
      }
    }
    return buf.toString().trimRight();
  }

  Future<void> close() async {
    if (_db.isOpen) {
      await _db.close();
    }
    if (identical(_sharedInstance, this)) {
      _sharedInstance = null;
    }
  }
}
