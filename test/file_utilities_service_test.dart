import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ultron_mobile/core/security/action_gate.dart';
import 'package:ultron_mobile/core/security/auth_gate.dart';
import 'package:ultron_mobile/services/device_control_service.dart';
import 'package:ultron_mobile/services/file_utilities_service.dart';
import 'package:ultron_mobile/services/obsidian_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FileUtilitiesService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ultron_file_utils_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('limpar_duplicados detects SHA-256 duplicates, preserves original, and deletes copies only when confirmed', () async {
      final original = File(p.join(tempDir.path, 'comprovante.pdf'));
      final copy = File(p.join(tempDir.path, 'comprovante (1).pdf'));
      final unique = File(p.join(tempDir.path, 'outro.txt'));

      await original.writeAsBytes(List<int>.generate(64, (i) => i));
      await copy.writeAsBytes(List<int>.generate(64, (i) => i));
      await unique.writeAsString('conteudo diferente com mesmo ou outro tamanho');

      final service = FileUtilitiesService(
        defaultDirectoryResolver: () async => tempDir.path,
      );

      final dryReport = await service.cleanDuplicates(dryRun: true);
      expect(dryReport.duplicates.length, 1);
      expect(dryReport.duplicates.first.originalPath, original.path);
      expect(dryReport.duplicates.first.duplicatePath, copy.path);
      expect(dryReport.deletedCount, 0);
      expect(await copy.exists(), isTrue);

      final deleteReport = await service.cleanDuplicates(dryRun: false);
      expect(deleteReport.deletedCount, 1);
      expect(await original.exists(), isTrue);
      expect(await copy.exists(), isFalse);
      expect(await unique.exists(), isTrue);
    });

    test('converter_imagens converts .webp and .heic to .jpg/.png without overwriting existing files', () async {
      final webpFile = File(p.join(tempDir.path, 'foto.webp'));
      final heicFile = File(p.join(tempDir.path, 'captura.heic'));
      final existingJpg = File(p.join(tempDir.path, 'foto.jpg'));
      final untouchedTxt = File(p.join(tempDir.path, 'notas.txt'));

      await webpFile.writeAsBytes(<int>[1, 2, 3, 4]);
      await heicFile.writeAsBytes(<int>[5, 6, 7, 8]);
      await existingJpg.writeAsBytes(<int>[9, 9, 9]);
      await untouchedTxt.writeAsString('nao converter');

      final service = FileUtilitiesService(
        defaultDirectoryResolver: () async => tempDir.path,
      );

      final jpgReport = await service.convertImages(targetFormat: 'jpg');
      expect(jpgReport.convertedFiles.length, 2);
      // foto.jpg já existia -> gerou foto_2.jpg (destino seguro sem sobrescrita)
      expect(File(p.join(tempDir.path, 'foto_2.jpg')).existsSync(), isTrue);
      expect(File(p.join(tempDir.path, 'captura.jpg')).existsSync(), isTrue);
      expect(await existingJpg.readAsBytes(), <int>[9, 9, 9]);
      expect(await webpFile.exists(), isTrue);
      expect(await heicFile.exists(), isTrue);

      final pngReport = await service.convertImages(targetFormat: 'png');
      expect(pngReport.convertedFiles.length, 2);
      expect(File(p.join(tempDir.path, 'foto.png')).existsSync(), isTrue);
      expect(File(p.join(tempDir.path, 'captura.png')).existsSync(), isTrue);
    });

    test('organizar_pdf_downloads standardizes filenames to AAAA-MM-DD - Assunto.pdf', () async {
      final rawBr = File(p.join(tempDir.path, 'boleto_internet_22-11-2026.pdf'));
      final rawIso = File(p.join(tempDir.path, '2026-10-05_extrato_banco.pdf'));
      final alreadyStd = File(p.join(tempDir.path, '2026-11-01 - Contrato Aluguel.pdf'));

      await rawBr.writeAsString('pdf1');
      await rawIso.writeAsString('pdf2');
      await alreadyStd.writeAsString('pdf3');

      final service = FileUtilitiesService(
        defaultDirectoryResolver: () async => tempDir.path,
      );

      final report = await service.organizePdfDownloads();
      expect(report.alreadyOrganizedCount, 1);
      expect(report.renamedFiles.length, 2);
      expect(
        File(p.join(tempDir.path, '2026-11-22 - Boleto Internet.pdf')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(tempDir.path, '2026-10-05 - Extrato Banco.pdf')).existsSync(),
        isTrue,
      );
      expect(alreadyStd.existsSync(), isTrue);
    });
  });

  group('ActionGate & DeviceControlService integration for Phase 6', () {
    test('ActionGate enforces sensitive + alwaysConfirmInSovereign on CLEAN_DUPLICATES', () {
      const gate = ActionGate();
      final cleanSim = gate.simulate('[ACTION:CLEAN_DUPLICATES:Downloads]');
      expect(cleanSim.riskLevel, RiskLevel.sensitive);
      expect(cleanSim.requiresConfirmation, isTrue);

      // Even in sovereign mode, CLEAN_DUPLICATES demands confirmation before deleting
      final sovereignDecision =
          gate.evaluatePrivilege(cleanSim, AccessLevel.sovereign);
      expect(sovereignDecision.allowed, isTrue);
      expect(sovereignDecision.requiresConfirmation, isTrue);

      final basicDecision = gate.evaluatePrivilege(cleanSim, AccessLevel.basic);
      expect(basicDecision.allowed, isFalse);

      final convSim = gate.simulate('[ACTION:CONVERT_IMAGES:png]');
      expect(convSim.riskLevel, RiskLevel.safe);
      expect(convSim.requiresConfirmation, isFalse);

      final pdfSim = gate.simulate('[ACTION:ORGANIZE_PDFS:Downloads]');
      expect(pdfSim.riskLevel, RiskLevel.sensitive);
      expect(pdfSim.requiresConfirmation, isTrue);
    });

    test('DeviceControlService executes file utilities with confirmation enforcement', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('ultron_dc_file_utils_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final f1 = File(p.join(tempDir.path, 'relatorio.txt'));
      final f2 = File(p.join(tempDir.path, 'relatorio (1).txt'));
      await f1.writeAsString('mesmo conteudo binario');
      await f2.writeAsString('mesmo conteudo binario');

      final auth = AuthGate();
      await auth.authenticatePin('1234', (_) async => true);
      // Simulate NFC elevated session so sensitive actions can proceed to confirmation
      await auth.authenticateNfc('TAG01', (_) async => true);

      const channel = MethodChannel('com.viniciusnpaula.ultron_mobile/device');
      final service = DeviceControlService(
        channel: channel,
        authGate: auth,
        fileUtilitiesProvider: () => FileUtilitiesService(
          channel: channel,
          defaultDirectoryResolver: () async => tempDir.path,
        ),
      );

      // Denied confirmation -> must NOT delete duplicate
      final denied = await service.tryExecuteNaturalCommand(
        'limpar duplicados ${tempDir.path}',
        confirmAction: (_) async => false,
      );
      expect(denied?.handled, isTrue);
      expect(denied?.message, contains('cancelada'));
      expect(await f2.exists(), isTrue);

      // Approved confirmation -> deletes duplicate
      final approved = await service.tryExecuteNaturalCommand(
        'limpar duplicados ${tempDir.path}',
        confirmAction: (_) async => true,
      );
      expect(approved?.handled, isTrue);
      expect(approved?.message, contains('1 duplicado(s) removido(s)'));
      expect(await f1.exists(), isTrue);
      expect(await f2.exists(), isFalse);
    });

    test('processBatchDocuments builds Markdown table offline and delegates PDFs to Desktop LAN when available',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('ultron_etl_');
      final vaultDir = await Directory.systemTemp.createTemp('ultron_etl_vault_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
        if (await vaultDir.exists()) await vaultDir.delete(recursive: true);
      });

      await File(p.join(tempDir.path, 'fatura_luz.txt')).writeAsString(
        'Fatura Energia 15/11/2026\nTotal a pagar: R\$ 248,90',
      );
      await File(p.join(tempDir.path, 'gastos.csv')).writeAsString(
        'Data,Item,Valor\n2026-11-18,Internet,R\$ 119,90',
      );
      await File(p.join(tempDir.path, '2026-11-10_fatura_cartao.pdf'))
          .writeAsBytes([0x25, 0x50, 0x44, 0x46, 0x2D]);

      final svc = FileUtilitiesService();
      final hybridReport = await svc.processBatchDocuments(
        directoryPath: tempDir.path,
        now: DateTime(2026, 11, 23, 18, 0),
        desktopPdfExtractor: (pdfs) async {
          expect(pdfs.length, 1);
          return '| Fatura | Valor |\n|---|---|\n| Cartão | R\$ 1.250,00 |';
        },
      );
      expect(hybridReport.mode, 'hybrid');
      expect(hybridReport.items.length, 3);
      expect(hybridReport.delegatedPdfCount, 1);
      expect(hybridReport.markdownNote, contains('R\$ 248,90'));
      expect(hybridReport.markdownNote, contains('R\$ 119,90'));
      expect(hybridReport.markdownNote, contains('Consolidação de PDFs via U.L.T.R.O.N. Desktop'));
      expect(hybridReport.markdownNote, contains('R\$ 1.250,00'));

      // End-to-end via executeFileUtilityCommand saves tabular note in Obsidian Inbox/
      final vault = ObsidianService(vaultDir);
      await vault.initialize();
      final device = DeviceControlService(
        obsidianProvider: () async => vault,
        fileUtilitiesProvider: () => svc,
      );
      final res = await device.executeFileUtilityCommand('lote ${tempDir.path}');
      expect(res.handled, isTrue);
      expect(res.message, contains('Inbox/ETL_'));
      final inboxNotes = await vault.listNotes(folder: 'Inbox');
      expect(inboxNotes.any((n) => n.relativePath.startsWith('Inbox/ETL_')), isTrue);
    });
  });
}
