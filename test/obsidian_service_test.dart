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

  test('falls back to app-private Skills directory and prefers readable primary skills',
      () async {
    final fallbackSkillsDir =
        await Directory.systemTemp.createTemp('ultron_fallback_skills_');
    final isolatedRoot =
        await Directory.systemTemp.createTemp('ultron_empty_primary_');
    addTearDown(() async {
      if (await fallbackSkillsDir.exists()) {
        await fallbackSkillsDir.delete(recursive: true);
      }
      if (await isolatedRoot.exists()) {
        await isolatedRoot.delete(recursive: true);
      }
    });

    await File('${fallbackSkillsDir.path}/modo_estudo.md')
        .writeAsString('# Modo Estudo Fallback\n[ACTION:VOLUME_MUTE]\n');
    await File('${fallbackSkillsDir.path}/somente_app.md')
        .writeAsString('# Skill Exclusiva do App\n[ACTION:VIBRATE]\n');

    await Directory('${isolatedRoot.path}/Skills').create(recursive: true);
    await File('${isolatedRoot.path}/Skills/modo_estudo.md')
        .writeAsString('# Modo Estudo Customizado\n[ACTION:TORCH_ON]\n');

    final scoped = ObsidianService(
      isolatedRoot,
      fallbackSkillsDir: fallbackSkillsDir,
    );
    final skills = await scoped.listSkills();
    expect(skills.length, 2);
    final estudo = skills.firstWhere((s) => s.id == 'modo_estudo');
    expect(estudo.title, 'Modo Estudo Customizado');
    expect(skills.any((s) => s.id == 'somente_app'), isTrue);
  });

  test('OBSIDIAN_LIST and OBSIDIAN_READ list notes by folder and block path traversal',
      () async {
    await service.saveMemory('Arquitetura', 'Núcleo tático v1.5');
    await service.captureToInbox('Revisar sensores');

    final memNotes = await service.listNotes(folder: 'Memoria');
    expect(memNotes.any((n) => n.relativePath == 'Memoria/Arquitetura.md'),
        isTrue);
    expect(memNotes.every((n) => n.folder == 'Memoria'), isTrue);

    final inboxNotes = await service.listNotes(folder: 'Inbox');
    expect(inboxNotes.length, 1);

    final readContent = await service.readNote('Memoria/Arquitetura.md');
    expect(readContent, contains('Núcleo tático v1.5'));

    // Short name resolution inside standard folders
    final readByShortName = await service.readNote('Arquitetura');
    expect(readByShortName, contains('Núcleo tático v1.5'));

    // Strict path traversal blocking
    expect(
      () => service.readNote('../segredo.md'),
      throwsArgumentError,
    );
    expect(
      () => service.readNote('Memoria/../../etc/passwd'),
      throwsArgumentError,
    );
    expect(
      () => service.readNote('/etc/passwd'),
      throwsArgumentError,
    );
    expect(
      () => service.readNote('.obsidian/app.json'),
      throwsArgumentError,
    );
  });

  test('OBSIDIAN_APPEND, OBSIDIAN_TASKS, OBSIDIAN_STATUS and UNDO stack work end-to-end',
      () async {
    // 1. Append to existing note
    await service.appendToNote(
      'Memoria/Operador.md',
      '- [ ] Configurar radar LAN\n- [x] Revisar protocolo NFC',
    );
    final afterAppend = await service.readNote('Memoria/Operador.md');
    expect(afterAppend, contains('Configurar radar LAN'));

    // 2. List and toggle Markdown tasks
    final tasks = await service.listTasks(notePath: 'Memoria/Operador.md');
    expect(tasks.length, 2);
    expect(tasks[0].text, 'Configurar radar LAN');
    expect(tasks[0].completed, isFalse);
    expect(tasks[1].completed, isTrue);

    final toggled = await service.setTaskCompletion(
      notePath: 'Memoria/Operador.md',
      taskIndex: 1,
      completed: true,
    );
    expect(toggled.completed, isTrue);
    expect(
      await service.readNote('Memoria/Operador.md'),
      contains('- [x] Configurar radar LAN'),
    );

    // 3. Vault Status
    final status = await service.getVaultStatus();
    expect(status.totalNotes, greaterThanOrEqualTo(5));
    expect(status.totalSizeBytes, greaterThan(0));
    expect(status.vaultPath, tempDir.path);
    expect(status.undoDepth, greaterThanOrEqualTo(2));

    // 4. Undo task completion -> reverts checkbox back to [ ]
    final undoTask = await service.undoLastMutation();
    expect(undoTask.undone, isTrue);
    expect(undoTask.operation, 'OBSIDIAN_TASKS');
    expect(
      await service.readNote('Memoria/Operador.md'),
      contains('- [ ] Configurar radar LAN'),
    );

    // 5. Undo append -> restores original Operador.md without the appended tasks
    final undoAppend = await service.undoLastMutation();
    expect(undoAppend.undone, isTrue);
    expect(undoAppend.operation, 'OBSIDIAN_APPEND');
    expect(
      await service.readNote('Memoria/Operador.md'),
      isNot(contains('Configurar radar LAN')),
    );

    // 6. Undo newly created Inbox file -> removes the created file
    final ideaFile = await service.captureToInbox('Ideia temporária para undo');
    expect(await ideaFile.exists(), isTrue);
    final undoInbox = await service.undoLastMutation();
    expect(undoInbox.undone, isTrue);
    expect(undoInbox.deletedCreatedFile, isTrue);
    expect(await ideaFile.exists(), isFalse);
  });

  test('SKILL_CREATE and SKILL_DELETE create and remove skills in Skills/*.md with UNDO support',
      () async {
    final created = await service.createSkill(
      'Modo Missão',
      '# Modo Missão\n[ACTION:TORCH_ON]\n[ACTION:VOLUME_SET:90]',
    );
    expect(created.id, 'modo_missão');
    expect(created.title, 'Modo Missão');
    final found = await service.findSkill('modo_missão');
    expect(found, isNotNull);

    final deleted = await service.deleteSkill('modo_missão');
    expect(deleted, isTrue);
    expect(await service.findSkill('modo_missão'), isNull);

    // Undo restores the deleted skill
    final undone = await service.undoLastMutation();
    expect(undone.undone, isTrue);
    expect(undone.operation, 'SKILL_DELETE');
    expect(await service.findSkill('modo_missão'), isNotNull);
  });

  test('Arquivo de Vida seeds Inventario folder, garantias skill and builds structured warranty note',
      () async {
    expect(ObsidianService.standardFolders, contains('Inventario'));
    expect(ObsidianService.normalizeFolderFilter('garantias'), 'Inventario');
    expect(await Directory('${tempDir.path}/Inventario').exists(), isTrue);

    final garantiasSkill = await service.findSkill('garantias');
    expect(garantiasSkill, isNotNull);
    expect(garantiasSkill!.content, contains('OBSIDIAN_APPEND:Inventario/'));
    expect(garantiasSkill.content, contains('REMINDER_CREATE'));

    final reminderAt = ObsidianService.computeWarrantyReminderDate(
      purchaseDate: DateTime(2026, 3, 20),
      warrantyMonths: 12,
      leadDays: 15,
    );
    expect(reminderAt, DateTime(2027, 3, 5, 9, 0));

    final md = ObsidianService.buildWarrantyNoteMarkdown(
      product: 'Monitor LG UltraGear 27',
      purchaseDate: DateTime(2026, 3, 20),
      warrantyMonths: 12,
      resetProcedure: 'Segurar joystick central por 5s -> Menu -> Reset.',
      serialNumber: 'LG-998877',
      vendor: 'KaBuM',
    );
    await service.appendToNote(
      'Inventario/Monitor_LG_UltraGear_27.md',
      md,
      createIfMissing: true,
    );

    final invNotes = await service.listNotes(folder: 'Inventario');
    expect(invNotes.any((n) => n.relativePath == 'Inventario/Monitor_LG_UltraGear_27.md'), isTrue);
    final saved = await service.readNote('Inventario/Monitor_LG_UltraGear_27.md');
    expect(saved, contains('garantia_ate: 2027-03-20'));
    expect(saved, contains('lembrete_preventivo: 2027-03-05'));
    expect(saved, contains('LG-998877'));
  });

  test('Marco 4: Pessoas/ folder, structured profile template and external AI privacy filter',
      () async {
    expect(ObsidianService.standardFolders, contains('Pessoas'));
    expect(ObsidianService.normalizeFolderFilter('contatos'), 'Pessoas');
    expect(await Directory('${tempDir.path}/Pessoas').exists(), isTrue);

    final profile = ObsidianService.buildPersonProfileMarkdown(
      name: 'Carlos Silva',
      relation: 'Colega de Engenharia',
      profession: 'Técnico em Automação',
      phone: '(11) 98765-4321',
      email: 'carlos.silva@empresa.com.br',
      address: 'Rua das Flores, 120 - São Paulo',
      interests: 'CLPs Siemens e inversores WEG',
      notes: 'Contato direto carlos@teste.com e CPF 123.456.789-00.',
    );
    await service.appendToNote(
      'Pessoas/Carlos_Silva.md',
      profile,
      createIfMissing: true,
    );

    final sanitized = ObsidianService.sanitizeForExternalAi(profile);
    expect(sanitized, contains('Carlos Silva'));
    expect(sanitized, contains('CLPs Siemens'));
    expect(sanitized, isNot(contains('98765-4321')));
    expect(sanitized, isNot(contains('carlos.silva@empresa.com.br')));
    expect(sanitized, isNot(contains('Rua das Flores')));
    expect(sanitized, isNot(contains('123.456.789-00')));
    expect(sanitized, contains('[email ocultado]'));
    expect(sanitized, contains('[cpf ocultado]'));
  });

  test('OKF metadata parses inline/block YAML, preserves legacy notes, and verifies/renews stale notes',
      () async {
    // 1. Parse inline and multi-line block sources while preserving extra YAML keys
    const rawBlock = '''---
tipo: garantia
produto: "Osciloscópio Rigol"
sources:
  - nota_fiscal_pdf
  - operador
verified: false
stale_after: 2026-10-01
updated_at: 2026-09-01T10:00:00Z
---
# Osciloscópio Rigol
Detalhes técnicos.''';
    final parsed = OkfMetadata.parse(rawBlock);
    expect(parsed.metadata.hasFrontmatter, isTrue);
    expect(parsed.metadata.sources, ['nota_fiscal_pdf', 'operador']);
    expect(parsed.metadata.verified, isFalse);
    expect(parsed.metadata.staleAfterIso, '2026-10-01');
    expect(parsed.metadata.extraFields['tipo'], 'garantia');
    expect(parsed.metadata.isStale(now: DateTime(2026, 11, 26)), isTrue);
    expect(parsed.body, contains('# Osciloscópio Rigol'));
    expect(parsed.body, isNot(contains('stale_after:')));

    // 2. Legacy notes without frontmatter remain 100% compatible
    final legacyFile = File('${tempDir.path}/Memoria/Legada.md');
    await legacyFile.writeAsString('# Nota Legada\nConteúdo antigo sem YAML.\n');
    await service.saveMemory('Legada', 'Novo registro compatível.');
    final legacyAfter = await legacyFile.readAsString();
    expect(legacyAfter.startsWith('# Nota Legada'), isTrue);
    expect(legacyAfter, contains('Novo registro compatível.'));

    // 3. readLongTermMemory signals stale and unverified context notes
    await File('${tempDir.path}/Memoria/Operador.md').writeAsString(
      '---\nsources: [ultron_seed]\nverified: false\nstale_after: 2026-10-15\nupdated_at: 2026-09-15T10:00:00Z\n---\n'
      '# Perfil do Operador\n- Nome: Operador\n',
    );
    await service.savePreferences(
      'Preferir respostas diretas.',
      sources: ['operador'],
      verified: true,
      staleDays: 30,
      now: DateTime(2026, 11, 20),
    );
    final ltmWithWarning = await service.readLongTermMemory(
      now: DateTime(2026, 11, 26),
    );
    expect(ltmWithWarning, contains('VENCIDA desde 2026-10-15'));
    expect(ltmWithWarning, contains('NÃO VERIFICADA'));

    final ltmExcluded = await service.readLongTermMemory(
      now: DateTime(2026, 11, 26),
      excludeStale: true,
    );
    expect(ltmExcluded, contains('ALERTA OKF: nota vencida desde 2026-10-15'));
    expect(ltmExcluded, isNot(contains('- Nome: Operador')));

    // 4. listStaleNotes and verifyNote renew validity + support UNDO
    final staleList = await service.listStaleNotes(now: DateTime(2026, 11, 26));
    expect(staleList.any((n) => n.relativePath == 'Memoria/Operador.md'), isTrue);

    final verifiedStatus = await service.verifyNote(
      'Memoria/Operador.md',
      renewDays: 30,
      addSources: ['revisao_manual'],
      now: DateTime(2026, 11, 26),
    );
    expect(verifiedStatus.metadata.isVerified, isTrue);
    expect(verifiedStatus.isStale, isFalse);
    expect(verifiedStatus.metadata.staleAfterIso, '2026-12-26');
    expect(verifiedStatus.metadata.sources, contains('revisao_manual'));

    final staleAfterVerify =
        await service.listStaleNotes(now: DateTime(2026, 11, 26));
    expect(
      staleAfterVerify.any((n) => n.relativePath == 'Memoria/Operador.md'),
      isFalse,
    );

    final undone = await service.undoLastMutation();
    expect(undone.undone, isTrue);
    expect(undone.operation, 'OBSIDIAN_VERIFY');
  });
}
