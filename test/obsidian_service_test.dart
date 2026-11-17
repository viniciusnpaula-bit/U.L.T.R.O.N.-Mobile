import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/obsidian_service.dart';

void main() {
  late Directory tempDir;
  late ObsidianService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ultron_obsidian_test_');
    service = ObsidianService(tempDir);
    await service.initialize();
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('initializes Second Brain vault structure and config files', () async {
    expect(await Directory('${tempDir.path}/.obsidian').exists(), isTrue);
    expect(await Directory('${tempDir.path}/Diario').exists(), isTrue);
    expect(await Directory('${tempDir.path}/Memoria').exists(), isTrue);
    expect(await Directory('${tempDir.path}/Inbox').exists(), isTrue);
    expect(await Directory('${tempDir.path}/Skills').exists(), isTrue);

    // .obsidian/app.json ensures the official Obsidian app recognizes the vault
    final appJson = File('${tempDir.path}/.obsidian/app.json');
    expect(await appJson.exists(), isTrue);
    expect(await appJson.readAsString(), contains('livePreview'));

    // Memoria/Segundo_Cerebro.md seeded
    final indexFile = File('${tempDir.path}/Memoria/Segundo_Cerebro.md');
    expect(await indexFile.exists(), isTrue);
    expect(await indexFile.readAsString(), contains('Segundo Cérebro'));

    // Memoria/Operador.md seeded
    final opFile = File('${tempDir.path}/Memoria/Operador.md');
    expect(await opFile.exists(), isTrue);
    expect(await opFile.readAsString(), contains('Perfil do Operador'));

    // Default skills seeded
    final skills = await service.listSkills();
    expect(skills.length, greaterThanOrEqualTo(3));
    expect(skills.any((s) => s.id == 'modo_estudo'), isTrue);
  });

  test('captures ideas to Inbox with timestamp', () async {
    final file = await service.captureToInbox('Implementar automação de backup');
    expect(await file.exists(), isTrue);
    expect(file.path, contains('Inbox'));
    final content = await file.readAsString();
    expect(content, contains('Implementar automação de backup'));
  });

  test('saves and updates persistent topics in Memoria/', () async {
    final file = await service.saveMemory('Projetos', 'Projeto U.L.T.R.O.N. v1.2.1 ativo.');
    expect(await file.exists(), isTrue);
    expect(file.path, contains('Memoria'));
    expect(await file.readAsString(), contains('Projeto U.L.T.R.O.N. v1.2.1'));

    // Appending update
    await service.saveMemory('Projetos', 'Fase 1 de wake word e memória concluída.');
    final updated = await file.readAsString();
    expect(updated, contains('Fase 1'));
  });

  test('reads long-term memory for contextual LLM prompt injection', () async {
    await service.dailyNote(DateTime.now(), 'Teste de rotina matinal');
    final memory = await service.readLongTermMemory();
    expect(memory, contains('Perfil do Operador'));
    expect(memory, contains('Teste de rotina matinal'));
  });

  test('generates valid official obsidian:// open URI', () {
    expect(service.obsidianOpenUri, startsWith('obsidian://open?vault='));
  });
}
