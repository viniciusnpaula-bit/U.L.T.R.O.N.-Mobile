import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultron_mobile/services/obsidian_service.dart';
import 'package:ultron_mobile/services/vault_search_service.dart';

Future<Database> _openInMemoryDb() => databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
      ),
    );

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late ObsidianService vault;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ultron_vault_search_');
    vault = ObsidianService(tempDir);
    await vault.initialize();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('sync indexes markdown notes across vault folders and skips .obsidian',
      () async {
    await vault.dailyNote(
      DateTime(2026, 11, 10),
      'Calibração dos sensores ultrassônicos concluída na bancada.',
    );
    await vault.captureToInbox('Ideia de telemetria térmica para o Galaxy A34');
    await vault.saveMemory(
        'Projetos', 'Projeto Aurora usa protocolo MQTT local.');
    await File(p.join(tempDir.path, '.obsidian', 'ignored.md'))
        .writeAsString('# Ignorar\nsensores secretos');

    final db = await _openInMemoryDb();
    final index = await VaultSearchService.open(
      vaultRoot: tempDir,
      database: db,
    );
    addTearDown(index.close);

    expect(index.engine, VaultSearchEngine.fts5);

    final stats = await index.sync();
    // Seeded: Operador.md, Segundo_Cerebro.md, 3 default skills + 3 created notes = 8
    expect(stats.indexed, 8);
    expect(stats.updated, 0);
    expect(stats.removed, 0);
    expect(stats.totalDocuments, 8);

    final hiddenHits = await index.search('secretos');
    expect(hiddenHits, isEmpty);
  });

  test('sync performs incremental updates and prunes deleted files', () async {
    final noteFile = await vault.dailyNote(
      DateTime(2026, 11, 11),
      'Versão inicial sobre bateria.',
    );

    final db = await _openInMemoryDb();
    final index = await VaultSearchService.open(
      vaultRoot: tempDir,
      database: db,
    );
    addTearDown(index.close);

    final first = await index.sync();
    expect(first.indexed, greaterThan(0));

    // Unchanged run -> no work
    final second = await index.sync();
    expect(second.indexed, 0);
    expect(second.updated, 0);
    expect(second.removed, 0);

    // Modify file (append new content + ensure mtime/size changes)
    await noteFile.writeAsString(
      '${await noteFile.readAsString()}\nAtualização: sensores térmicos em 34 graus.',
    );
    final third = await index.sync();
    expect(third.updated, 1);
    expect(third.removed, 0);

    final updatedHits = await index.search('térmicos');
    expect(updatedHits, isNotEmpty);
    expect(updatedHits.first.path, 'Diario/2026-11-11.md');

    // Delete file -> pruned from index
    await noteFile.delete();
    final fourth = await index.sync();
    expect(fourth.removed, 1);
    expect(await index.search('térmicos'), isEmpty);
  });

  test('search handles Portuguese accents, stopwords, and natural questions',
      () async {
    await vault.dailyNote(
      DateTime(2026, 11, 5),
      'Reunião sobre calibração dos sensores de proximidade e giroscópio.',
    );
    await vault.dailyNote(
      DateTime(2026, 11, 6),
      'Lista de mercado: café e pão.',
    );
    await vault.saveMemory(
      'Sensores',
      'Referência técnica de sensores MEMS no Android.',
    );

    final db = await _openInMemoryDb();
    final index = await VaultSearchService.open(
      vaultRoot: tempDir,
      database: db,
    );
    addTearDown(index.close);
    await index.sync();

    final hits = await index.search(
      'O que anotei na reunião sobre sensores e calibração?',
      limit: 3,
    );
    expect(hits, isNotEmpty);
    // Notes mentioning sensores / calibracao / reuniao rank at top; mercado excluded
    expect(hits.any((h) => h.path.contains('2026-11-05.md')), isTrue);
    expect(hits.any((h) => h.path.contains('2026-11-06.md')), isFalse);

    // Accent-insensitive query ("reuniao" without tilde finds "Reunião")
    final accentHits = await index.search('reuniao calibracao');
    expect(accentHits, isNotEmpty);
    expect(accentHits.first.path, 'Diario/2026-11-05.md');
  });

  test('search safely handles FTS5 syntax punctuation and operators', () async {
    await vault.dailyNote(
      DateTime(2026, 11, 8),
      'Testar chave "alpha-1" (modo: OR/AND*) sem falhar.',
    );

    final db = await _openInMemoryDb();
    final index = await VaultSearchService.open(
      vaultRoot: tempDir,
      database: db,
    );
    addTearDown(index.close);
    await index.sync();

    final hits = await index.search('chave "alpha-1" (modo: OR/AND*)?');
    expect(hits, isNotEmpty);
    expect(hits.first.path, 'Diario/2026-11-08.md');
  });

  test('buildRagContext formats compact cited excerpts within maxChars',
      () async {
    final longPadding = List.filled(80, 'contexto adicional').join(' ');
    await vault.dailyNote(
      DateTime(2026, 11, 1),
      '$longPadding Marcador crítico: capacitor de 470uF queimou na placa.',
    );

    final db = await _openInMemoryDb();
    final index = await VaultSearchService.open(
      vaultRoot: tempDir,
      database: db,
    );
    addTearDown(index.close);
    await index.sync();

    final rag = await index.buildRagContext(
      'qual capacitor queimou na placa?',
      limit: 3,
      maxChars: 420,
    );
    expect(rag, contains('Diario/2026-11-01.md'));
    expect(rag, contains('470uF'));
    expect(rag.length, lessThanOrEqualTo(420));

    final emptyRag = await index.buildRagContext('termo_inexistente_xyz');
    expect(emptyRag, isEmpty);
  });

  test('rankLexicalDocuments provides deterministic fallback scoring', () {
    const docs = [
      VaultDocumentRecord(
        path: 'Diario/2026-11-01.md',
        folder: 'Diario',
        title: 'Notas Gerais',
        content: 'Hoje revisei o código de rede.',
        modifiedMs: 1000,
        sizeBytes: 30,
      ),
      VaultDocumentRecord(
        path: 'Memoria/Sensores.md',
        folder: 'Memoria',
        title: 'Sensores Android',
        content: 'Acelerômetro e giroscópio para sensores táticos.',
        modifiedMs: 2000,
        sizeBytes: 50,
      ),
    ];

    final hits = VaultSearchService.rankLexicalDocuments(
      docs,
      'sensores giroscopio',
      limit: 2,
    );
    expect(hits.length, 1);
    expect(hits.first.path, 'Memoria/Sensores.md');
    expect(hits.first.snippet, contains('giroscópio'));
  });
}
