import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ultron_mobile/models/tactical_mode.dart';
import 'package:ultron_mobile/services/device_control_service.dart';
import 'package:ultron_mobile/services/obsidian_service.dart';
import 'package:ultron_mobile/services/opengym_service.dart';
import 'package:ultron_mobile/services/slash_command_parser.dart';
import 'package:ultron_mobile/services/vault_search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('OpenGymService offline import', () {
    test('parses openGym JSON backup with workouts, routines, bodyweight and Epley PRs',
        () {
      final sampleJson = jsonEncode({
        'exercises': [
          {'id': 'ex_bench', 'name': 'Supino Reto', 'muscleGroup': 'Peito'},
          {'id': 'ex_squat', 'name': 'Agachamento Livre', 'muscleGroup': 'Pernas'},
        ],
        'routines': [
          {
            'name': 'Push A',
            'exercises': [
              {'exerciseId': 'ex_bench'},
              {'name': 'Desenvolvimento Militar'},
            ],
          },
        ],
        'bodyWeights': [
          {'date': '2026-11-01', 'weight': 78.2},
          {'date': '2026-11-24', 'weight': 79.4},
        ],
        'workouts': [
          {
            'name': 'Treino Peito e Tríceps',
            'date': '2026-11-24T18:30:00Z',
            'durationMinutes': 55,
            'notes': 'Boa progressão de carga',
            'exercises': [
              {
                'exerciseId': 'ex_bench',
                'sets': [
                  {'weight': 80, 'reps': 8, 'completed': true},
                  {'weight': 90, 'reps': 5, 'completed': true},
                ],
              },
              {
                'exerciseId': 'ex_squat',
                'sets': [
                  {'weight': 120, 'reps': 6, 'completed': true},
                ],
              },
            ],
          },
        ],
      });

      final summary = OpenGymService.parseJsonExport(
        sampleJson,
        sourceName: 'opengym-state.json',
      );

      expect(summary.isEmpty, isFalse);
      expect(summary.workouts.length, 1);
      expect(summary.routines.length, 1);
      expect(summary.routines.first.name, 'Push A');
      expect(summary.routines.first.exercises, contains('Supino Reto'));
      expect(summary.weightEntries.length, 2);
      expect(summary.personalRecords.length, 2);

      // Agachamento 120x6 -> Epley 1RM = 120 * (1 + 6/30) = 144.0 kg (top PR)
      final topPr = summary.personalRecords.first;
      expect(topPr.exerciseName, 'Agachamento Livre');
      expect(topPr.maxWeightKg, 120);
      expect(topPr.repsAtMax, 6);
      expect(topPr.estimated1RmKg, closeTo(144.0, 0.01));

      final md = summary.toObsidianMarkdown(syncedAt: DateTime(2026, 11, 25));
      expect(md, contains('# openGym - Resumo de Treinos (Offline)'));
      expect(md, contains('Agachamento Livre'));
      expect(md, contains('Supino Reto'));
      expect(md, contains('79.4 kg'));
      expect(md, contains('+1.2 kg'));
    });

    test('parses openGym CSV workout and bodyweight exports', () {
      const workoutCsv = 'Date,Workout,Exercise,Weight,Reps\n'
          '2026-11-20,Costas B,Remada Curvada,70,10\n'
          '2026-11-20,Costas B,Remada Curvada,75,8\n'
          '2026-11-22,Pernas A,Leg Press,220,12\n';
      final wSummary = OpenGymService.parseCsvExport(
        workoutCsv,
        sourceName: 'opengym_workouts.csv',
      );
      expect(wSummary.workouts.length, 2);
      expect(wSummary.personalRecords.first.exerciseName, 'Leg Press');
      expect(wSummary.personalRecords.first.maxWeightKg, 220);

      const weightCsv = 'date,bodyweight\n2026-11-01,77.5\n2026-11-25,78.8\n';
      final bwSummary = OpenGymService.parseCsvExport(
        weightCsv,
        sourceName: 'opengym_weight.csv',
      );
      expect(bwSummary.weightEntries.length, 2);
      expect(bwSummary.weightEntries.last.weightKg, 78.8);
    });

    test('importFile writes Memoria/Treino/OpenGym_Resumo.md and feeds Modo Treino RAG',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('ultron_opengym_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final backupFile = File(p.join(tempDir.path, 'opengym-state.json'));
      await backupFile.writeAsString(
        jsonEncode({
          'workouts': [
            {
              'name': 'Hipertrofia Superior',
              'date': '2026-11-24',
              'exercises': [
                {
                  'name': 'Supino Inclinado Halter',
                  'sets': [
                    {'weight': 36, 'reps': 10},
                  ],
                },
              ],
            },
          ],
        }),
      );

      final vaultDir = Directory(p.join(tempDir.path, 'vault'));
      final vault = ObsidianService(vaultDir);
      await vault.initialize();

      final openGym = OpenGymService();
      final imported = await openGym.importFile(backupFile, obsidian: vault);
      expect(imported.savedNotePath, OpenGymService.summaryNotePath);

      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final search = await VaultSearchService.open(
        vaultRoot: vaultDir,
        database: db,
      );
      addTearDown(search.close);
      await search.sync(force: true);

      final device = DeviceControlService(
        obsidianProvider: () async => vault,
        vaultSearchProvider: () async => search,
      );

      final treinoPrompt = await device.buildContextualSystemPrompt(
        userQuery: 'qual foi meu peso no supino inclinado?',
        mode: TacticalMode.treino,
      );
      expect(treinoPrompt, contains('OpenGym_Resumo.md'));
      expect(treinoPrompt, contains('Supino Inclinado Halter'));

      final musicaPrompt = await device.buildContextualSystemPrompt(
        userQuery: 'qual foi meu peso no supino inclinado?',
        mode: TacticalMode.musica,
      );
      expect(musicaPrompt, isNot(contains('OpenGym_Resumo.md')));
    });
  });

  group('Slash commands & Dynamic Island MethodChannel', () {
    const channel = MethodChannel('com.viniciusnpaula.ultron_mobile/device');
    final recordedCalls = <MethodCall>[];

    setUp(() {
      recordedCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        recordedCalls.add(call);
        switch (call.method) {
          case 'setDynamicIsland':
            return call.arguments['enabled'] == true;
          case 'isDynamicIslandRunning':
            return true;
          case 'updateDynamicIslandState':
          case 'setDynamicIslandAccent':
            return true;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('SlashCommandParser parses /opengym and /ilha commands', () {
      final gym = SlashCommandParser.parse('/opengym importar');
      expect(gym, isNotNull);
      expect(gym!.command, UltronCommand.opengym);
      expect(gym.argument, 'importar');

      final gymAlias = SlashCommandParser.parse('/gym resumo');
      expect(gymAlias!.command, UltronCommand.opengym);
      expect(gymAlias.argument, 'resumo');

      final island = SlashCommandParser.parse('/ilha on');
      expect(island, isNotNull);
      expect(island!.command, UltronCommand.island);
      expect(island.argument, 'on');

      final cutout = SlashCommandParser.parse('/cutout status');
      expect(cutout!.command, UltronCommand.island);
      expect(cutout.argument, 'status');
    });

    test('DeviceControlService invokes Dynamic Island native channel methods',
        () async {
      final device = DeviceControlService();

      expect(await device.setDynamicIsland(true), isTrue);
      expect(await device.isDynamicIslandRunning(), isTrue);
      await device.setDynamicIslandAccent(0xFFF10D28);
      await device.updateDynamicIslandState(
        mode: 'listening',
        title: 'Ouvindo...',
        detail: 'Microfone nativo',
      );

      expect(
        recordedCalls.map((c) => c.method),
        containsAll([
          'setDynamicIsland',
          'isDynamicIslandRunning',
          'setDynamicIslandAccent',
          'updateDynamicIslandState',
        ]),
      );

      final updateCall = recordedCalls.firstWhere(
        (c) => c.method == 'updateDynamicIslandState',
      );
      expect(updateCall.arguments['mode'], 'listening');
      expect(updateCall.arguments['title'], 'Ouvindo...');
    });
  });
}
