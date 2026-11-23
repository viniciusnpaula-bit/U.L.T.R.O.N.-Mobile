import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultron_mobile/services/audit_log_service.dart';

Future<Database> _openInMemoryAuditDb() => databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, singleInstance: false),
    );

void main() {
  sqfliteFfiInit();

  test('appends hash-chained audit entries and verifies integrity', () async {
    final db = await _openInMemoryAuditDb();
    final audit = await AuditLogService.open(database: db);
    addTearDown(() => audit.close());

    final e1 = await audit.record(
      actor: 'operator',
      action: 'kill_switch',
      target: '192.168.1.10',
      status: 'executed',
      detail: 'HTTP 200',
    );
    final e2 = await audit.record(
      actor: 'skill:iot',
      action: 'http_post',
      target: 'http://192.168.1.50:8123/api/webhook/noite',
      status: 'denied',
      detail: 'Action Gate',
    );

    expect(e1.seq, 1);
    expect(e1.prevHash, AuditLogService.genesisHash);
    expect(e2.seq, 2);
    expect(e2.prevHash, e1.hash);
    expect(e1.hash.length, 64);

    final verification = await audit.verifyChain();
    expect(verification.valid, isTrue);
    expect(verification.totalEntries, 2);
    expect(verification.lastHash, e2.hash);

    final recent = await audit.recent(limit: 5);
    expect(recent.map((e) => e.seq).toList(), [2, 1]);

    final report = await audit.formatReport();
    expect(report, contains('CADEIA ÍNTEGRA (2 registros verificados)'));
  });

  test('detects tampering when an entry is modified out-of-band', () async {
    final db = await _openInMemoryAuditDb();
    final audit = await AuditLogService.open(database: db);
    addTearDown(() => audit.close());

    await audit.record(
      actor: 'operator',
      action: 'whatsapp',
      target: 'Carlos',
      status: 'executed',
    );
    await audit.record(
      actor: 'ai_tag',
      action: 'sms',
      target: '11999999999',
      status: 'denied',
    );

    // Simulate malicious SQLite tamper of row 1
    await db.update(
      'audit_log',
      {'status': 'DENIED'},
      where: 'seq = ?',
      whereArgs: [1],
    );

    final verification = await audit.verifyChain();
    expect(verification.valid, isFalse);
    expect(verification.brokenAtSeq, 1);

    final report = await audit.formatReport();
    expect(report, contains('ADULTERAÇÃO DETECTADA no registro #1'));
  });

  test('Marco 2: classifies confirmed/uncertain/failed outcomes and summarizes receipts',
      () async {
    expect(
      AuditLogService.classifyActionOutcome('TORCH_ON', succeeded: true),
      ExecutionOutcome.confirmed,
    );
    expect(
      AuditLogService.classifyActionOutcome('WHATSAPP', succeeded: true),
      ExecutionOutcome.uncertain,
    );
    expect(
      AuditLogService.classifyActionOutcome('OPEN_APP', succeeded: true),
      ExecutionOutcome.uncertain,
    );
    expect(
      AuditLogService.classifyActionOutcome(
        'OBSIDIAN_READ',
        succeeded: true,
        detail: 'Não encontrei a nota solicitada',
      ),
      ExecutionOutcome.failed,
    );

    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final audit = await AuditLogService.open(database: db);
    addTearDown(audit.close);

    await audit.recordReceipt(
      actor: 'OPERATOR',
      action: 'TORCH_ON',
      outcome: ExecutionOutcome.confirmed,
    );
    await audit.recordReceipt(
      actor: 'OPERATOR',
      action: 'WHATSAPP',
      outcome: ExecutionOutcome.uncertain,
    );
    await audit.recordReceipt(
      actor: 'OPERATOR',
      action: 'PC_EXEC_TOOL',
      outcome: ExecutionOutcome.failed,
    );

    final summary = await audit.summarizeOutcomes();
    expect(summary.confirmed, 1);
    expect(summary.uncertain, 1);
    expect(summary.failed, 1);
    expect((await audit.verifyChain()).valid, isTrue);

    final report = await audit.formatReport();
    expect(report, contains('1 confirmados'));
    expect(report, contains('1 incertos'));
    expect(report, contains('1 falhos'));
  });
}
