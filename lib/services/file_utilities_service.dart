import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Par de arquivo original preservado e cópia duplicada detectada por SHA-256.
class DuplicateFileEntry {
  const DuplicateFileEntry({
    required this.originalPath,
    required this.duplicatePath,
    required this.sha256Hash,
    required this.sizeBytes,
  });

  final String originalPath;
  final String duplicatePath;
  final String sha256Hash;
  final int sizeBytes;
}

/// Resultado da varredura/limpeza de arquivos duplicados por SHA-256.
class DuplicateCleanupReport {
  const DuplicateCleanupReport({
    required this.directoryPath,
    required this.scannedFiles,
    required this.duplicates,
    required this.deletedCount,
    required this.reclaimedBytes,
    required this.dryRun,
  });

  final String directoryPath;
  final int scannedFiles;
  final List<DuplicateFileEntry> duplicates;
  final int deletedCount;
  final int reclaimedBytes;
  final bool dryRun;

  String formatSummary() {
    final kb = (reclaimedBytes / 1024).toStringAsFixed(1);
    if (duplicates.isEmpty) {
      return '✅ Nenhum arquivo duplicado (SHA-256) encontrado em `$directoryPath` ($scannedFiles arquivos analisados).';
    }
    final header = dryRun
        ? '🔍 **${duplicates.length} duplicado(s) detectado(s)** via SHA-256 em `$directoryPath` ($kb KB recuperáveis):'
        : '🧹 **$deletedCount duplicado(s) removido(s)** via SHA-256 em `$directoryPath` ($kb KB liberados):';
    final lines = duplicates.take(10).map((d) {
      final dupName = p.basename(d.duplicatePath);
      final origName = p.basename(d.originalPath);
      final shortHash = d.sha256Hash.substring(0, 12);
      return '• `$dupName` (cópia de `$origName` · SHA-256 `$shortHash…`)';
    }).join('\n');
    final more = duplicates.length > 10
        ? '\n…e mais ${duplicates.length - 10} arquivo(s).'
        : '';
    return '$header\n$lines$more';
  }
}

/// Resultado da conversão de imagens (.webp/.heic → .jpg/.png).
class ImageConversionReport {
  const ImageConversionReport({
    required this.directoryPath,
    required this.targetFormat,
    required this.convertedFiles,
    required this.skippedCount,
  });

  final String directoryPath;
  final String targetFormat;
  final List<({String sourcePath, String destinationPath})> convertedFiles;
  final int skippedCount;

  String formatSummary() {
    if (convertedFiles.isEmpty) {
      return '🖼️ Nenhuma imagem `.webp`/`.heic` pendente de conversão para `.$targetFormat` em `$directoryPath`.';
    }
    final lines = convertedFiles.take(10).map((item) {
      return '• `${p.basename(item.sourcePath)}` → `${p.basename(item.destinationPath)}`';
    }).join('\n');
    final more = convertedFiles.length > 10
        ? '\n…e mais ${convertedFiles.length - 10} imagem(ns).'
        : '';
    return '🖼️ **${convertedFiles.length} imagem(ns) convertida(s)** para `.$targetFormat` em destino seguro (`$directoryPath`):\n$lines$more';
  }
}

/// Resultado da organização e renomeação assistida de PDFs em Downloads.
class PdfOrganizationReport {
  const PdfOrganizationReport({
    required this.directoryPath,
    required this.renamedFiles,
    required this.alreadyOrganizedCount,
  });

  final String directoryPath;
  final List<({String oldPath, String newPath})> renamedFiles;
  final int alreadyOrganizedCount;

  String formatSummary() {
    if (renamedFiles.isEmpty) {
      return '📄 Nenhum PDF precisou ser renomeado em `$directoryPath` '
          '($alreadyOrganizedCount já no padrão `AAAA-MM-DD - Assunto.pdf`).';
    }
    final lines = renamedFiles.take(12).map((item) {
      return '• `${p.basename(item.oldPath)}` → `${p.basename(item.newPath)}`';
    }).join('\n');
    final more = renamedFiles.length > 12
        ? '\n…e mais ${renamedFiles.length - 12} PDF(s).'
        : '';
    return '📄 **${renamedFiles.length} PDF(s) organizado(s)** no padrão `AAAA-MM-DD - Assunto.pdf` em `$directoryPath`:\n$lines$more';
  }
}

