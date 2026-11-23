import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultron_mobile/models/tactical_mode.dart';
import 'package:ultron_mobile/services/device_control_service.dart';
import 'package:ultron_mobile/services/obsidian_service.dart';
import 'package:ultron_mobile/services/vault_search_service.dart';

void main() {
  sqfliteFfiInit();

  test('TacticalMode.parse resolves canonical names and aliases', () {
    expect(TacticalMode.parse('eng'), TacticalMode.engenharia);
    expect(TacticalMode.parse('ENEM'), TacticalMode.estudos);
    expect(TacticalMode.parse('dieta'), TacticalMode.treino);
    expect(TacticalMode.parse('código'), TacticalMode.dev);
    expect(TacticalMode.parse('padrão'), TacticalMode.geral);
    expect(TacticalMode.parse('desconhecido'), isNull);
  });

  test('buildSystemPromptForMode trims irrelevant tools and saves tokens on specialist modes',
      () {
    final fullPrompt = DeviceControlService.buildSystemPromptForMode(
      TacticalMode.geral,
    );
    final studyPrompt = DeviceControlService.buildSystemPromptForMode(
      TacticalMode.estudos,
    );
    final devPrompt = DeviceControlService.buildSystemPromptForMode(
      TacticalMode.dev,
    );

    expect(fullPrompt, DeviceControlService.aiSystemPrompt);
    // Specialist prompts must be substantially shorter than the full prompt
    expect(studyPrompt.length, lessThan(fullPrompt.length * 0.55));
    expect(devPrompt.length, lessThan(fullPrompt.length * 0.6));

    // Core tools remain available in specialist modes
    expect(studyPrompt, contains('[ACTION:NOTE:'));
    expect(studyPrompt, contains('[ACTION:REMINDER_CREATE:'));
    expect(studyPrompt, contains('Memoria/Estudos'));

    // Irrelevant tools are excluded from Estudos
    expect(studyPrompt, isNot(contains('PC_EXEC_TOOL')));
    expect(studyPrompt, isNot(contains('SPOTIFY_PLAY')));
    expect(studyPrompt, isNot(contains('WHATSAPP')));

    // Dev mode keeps Desktop bridge tools but excludes Spotify
    expect(devPrompt, contains('PC_EXEC_TOOL'));
    expect(devPrompt, isNot(contains('SPOTIFY_PLAY')));
  });

  test('buildContextualSystemPrompt scopes RAG FTS5 to active TacticalMode folder',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('ultron_tactical_mode_test_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final vault = ObsidianService(tempDir);
    await vault.initialize();
    await vault.appendToNote(
      'Memoria/Engenharia/Inversor.md',
      '# Inversor Trifásico\nFrequência nominal de 60Hz com rampa de aceleração.',
      createIfMissing: true,
    );
    await vault.appendToNote(
      'Memoria/Treino/Cardio.md',
      '# Cardio HIIT\nFrequência cardíaca alvo em 165bpm na rampa da esteira.',
      createIfMissing: true,
    );

    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    final search = await VaultSearchService.open(
      vaultRoot: tempDir,
      database: db,
    );
    addTearDown(search.close);
    await search.sync(force: true);

    final device = DeviceControlService(
      obsidianProvider: () async => vault,
      vaultSearchProvider: () async => search,
    );

    final engPrompt = await device.buildContextualSystemPrompt(
      userQuery: 'qual a frequencia na rampa?',
      mode: TacticalMode.engenharia,
    );
    expect(engPrompt, contains('Memoria/Engenharia/Inversor.md'));
    expect(engPrompt, isNot(contains('Memoria/Treino/Cardio.md')));
    expect(engPrompt, contains('MODO ENGENHARIA/AUTOMAÇÃO'));

    final treinoPrompt = await device.buildContextualSystemPrompt(
      userQuery: 'qual a frequencia na rampa?',
      mode: TacticalMode.treino,
    );
    expect(treinoPrompt, contains('Memoria/Treino/Cardio.md'));
    expect(treinoPrompt, isNot(contains('Memoria/Engenharia/Inversor.md')));
    expect(treinoPrompt, contains('MODO TREINO/DIETA'));
  });
}
