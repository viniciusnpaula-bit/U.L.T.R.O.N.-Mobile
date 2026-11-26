import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

    test('parses compressed FlateDecode openGym PDF report offline and writes Obsidian note',
        () async {
      // Monta um PDF válido com stream FlateDecode (zlib) contendo um relatório real do openGym
      const pdfContent = 'BT\n'
          '/F1 12 Tf\n'
          '(2026-11-25 - Treino Peito e Pernas) Tj\n'
          'T*\n'
          '(Peso corporal: 79.6 kg) Tj\n'
          'T*\n'
          '(Supino Reto 90 kg x 6) Tj\n'
          'T*\n'
          '(Agachamento Livre 4 x 8 @ 110 kg) Tj\n'
          'ET\n';
      final compressed = zlib.encode(latin1.encode(pdfContent));
      final pdfBuilder = BytesBuilder()
        ..add(latin1.encode('%PDF-1.4\n1 0 obj\n<< /Filter /FlateDecode /Length ${compressed.length} >>\nstream\n'))
        ..add(compressed)
        ..add(latin1.encode('\nendstream\nendobj\n%%EOF\n'));
      final pdfBytes = pdfBuilder.toBytes();

      final tempDir =
          await Directory.systemTemp.createTemp('ultron_opengym_pdf_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final pdfFile = File(p.join(tempDir.path, 'opengym_relatorio.pdf'));
      await pdfFile.writeAsBytes(pdfBytes);

      final vaultDir = Directory(p.join(tempDir.path, 'vault'));
      final vault = ObsidianService(vaultDir);
      await vault.initialize();

      final summary = await OpenGymService().importFile(
        pdfFile,
        obsidian: vault,
      );

      expect(summary.isEmpty, isFalse);
      expect(summary.savedNotePath, OpenGymService.summaryNotePath);
      expect(summary.workouts.length, 1);
      expect(summary.workouts.first.name, 'Treino Peito e Pernas');
      expect(summary.weightEntries.length, 1);
      expect(summary.weightEntries.first.weightKg, 79.6);
      expect(summary.personalRecords.length, 2);
      expect(summary.personalRecords.first.exerciseName, 'Agachamento Livre');
      expect(summary.personalRecords.first.maxWeightKg, 110);

      final note = await vault.readNote(OpenGymService.summaryNotePath);
      expect(note, contains('Agachamento Livre'));
      expect(note, contains('Supino Reto'));
      expect(note, contains('79.6 kg'));
      expect(note, contains('Relatório Extraído (PDF)'));
    });

    test('parses weekly routine PDF with multiline exercises and rep ranges', () {
      const planText = '''
Treino A - Peito e Tríceps
Supino Inclinado com Halteres
3 x 8-12
Crucifixo Máquina
4 x 10-12
Tríceps Pulley Corda - 3x12-15

Treino B - Costas e Bíceps
Puxada Frente Aberta 4 x 8-10
Remada Baixa 3 séries de 12 reps
''';
      final summary = OpenGymService.parsePdfReportText(
        planText,
        sourceName: 'plano_opengym.pdf',
      );
      expect(summary.isEmpty, isFalse);
      expect(summary.routines.length, 2);
      expect(summary.routines[0].name, 'Treino A - Peito e Tríceps');
      expect(
        summary.routines[0].exercises,
        containsAll([
          'Supino Inclinado com Halteres',
          'Crucifixo Máquina',
          'Tríceps Pulley Corda',
        ]),
      );
      expect(summary.routines[1].name, 'Treino B - Costas e Bíceps');
      expect(summary.speakText, isNot(contains('0 treinos')));
      expect(summary.speakText, contains('2 rotinas'));
      expect(summary.formatChatSummary(), contains('Rotinas identificadas'));
    });

    test('extractTextFromPdfBytes decodes beginbfrange array CMaps and importFile uses native extractor',
        () async {
      const cmapAndContent = '''
/CIDInit /ProcSet findresource begin
begincmap
1 beginbfrange
<0001> <0006> [<0053> <0075> <0070> <0069> <006E> <006F>]
endbfrange
endcmap
BT
/F1 12 Tf
<000100020003000400050006> Tj
T*
(80 kg x 10) Tj
ET
''';
      final compressed = zlib.encode(latin1.encode(cmapAndContent));
      final pdfBuilder = BytesBuilder()
        ..add(latin1.encode(
            '%PDF-1.4\n1 0 obj\n<< /Filter /FlateDecode /Length ${compressed.length} >>\nstream\n'))
        ..add(compressed)
        ..add(latin1.encode('\nendstream\nendobj\n%%EOF\n'));
      final extracted =
          OpenGymService.extractTextFromPdfBytes(pdfBuilder.toBytes());
      expect(extracted, contains('Supino'));
      expect(extracted, contains('80 kg x 10'));

      // Testa fluxo com extrator nativo Android PDFBox via MethodChannel
      const channel = MethodChannel('com.viniciusnpaula.ultron_mobile/device');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'extractPdfTextNative') {
          return '2026-11-26 - Pernas Foco Quadríceps\nAgachamento Búlgaro 24 kg x 12\n';
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final tempDir =
          await Directory.systemTemp.createTemp('ultron_opengym_native_pdf_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final dummyPdf = File(p.join(tempDir.path, 'relatorio_android.pdf'));
      await dummyPdf.writeAsBytes(latin1.encode('%PDF-1.5\n%%EOF'));
      final vault = ObsidianService(Directory(p.join(tempDir.path, 'vault')));
      await vault.initialize();

      final nativeSummary = await OpenGymService().importFile(
        dummyPdf,
        obsidian: vault,
      );
      expect(nativeSummary.isEmpty, isFalse);
      expect(nativeSummary.workouts.length, 1);
      expect(nativeSummary.workouts.first.name, 'Pernas Foco Quadríceps');
      expect(
        nativeSummary.personalRecords.first.exerciseName,
        'Agachamento Búlgaro',
      );
      expect(nativeSummary.personalRecords.first.maxWeightKg, 24);
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
          case 'openDynamicIslandConfigurator':
            return true;
          case 'getDynamicIslandConfig':
          case 'resetDynamicIslandConfig':
            return <String, Object>{
              'enabled': true,
              'customPosition': false,
              'orientation': 'auto',
              'zoneLabel': 'Topo (Câmera)',
            };
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
      expect(await device.openDynamicIslandConfigurator(), isTrue);
      final cfg = await device.getDynamicIslandConfig();
      expect(cfg['zoneLabel'], 'Topo (Câmera)');
      final reset = await device.resetDynamicIslandConfig();
      expect(reset['orientation'], 'auto');
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
          'openDynamicIslandConfigurator',
          'getDynamicIslandConfig',
          'resetDynamicIslandConfig',
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