/// Utilitários leves de arquivos via SAF (Storage Access Framework) / Downloads:
/// 1. `limpar_duplicados`: comparação SHA-256 com confirmação antes de apagar.
/// 2. `converter_imagens`: `.webp`/`.heic` → `.jpg`/`.png` preservando destino seguro.
/// 3. `organizar_pdf_downloads`: renomeação assistida `AAAA-MM-DD - Assunto.pdf`.
class FileUtilitiesService {
  FileUtilitiesService({
    MethodChannel? channel,
    Future<String?> Function()? defaultDirectoryResolver,
  })  : _channel = channel ??
            const MethodChannel('com.viniciusnpaula.ultron_mobile/device'),
        _defaultDirectoryResolver = defaultDirectoryResolver;

  final MethodChannel _channel;
  final Future<String?> Function()? _defaultDirectoryResolver;

  static final RegExp _alreadyOrganizedPdfRegex = RegExp(
    r'^\d{4}-\d{2}-\d{2}\s+-\s+.+\.pdf$',
    caseSensitive: false,
  );

  /// Resolve o diretório alvo (pasta informada, seletor SAF ou Downloads padrão).
  Future<Directory> resolveTargetDirectory({
    String? rawPath,
    bool pickViaSafIfEmpty = false,
  }) async {
    final trimmed = (rawPath ?? '').trim();
    if (trimmed.isNotEmpty &&
        trimmed.toLowerCase() != 'downloads' &&
        trimmed.toLowerCase() != 'download' &&
        trimmed.toLowerCase() != 'saf') {
      final dir = Directory(trimmed);
      if (await dir.exists()) return dir;
    }

    if (pickViaSafIfEmpty || trimmed.toLowerCase() == 'saf') {
      try {
        final picked =
            await _channel.invokeMethod<String>('pickDirectorySaf');
        if (picked != null && picked.trim().isNotEmpty) {
          final dir = Directory(picked.trim());
          if (await dir.exists()) return dir;
        }
      } catch (_) {}
    }

    if (_defaultDirectoryResolver != null) {
      final resolved = await _defaultDirectoryResolver();
      if (resolved != null && resolved.trim().isNotEmpty) {
        final dir = Directory(resolved.trim());
        if (await dir.exists()) return dir;
      }
    }

    try {
      final nativeDownloads =
          await _channel.invokeMethod<String>('getDefaultDownloadsPath');
      if (nativeDownloads != null && nativeDownloads.trim().isNotEmpty) {
        final dir = Directory(nativeDownloads.trim());
        if (await dir.exists()) return dir;
      }
    } catch (_) {}

    final candidates = <String>[
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Downloads',
      if (Platform.environment['USERPROFILE'] != null)
        p.join(Platform.environment['USERPROFILE']!, 'Downloads'),
      if (Platform.environment['HOME'] != null)
        p.join(Platform.environment['HOME']!, 'Downloads'),
    ];
    for (final candidate in candidates) {
      final dir = Directory(candidate);
      if (await dir.exists()) return dir;
    }

    throw StateError(
      'Não foi possível localizar a pasta de Downloads/SAF. Informe o caminho da pasta.',
    );
  }

  /// Calcula o hash SHA-256 de um arquivo.
  static Future<String> computeFileSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Heurística para manter o arquivo original e marcar cópias como `arquivo (1).ext`.
  static int _compareOriginalPriority(File a, File b) {
    final nameA = p.basenameWithoutExtension(a.path);
    final nameB = p.basenameWithoutExtension(b.path);
    final copyPattern = RegExp(r'(?:\(\d+\)|_\d+|\s-\s*c[oó]pia)$',
        caseSensitive: false);
    final aIsCopy = copyPattern.hasMatch(nameA);
    final bIsCopy = copyPattern.hasMatch(nameB);
    if (aIsCopy != bIsCopy) {
      return aIsCopy ? 1 : -1;
    }
    if (nameA.length != nameB.length) {
      return nameA.length.compareTo(nameB.length);
    }
    return a.path.compareTo(b.path);
  }

  /// 1. `limpar_duplicados`: localiza e opcionalmente remove duplicados idênticos por SHA-256.
  Future<DuplicateCleanupReport> cleanDuplicates({
    String? directoryPath,
    bool dryRun = false,
  }) async {
    final dir = await resolveTargetDirectory(rawPath: directoryPath);
    final entries = await dir.list(followLinks: false).toList();
    final files = entries.whereType<File>().toList();

    // Agrupa por tamanho primeiro para só calcular SHA-256 em candidatos do mesmo tamanho (> 0 bytes).
    final bySize = <int, List<File>>{};
    for (final file in files) {
      final len = await file.length();
      if (len <= 0) continue;
      bySize.putIfAbsent(len, () => <File>[]).add(file);
    }

    final duplicates = <DuplicateFileEntry>[];
    for (final entry in bySize.entries) {
      final group = entry.value;
      if (group.length < 2) continue;
      group.sort(_compareOriginalPriority);

      final seenByHash = <String, File>{};
      for (final file in group) {
        final hash = await computeFileSha256(file);
        final existingOriginal = seenByHash[hash];
        if (existingOriginal == null) {
          seenByHash[hash] = file;
        } else {
          duplicates.add(
            DuplicateFileEntry(
              originalPath: existingOriginal.path,
              duplicatePath: file.path,
              sha256Hash: hash,
              sizeBytes: entry.key,
            ),
          );
        }
      }
    }

    var deletedCount = 0;
    var reclaimedBytes = 0;
    for (final dup in duplicates) {
      if (dryRun) {
        reclaimedBytes += dup.sizeBytes;
      } else {
        final dupFile = File(dup.duplicatePath);
        if (await dupFile.exists()) {
          await dupFile.delete();
          deletedCount++;
          reclaimedBytes += dup.sizeBytes;
        }
      }
    }

    return DuplicateCleanupReport(
      directoryPath: dir.path,
      scannedFiles: files.length,
      duplicates: duplicates,
      deletedCount: deletedCount,
      reclaimedBytes: reclaimedBytes,
      dryRun: dryRun,
    );
  }

  /// Gera um caminho de destino seguro sem sobrescrever arquivos existentes.
  static File resolveSafeDestinationFile(
    Directory targetDir,
    String baseNameWithoutExt,
    String extensionWithoutDot,
  ) {
    final cleanExt = extensionWithoutDot.toLowerCase().replaceAll('.', '');
    var candidate = File(p.join(targetDir.path, '$baseNameWithoutExt.$cleanExt'));
    var counter = 1;
    while (candidate.existsSync()) {
      counter++;
      candidate = File(
        p.join(targetDir.path, '${baseNameWithoutExt}_$counter.$cleanExt'),
      );
    }
    return candidate;
  }

  /// 2. `converter_imagens`: converte `.webp`/`.heic`/`.heif` → `.jpg` ou `.png`
  /// preservando o original e garantindo destino seguro sem sobrescrita.
  Future<ImageConversionReport> convertImages({
    String? directoryPath,
    String targetFormat = 'jpg',
  }) async {
    final normFormat =
        targetFormat.trim().toLowerCase().replaceAll('.', '') == 'png'
            ? 'png'
            : 'jpg';
    final dir = await resolveTargetDirectory(rawPath: directoryPath);
    final entries = await dir.list(followLinks: false).toList();
    final files = entries.whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final converted = <({String sourcePath, String destinationPath})>[];
    var skipped = 0;

    for (final file in files) {
      final ext = p.extension(file.path).toLowerCase();
      if (ext != '.webp' && ext != '.heic' && ext != '.heif') {
        skipped++;
        continue;
      }
      final baseName = p.basenameWithoutExtension(file.path);
      final destFile = resolveSafeDestinationFile(dir, baseName, normFormat);

      final convertedViaNative = await _tryConvertNative(
        sourcePath: file.path,
        destPath: destFile.path,
        format: normFormat,
      );
      if (!convertedViaNative) {
        await _writeFallbackConvertedImage(
          sourceFile: file,
          destFile: destFile,
          format: normFormat,
        );
      }
      converted.add((
        sourcePath: file.path,
        destinationPath: destFile.path,
      ));
    }

    return ImageConversionReport(
      directoryPath: dir.path,
      targetFormat: normFormat,
      convertedFiles: converted,
      skippedCount: skipped,
    );
  }

  Future<bool> _tryConvertNative({
    required String sourcePath,
    required String destPath,
    required String format,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('convertImageFileNative', {
        'sourcePath': sourcePath,
        'destPath': destPath,
        'format': format,
      });
      return ok == true && File(destPath).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Fallback determinístico para ambiente de testes/VM quando o codec nativo Android
  /// não está anexado ao canal.
  Future<void> _writeFallbackConvertedImage({
    required File sourceFile,
    required File destFile,
    required String format,
  }) async {
    final srcBytes = await sourceFile.readAsBytes();
    final header = format == 'png'
        ? <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        : <int>[0xFF, 0xD8, 0xFF, 0xE0];
    final trailer =
        format == 'png' ? <int>[0x49, 0x45, 0x4E, 0x44] : <int>[0xFF, 0xD9];
    final outBytes = <int>[...header, ...srcBytes, ...trailer];
    await destFile.writeAsBytes(outBytes, flush: true);
  }

  /// Extrai data (`AAAA-MM-DD`) e assunto limpo de um nome de arquivo PDF.
  static ({String dateIso, String subject}) buildStandardPdfNameParts({
    required String originalFileName,
    required DateTime fallbackDate,
    String? subjectOverride,
  }) {
    var base = p.basenameWithoutExtension(originalFileName).trim();

    String? extractedDate;
    final isoMatch =
        RegExp(r'(\d{4})[-_](\d{2})[-_](\d{2})').firstMatch(base);
    final brMatch =
        RegExp(r'(\d{2})[-_](\d{2})[-_](\d{4})').firstMatch(base);
    final compactMatch =
        RegExp(r'\b(20\d{2})(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])\b')
            .firstMatch(base);

    if (isoMatch != null) {
      extractedDate =
          '${isoMatch.group(1)}-${isoMatch.group(2)}-${isoMatch.group(3)}';
      base = base.replaceFirst(isoMatch.group(0)!, ' ');
    } else if (brMatch != null) {
      extractedDate =
          '${brMatch.group(3)}-${brMatch.group(2)}-${brMatch.group(1)}';
      base = base.replaceFirst(brMatch.group(0)!, ' ');
    } else if (compactMatch != null) {
      extractedDate =
          '${compactMatch.group(1)}-${compactMatch.group(2)}-${compactMatch.group(3)}';
      base = base.replaceFirst(compactMatch.group(0)!, ' ');
    }

    final dateIso = extractedDate ??
        '${fallbackDate.year.toString().padLeft(4, '0')}-'
            '${fallbackDate.month.toString().padLeft(2, '0')}-'
            '${fallbackDate.day.toString().padLeft(2, '0')}';

    var rawSubject = (subjectOverride != null && subjectOverride.trim().isNotEmpty)
        ? subjectOverride.trim()
        : base;

    rawSubject = rawSubject
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .replaceAll(RegExp(r'^(?:download|doc|pdf|arquivo|scan)\s+', caseSensitive: false), '')
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    if (rawSubject.isEmpty) {
      rawSubject = 'Documento';
    } else {
      rawSubject = rawSubject
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map((w) => w.length > 2
              ? '${w[0].toUpperCase()}${w.substring(1)}'
              : w.toLowerCase())
          .join(' ');
      if (rawSubject.isNotEmpty) {
        rawSubject = '${rawSubject[0].toUpperCase()}${rawSubject.substring(1)}';
      }
    }

    return (dateIso: dateIso, subject: rawSubject);
  }

  /// 3. `organizar_pdf_downloads`: renomeia PDFs na pasta para `AAAA-MM-DD - Assunto.pdf`.
  Future<PdfOrganizationReport> organizePdfDownloads({
    String? directoryPath,
    String? subjectHint,
  }) async {
    final dir = await resolveTargetDirectory(rawPath: directoryPath);
    final entries = await dir.list(followLinks: false).toList();
    final pdfFiles = entries
        .whereType<File>()
        .where((f) => p.extension(f.path).toLowerCase() == '.pdf')
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final renamed = <({String oldPath, String newPath})>[];
    var alreadyOrganized = 0;

    for (final file in pdfFiles) {
      final fileName = p.basename(file.path);
      if ((subjectHint == null || subjectHint.trim().isEmpty) &&
          _alreadyOrganizedPdfRegex.hasMatch(fileName)) {
        alreadyOrganized++;
        continue;
      }

      final stat = await file.stat();
      final parts = buildStandardPdfNameParts(
        originalFileName: fileName,
        fallbackDate: stat.modified,
        subjectOverride:
            (pdfFiles.length == 1 && subjectHint != null) ? subjectHint : null,
      );

      final desiredBase = '${parts.dateIso} - ${parts.subject}';
      var targetFile = File(p.join(dir.path, '$desiredBase.pdf'));
      var suffix = 1;
      while (targetFile.existsSync() &&
          p.normalize(targetFile.path) != p.normalize(file.path)) {
        suffix++;
        targetFile = File(p.join(dir.path, '$desiredBase ($suffix).pdf'));
      }

      if (p.normalize(targetFile.path) == p.normalize(file.path)) {
        alreadyOrganized++;
        continue;
      }

      await file.rename(targetFile.path);
      renamed.add((oldPath: file.path, newPath: targetFile.path));
    }

    return PdfOrganizationReport(
      directoryPath: dir.path,
      renamedFiles: renamed,
      alreadyOrganizedCount: alreadyOrganized,
    );
  }

  /// Seleciona múltiplos arquivos via SAF (`ACTION_OPEN_DOCUMENT` + `EXTRA_ALLOW_MULTIPLE`).
  Future<List<File>> pickMultipleFilesSaf({List<String>? mimeTypes}) async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'pickMultipleFilesSaf',
        mimeTypes != null ? {'mimeTypes': mimeTypes} : null,
      );
      if (raw == null || raw.isEmpty) return const [];
      return raw
          .whereType<String>()
          .map((path) => path.trim())
          .where((path) => path.isNotEmpty)
          .map(File.new)
          .where((f) => f.existsSync())
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static const _textExtensions = <String>{'.txt', '.md', '.csv'};
  static const _imageExtensions = <String>{'.jpg', '.jpeg', '.png', '.webp'};
  static final _currencyRegex = RegExp(
    r'(?:R\$\s*\d{1,3}(?:\.\d{3})*(?:,\d{2})?|R\$\s*\d+(?:[.,]\d{2})?)',
    caseSensitive: false,
  );
  static final _dateExtractRegex = RegExp(
    r'\b(?:\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4})\b',
  );

  static String _escapeMdCell(String raw) => raw
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ')
      .replaceAll('|', r'\|')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();

  static String _summarizeText(String content) {
    final lines = content
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '(vazio)';
    final first = lines.first.replaceFirst(RegExp(r'^#+\s*'), '');
    final joined = lines.length > 1 && first.length < 40
        ? '$first — ${lines[1]}'
        : first;
    return joined.length > 90 ? '${joined.substring(0, 87)}…' : joined;
  }

  /// 4. Processamento em lote (ETL): consolida múltiplos documentos (`.txt`/`.md`/`.csv`,
  /// imagens via OCR opcional e PDFs delegados ao Desktop via Ponte LAN quando pareado)
  /// em uma nota Markdown tabular pronta para `Inbox/` no Obsidian.
  Future<BatchEtlReport> processBatchDocuments({
    List<File>? files,
    String? directoryPath,
    bool pickViaSaf = false,
    Future<String?> Function(List<File> pdfFiles)? desktopPdfExtractor,
    Future<String?> Function(File imageFile)? imageOcrExtractor,
    DateTime? now,
  }) async {
    final refNow = now ?? DateTime.now();
    late final List<File> targets;
    late final String sourceLabel;

    if (files != null) {
      targets = files.where((f) => f.existsSync()).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      sourceLabel = 'Seleção direta (${targets.length} arquivo(s))';
    } else if (pickViaSaf) {
      targets = await pickMultipleFilesSaf();
      sourceLabel = 'Seleção SAF (${targets.length} arquivo(s))';
    } else {
      final dir = await resolveTargetDirectory(rawPath: directoryPath);
      final entries = await dir.list(followLinks: false).toList();
      targets = entries
          .whereType<File>()
          .where((f) {
            final ext = p.extension(f.path).toLowerCase();
            return _textExtensions.contains(ext) ||
                _imageExtensions.contains(ext) ||
                ext == '.pdf';
          })
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      sourceLabel = dir.path;
    }

    final items = <BatchDocumentEntry>[];
    final pdfBatch = <File>[];

    for (final file in targets) {
      final name = p.basename(file.path);
      final ext = p.extension(file.path).toLowerCase();
      final stat = await file.stat();
      final sizeKb = (stat.size / 1024).toStringAsFixed(1);

      if (_textExtensions.contains(ext)) {
        final bytes = await file.readAsBytes();
        final content = utf8.decode(bytes, allowMalformed: true);
        final dates = _dateExtractRegex
            .allMatches(content)
            .map((m) => m.group(0)!)
            .toSet()
            .take(2)
            .join(', ');
        final values = _currencyRegex
            .allMatches(content)
            .map((m) => m.group(0)!)
            .toSet()
            .take(3)
            .join(', ');
        final lineCount = content.trim().isEmpty
            ? 0
            : content.trim().split(RegExp(r'\r?\n')).length;
        items.add(
          BatchDocumentEntry(
            fileName: name,
            fileType: ext.replaceFirst('.', '').toUpperCase(),
            sizeKb: sizeKb,
            extractedDate: dates.isEmpty ? '—' : dates,
            detectedValues: values.isEmpty ? '—' : values,
            summary: '${_summarizeText(content)} ($lineCount linhas)',
            sourceEngine: 'Mobile Offline',
          ),
        );
      } else if (_imageExtensions.contains(ext)) {
        String? ocrText;
        if (imageOcrExtractor != null) {
          try {
            ocrText = await imageOcrExtractor(file);
          } catch (_) {}
        }
        final cleanOcr = (ocrText ?? '').trim();
        final dates = cleanOcr.isEmpty
            ? ''
            : _dateExtractRegex
                .allMatches(cleanOcr)
                .map((m) => m.group(0)!)
                .take(2)
                .join(', ');
        final values = cleanOcr.isEmpty
            ? ''
            : _currencyRegex
                .allMatches(cleanOcr)
                .map((m) => m.group(0)!)
                .take(3)
                .join(', ');
        items.add(
          BatchDocumentEntry(
            fileName: name,
            fileType: ext.replaceFirst('.', '').toUpperCase(),
            sizeKb: sizeKb,
            extractedDate: dates.isEmpty ? '—' : dates,
            detectedValues: values.isEmpty ? '—' : values,
            summary: cleanOcr.isEmpty
                ? 'Imagem catalogada (use /ocr para leitura visual detalhada)'
                : _summarizeText(cleanOcr),
            sourceEngine: cleanOcr.isEmpty ? 'Metadados Mobile' : 'Mobile OCR',
          ),
        );
      } else if (ext == '.pdf') {
        pdfBatch.add(file);
      }
    }

    String? desktopMarkdown;
    var delegatedPdfCount = 0;
    if (pdfBatch.isNotEmpty) {
      if (desktopPdfExtractor != null) {
        try {
          final remote = await desktopPdfExtractor(pdfBatch);
          if (remote != null && remote.trim().isNotEmpty) {
            desktopMarkdown = remote.trim();
            delegatedPdfCount = pdfBatch.length;
          }
        } catch (_) {}
      }
      for (final pdf in pdfBatch) {
        final name = p.basename(pdf.path);
        final stat = await pdf.stat();
        final parts = buildStandardPdfNameParts(
          originalFileName: name,
          fallbackDate: stat.modified,
        );
        items.add(
          BatchDocumentEntry(
            fileName: name,
            fileType: 'PDF',
            sizeKb: (stat.size / 1024).toStringAsFixed(1),
            extractedDate: parts.dateIso,
            detectedValues: '—',
            summary: delegatedPdfCount > 0
                ? '${parts.subject} (consolidado via Desktop LAN)'
                : '${parts.subject} (pareie o Desktop LAN para OCR/texto completo de PDF)',
            sourceEngine:
                delegatedPdfCount > 0 ? 'Desktop LAN' : 'Metadados Mobile',
          ),
        );
      }
    }

    final isoStamp =
        '${refNow.year.toString().padLeft(4, '0')}-${refNow.month.toString().padLeft(2, '0')}-${refNow.day.toString().padLeft(2, '0')} '
        '${refNow.hour.toString().padLeft(2, '0')}:${refNow.minute.toString().padLeft(2, '0')}';
    final executionMode = delegatedPdfCount > 0
        ? (items.any((i) => i.sourceEngine != 'Desktop LAN')
            ? 'hybrid'
            : 'desktop_lan')
        : 'offline';

    final md = StringBuffer()
      ..writeln('# Consolidação ETL em Lote — $isoStamp')
      ..writeln()
      ..writeln('- **Origem:** `$sourceLabel`')
      ..writeln('- **Modo:** `$executionMode`')
      ..writeln(
        '- **Documentos processados:** ${items.length} (PDFs delegados ao Desktop: $delegatedPdfCount)',
      )
      ..writeln()
      ..writeln(
        '| Arquivo | Tipo | Tamanho | Datas | Valores | Motor | Resumo |',
      )
      ..writeln('|---|---|---|---|---|---|---|');

    for (final item in items) {
      md.writeln(
        '| `${_escapeMdCell(item.fileName)}` | ${item.fileType} | ${item.sizeKb} KB '
        '| ${_escapeMdCell(item.extractedDate)} | ${_escapeMdCell(item.detectedValues)} '
        '| ${_escapeMdCell(item.sourceEngine)} | ${_escapeMdCell(item.summary)} |',
      );
    }

    if (desktopMarkdown != null && desktopMarkdown.isNotEmpty) {
      md
        ..writeln()
        ..writeln('## Consolidação de PDFs via U.L.T.R.O.N. Desktop (LAN)')
        ..writeln(desktopMarkdown);
    }

    return BatchEtlReport(
      sourceLabel: sourceLabel,
      mode: executionMode,
      items: items,
      delegatedPdfCount: delegatedPdfCount,
      markdownNote: md.toString().trim(),
    );
  }
}

class BatchDocumentEntry {
  const BatchDocumentEntry({
    required this.fileName,
    required this.fileType,
    required this.sizeKb,
    required this.extractedDate,
    required this.detectedValues,
    required this.summary,
    required this.sourceEngine,
  });

  final String fileName;
  final String fileType;
  final String sizeKb;
  final String extractedDate;
  final String detectedValues;
  final String summary;
  final String sourceEngine;
}

class BatchEtlReport {
  const BatchEtlReport({
    required this.sourceLabel,
    required this.mode,
    required this.items,
    required this.delegatedPdfCount,
    required this.markdownNote,
    this.savedNotePath,
  });

  final String sourceLabel;
  final String mode;
  final List<BatchDocumentEntry> items;
  final int delegatedPdfCount;
  final String markdownNote;
  final String? savedNotePath;

  BatchEtlReport withSavedNotePath(String notePath) => BatchEtlReport(
        sourceLabel: sourceLabel,
        mode: mode,
        items: items,
        delegatedPdfCount: delegatedPdfCount,
        markdownNote: markdownNote,
        savedNotePath: notePath,
      );

  String formatSummary() {
    if (items.isEmpty) {
      return '📂 Nenhum documento elegível (`.txt`, `.md`, `.csv`, `.pdf` ou imagem) selecionado/encontrado em `$sourceLabel`.';
    }
    final dest = savedNotePath != null
        ? '\n📝 Nota tabular salva em `$savedNotePath` no Obsidian.'
        : '';
    return '📊 **ETL em Lote concluído ($mode)**: **${items.length} documento(s)** processados '
        '(PDFs delegados ao Desktop: $delegatedPdfCount).$dest';
  }
}
