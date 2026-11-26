import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'obsidian_service.dart';

class OpenGymSet {
  const OpenGymSet({
    required this.weightKg,
    required this.reps,
    this.rpe,
    this.completed = true,
  });

  final double weightKg;
  final int reps;
  final double? rpe;
  final bool completed;

  double get volume => weightKg * reps;

  /// Fórmula de Epley para estimativa de 1RM (até 15 repetições).
  double get estimated1Rm {
    if (weightKg <= 0 || reps <= 0) return 0;
    if (reps == 1) return weightKg;
    final cappedReps = reps.clamp(1, 15);
    return weightKg * (1.0 + cappedReps / 30.0);
  }
}

class OpenGymExerciseLog {
  const OpenGymExerciseLog({
    required this.name,
    required this.sets,
    this.muscleGroup = '',
  });

  final String name;
  final List<OpenGymSet> sets;
  final String muscleGroup;

  double get totalVolume =>
      sets.fold<double>(0, (acc, s) => acc + (s.completed ? s.volume : 0));

  double get maxWeight => sets.fold<double>(
        0,
        (best, s) => s.completed && s.weightKg > best ? s.weightKg : best,
      );
}

class OpenGymWorkout {
  const OpenGymWorkout({
    required this.name,
    required this.date,
    required this.exercises,
    this.durationMinutes = 0,
    this.notes = '',
  });

  final String name;
  final DateTime date;
  final List<OpenGymExerciseLog> exercises;
  final int durationMinutes;
  final String notes;

  double get totalVolume =>
      exercises.fold<double>(0, (acc, e) => acc + e.totalVolume);

  int get totalSets =>
      exercises.fold<int>(0, (acc, e) => acc + e.sets.where((s) => s.completed).length);
}

class OpenGymRoutine {
  const OpenGymRoutine({
    required this.name,
    required this.exercises,
  });

  final String name;
  final List<String> exercises;
}

class OpenGymPersonalRecord {
  const OpenGymPersonalRecord({
    required this.exerciseName,
    required this.maxWeightKg,
    required this.repsAtMax,
    required this.estimated1RmKg,
    required this.achievedOn,
  });

  final String exerciseName;
  final double maxWeightKg;
  final int repsAtMax;
  final double estimated1RmKg;
  final DateTime achievedOn;
}

class OpenGymWeightEntry {
  const OpenGymWeightEntry({
    required this.date,
    required this.weightKg,
  });

  final DateTime date;
  final double weightKg;
}

class OpenGymSummary {
  const OpenGymSummary({
    required this.sourceName,
    required this.workouts,
    required this.routines,
    required this.personalRecords,
    required this.weightEntries,
    this.savedNotePath,
    this.rawExtractedText = '',
  });

  final String sourceName;
  final List<OpenGymWorkout> workouts;
  final List<OpenGymRoutine> routines;
  final List<OpenGymPersonalRecord> personalRecords;
  final List<OpenGymWeightEntry> weightEntries;
  final String? savedNotePath;
  final String rawExtractedText;

  OpenGymSummary withSavedNotePath(String path) => OpenGymSummary(
        sourceName: sourceName,
        workouts: workouts,
        routines: routines,
        personalRecords: personalRecords,
        weightEntries: weightEntries,
        savedNotePath: path,
        rawExtractedText: rawExtractedText,
      );

  bool get isEmpty =>
      workouts.isEmpty &&
      routines.isEmpty &&
      weightEntries.isEmpty &&
      rawExtractedText.trim().isEmpty;

  String toObsidianMarkdown({DateTime? syncedAt}) {
    final now = syncedAt ?? DateTime.now();
    final sb = StringBuffer()
      ..writeln('# openGym - Resumo de Treinos (Offline)')
      ..writeln()
      ..writeln('- **Fonte:** `$sourceName`')
      ..writeln('- **Sincronizado em:** ${_fmtDate(now)}')
      ..writeln('- **Treinos registrados:** ${workouts.length}')
      ..writeln('- **Rotinas:** ${routines.length}')
      ..writeln('- **Registros de peso corporal:** ${weightEntries.length}');

    if (weightEntries.isNotEmpty) {
      final sortedW = [...weightEntries]..sort((a, b) => a.date.compareTo(b.date));
      final latest = sortedW.last;
      final first = sortedW.first;
      final delta = latest.weightKg - first.weightKg;
      final deltaStr = delta == 0
          ? '0.0 kg'
          : '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)} kg';
      sb
        ..writeln()
        ..writeln('## Peso Corporal')
        ..writeln('- **Atual:** ${latest.weightKg.toStringAsFixed(1)} kg (${_fmtDate(latest.date)})')
        ..writeln('- **Variação no período:** $deltaStr (desde ${_fmtDate(first.date)})');
    }

    if (personalRecords.isNotEmpty) {
      sb
        ..writeln()
        ..writeln('## Recordes Pessoais (PRs)');
      for (final pr in personalRecords.take(20)) {
        sb.writeln(
          '- **${pr.exerciseName}:** ${pr.maxWeightKg.toStringAsFixed(1)} kg x ${pr.repsAtMax} '
          '(1RM est.: ${pr.estimated1RmKg.toStringAsFixed(1)} kg · ${_fmtDate(pr.achievedOn)})',
        );
      }
    }

    if (routines.isNotEmpty) {
      sb
        ..writeln()
        ..writeln('## Rotinas Cadastradas');
      for (final r in routines.take(12)) {
        final exList = r.exercises.isEmpty ? 'sem exercícios listados' : r.exercises.join(', ');
        sb.writeln('- **${r.name}:** $exList');
      }
    }

    if (workouts.isNotEmpty) {
      final sorted = [...workouts]..sort((a, b) => b.date.compareTo(a.date));
      sb
        ..writeln()
        ..writeln('## Últimos Treinos');
      for (final w in sorted.take(10)) {
        final dur = w.durationMinutes > 0 ? ' · ${w.durationMinutes} min' : '';
        sb.writeln(
          '### ${_fmtDate(w.date)} - ${w.name} (${w.totalSets} séries · ${w.totalVolume.toStringAsFixed(0)} kg vol.$dur)',
        );
        for (final ex in w.exercises) {
          final setsStr = ex.sets
              .where((s) => s.completed)
              .map((s) => '${_fmtKg(s.weightKg)}kgx${s.reps}')
              .join(', ');
          sb.writeln('- **${ex.name}:** ${setsStr.isEmpty ? 'sem séries' : setsStr}');
        }
        if (w.notes.isNotEmpty) {
          sb.writeln('  - Nota: ${w.notes}');
        }
      }
    }

    if (rawExtractedText.trim().isNotEmpty) {
      final clipped = rawExtractedText.trim().length > 6000
          ? '${rawExtractedText.trim().substring(0, 5997)}...'
          : rawExtractedText.trim();
      sb
        ..writeln()
        ..writeln('## Relatório Extraído (PDF)')
        ..writeln(clipped);
    }

    return sb.toString().trim();
  }

  String formatChatSummary() {
    if (isEmpty) {
      return 'Nenhum treino, rotina ou texto legível foi encontrado em "$sourceName". '
          'Se o PDF foi gerado como imagem (scan), exporte também o backup JSON/CSV no openGym e importe novamente.';
    }
    final sb = StringBuffer()
      ..writeln('openGym sincronizado ($sourceName):');
    if (workouts.isNotEmpty || routines.isNotEmpty || weightEntries.isNotEmpty) {
      sb.writeln(
        '• Treinos: ${workouts.length} · Rotinas: ${routines.length} · Pesagens: ${weightEntries.length}',
      );
    }

    if (weightEntries.isNotEmpty) {
      final sortedW = [...weightEntries]..sort((a, b) => a.date.compareTo(b.date));
      final latest = sortedW.last;
      sb.writeln('• Peso atual: ${latest.weightKg.toStringAsFixed(1)} kg (${_fmtDate(latest.date)})');
    }

    if (routines.isNotEmpty) {
      sb.writeln('• Rotinas identificadas:');
      for (final r in routines.take(6)) {
        final preview = r.exercises.isEmpty
            ? 'sem exercícios listados'
            : r.exercises.take(5).join(', ') +
                (r.exercises.length > 5 ? ' (+${r.exercises.length - 5})' : '');
        sb.writeln('  - ${r.name}: $preview');
      }
    }

    if (workouts.isNotEmpty) {
      final sorted = [...workouts]..sort((a, b) => b.date.compareTo(a.date));
      final last = sorted.first;
      sb.writeln(
        '• Último treino: ${last.name} em ${_fmtDate(last.date)} '
        '(${last.exercises.length} exercícios, ${last.totalSets} séries, ${last.totalVolume.toStringAsFixed(0)} kg de volume)',
      );
    }

    if (personalRecords.isNotEmpty) {
      sb.writeln('• Top PRs:');
      for (final pr in personalRecords.take(5)) {
        sb.writeln(
          '  - ${pr.exerciseName}: ${_fmtKg(pr.maxWeightKg)} kg x ${pr.repsAtMax} (1RM ~${pr.estimated1RmKg.toStringAsFixed(1)} kg)',
        );
      }
    }

    if (workouts.isEmpty &&
        routines.isEmpty &&
        weightEntries.isEmpty &&
        rawExtractedText.trim().isNotEmpty) {
      final lines = const LineSplitter()
          .convert(rawExtractedText)
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .take(8)
          .toList();
      sb.writeln('• Texto extraído do PDF:');
      for (final l in lines) {
        sb.writeln('  $l');
      }
    }

    if (savedNotePath != null) {
      sb.writeln('• Memória do Modo Treino atualizada em `$savedNotePath`.');
    }
    return sb.toString().trim();
  }

  String get speakText {
    if (isEmpty) {
      return 'Não encontrei registros de treino legíveis nesse arquivo do OpenGym.';
    }
    if (workouts.isNotEmpty) {
      final parts = <String>[
        'OpenGym sincronizado com ${workouts.length} treinos',
      ];
      if (personalRecords.isNotEmpty) {
        final top = personalRecords.first;
        parts.add(
          'maior carga registrada em ${top.exerciseName} com ${_fmtKg(top.maxWeightKg)} quilos',
        );
      }
      if (weightEntries.isNotEmpty) {
        final sortedW = [...weightEntries]
          ..sort((a, b) => a.date.compareTo(b.date));
        parts.add(
          'peso corporal atual em ${sortedW.last.weightKg.toStringAsFixed(1)} quilos',
        );
      }
      return '${parts.join(', ')}.';
    }
    if (routines.isNotEmpty) {
      final exTotal =
          routines.fold<int>(0, (acc, r) => acc + r.exercises.length);
      return 'OpenGym sincronizado com ${routines.length} rotinas e $exTotal exercícios salvos no Modo Treino.';
    }
    if (weightEntries.isNotEmpty) {
      final sortedW = [...weightEntries]..sort((a, b) => a.date.compareTo(b.date));
      return 'OpenGym sincronizado com peso corporal atual em ${sortedW.last.weightKg.toStringAsFixed(1)} quilos.';
    }
    return 'Relatório do OpenGym lido e salvo na memória do Modo Treino.';
  }

  static String _fmtDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$d/$m/$y';
  }

  static String _fmtKg(double kg) =>
      kg == kg.roundToDouble() ? kg.toInt().toString() : kg.toStringAsFixed(1);
}

/// Serviço offline de integração com o app Android `openGym` (`ch.duartesantos.opengym`).
/// Lê backups JSON (`opengym-state.json`) e exportações CSV via SAF ou Downloads,
/// consolida PRs/volume/rotinas/peso corporal e grava em `Memoria/Treino/OpenGym_Resumo.md`
/// no Obsidian para alimentar o RAG do Modo Treino.
class OpenGymService {
  OpenGymService({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('com.viniciusnpaula.ultron_mobile/device');

  static const String androidPackage = 'ch.duartesantos.opengym';
  static const String summaryNotePath = 'Memoria/Treino/OpenGym_Resumo.md';

  final MethodChannel _channel;

  /// Abre o seletor SAF nativo para escolher o relatório `.pdf` ou backup `.json`/`.csv` do openGym.
  Future<File?> pickBackupFileSaf() async {
    try {
      final raw = await _channel.invokeListMethod<String>(
        'pickMultipleFilesSaf',
        <String, Object?>{
          'mimeTypes': const <String>[
            'application/pdf',
            'application/json',
            'text/csv',
            'text/comma-separated-values',
            'text/plain',
            'application/octet-stream',
          ],
        },
      );
      if (raw == null || raw.isEmpty) return null;
      final file = File(raw.first);
      if (await file.exists()) return file;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Procura automaticamente o relatório PDF ou backup mais recente do openGym em Downloads / Documents.
  Future<File?> findLatestLocalBackup({List<Directory>? extraDirs}) async {
    final dirs = <Directory>[
      ...?extraDirs,
      Directory('/storage/emulated/0/Download'),
      Directory('/storage/emulated/0/Documents'),
      Directory('/storage/emulated/0/openGym'),
    ];
    final candidates = <File>[];
    for (final dir in dirs) {
      try {
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is! File) continue;
          final name = p.basename(entity.path).toLowerCase();
          final isSupported = name.endsWith('.pdf') ||
              name.endsWith('.json') ||
              name.endsWith('.csv');
          if (isSupported &&
              (name.contains('opengym') ||
                  name.contains('open_gym') ||
                  name.contains('open-gym') ||
                  name.contains('workout') ||
                  name.contains('treino'))) {
            candidates.add(entity);
          }
        }
      } catch (_) {}
    }
    if (candidates.isEmpty) return null;
    candidates.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    return candidates.first;
  }

  /// Importa um arquivo PDF, JSON ou CSV do openGym e grava o resumo consolidado
  /// em `Memoria/Treino/OpenGym_Resumo.md` no cofre Obsidian.
  Future<OpenGymSummary> importFile(
    File file, {
    required ObsidianService obsidian,
    DateTime? now,
  }) async {
    final name = p.basename(file.path);
    final bytes = await file.readAsBytes();
    final isPdfHeader = bytes.length >= 4 &&
        bytes[0] == 0x25 && // %
        bytes[1] == 0x50 && // P
        bytes[2] == 0x44 && // D
        bytes[3] == 0x46; // F

    final OpenGymSummary summary;
    if (name.toLowerCase().endsWith('.pdf') || isPdfHeader) {
      String nativeText = '';
      try {
        final rawNative = await _channel.invokeMethod<String>(
          'extractPdfTextNative',
          <String, Object?>{'path': file.path},
        );
        if (rawNative != null && rawNative.trim().isNotEmpty) {
          nativeText = rawNative.trim();
        }
      } catch (_) {}
      summary = nativeText.isNotEmpty
          ? parsePdfReportText(nativeText, sourceName: name)
          : parsePdfExport(bytes, sourceName: name);
    } else {
      final raw = utf8.decode(bytes, allowMalformed: true);
      final trimmed = raw.trimLeft();
      summary = (name.toLowerCase().endsWith('.json') ||
              trimmed.startsWith('{') ||
              trimmed.startsWith('['))
          ? parseJsonExport(raw, sourceName: name)
          : parseCsvExport(raw, sourceName: name);
    }

    if (!summary.isEmpty) {
      await obsidian.initialize();
      final noteFile = File(p.join(obsidian.root.path, summaryNotePath));
      await noteFile.parent.create(recursive: true);
      await noteFile.writeAsString(summary.toObsidianMarkdown(syncedAt: now));
      return summary.withSavedNotePath(summaryNotePath);
    }
    return summary;
  }

  /// Faz extração offline de texto de PDFs (streams FlateDecode/raw + ToUnicode CMap)
  /// e interpreta exercícios, séries, cargas, datas e peso corporal de relatórios do openGym.
  static OpenGymSummary parsePdfExport(
    Uint8List bytes, {
    String sourceName = 'opengym-report.pdf',
  }) {
    final extracted = extractTextFromPdfBytes(bytes);
    return parsePdfReportText(extracted, sourceName: sourceName);
  }

  /// Extrai texto legível de um PDF 100% offline em Dart (suporta FlateDecode,
  /// operadores Tj/TJ, strings literais, hex UTF-16BE e mapas ToUnicode CMap do Skia/Android).
  static String extractTextFromPdfBytes(Uint8List bytes) {
    final latin = latin1.decode(bytes, allowInvalid: true);
    final decodedStreams = <String>[];
    final cmap = <int, String>{};

    final streamRegex = RegExp(r'stream\r?\n([\s\S]*?)\r?\n?endstream');
    for (final m in streamRegex.allMatches(latin)) {
      final rawStream = m.group(1);
      if (rawStream == null || rawStream.isEmpty) continue;
      final streamBytes = latin1.encode(rawStream);
      String? text;
      try {
        final inflated = zlib.decode(streamBytes);
        text = latin1.decode(inflated, allowInvalid: true);
      } catch (_) {
        // Alguns geradores deixam CR/LF extra antes de endstream
        final trimmedStream = rawStream.replaceFirst(RegExp(r'\r?\n$'), '');
        if (trimmedStream.length != rawStream.length) {
          try {
            final inflated = zlib.decode(latin1.encode(trimmedStream));
            text = latin1.decode(inflated, allowInvalid: true);
          } catch (_) {
            text = rawStream;
          }
        } else {
          text = rawStream;
        }
      }
      if (text.contains('begincmap') ||
          text.contains('beginbfchar') ||
          text.contains('beginbfrange')) {
        _parseToUnicodeCMap(text, cmap);
      }
      if (text.contains('BT') &&
          (text.contains('Tj') ||
              text.contains('TJ') ||
              text.contains("'") ||
              text.contains('"'))) {
        decodedStreams.add(text);
      }
    }

    // Fallback para PDFs sem stream comprimido explícito
    if (decodedStreams.isEmpty &&
        latin.contains('BT') &&
        (latin.contains('Tj') ||
            latin.contains('TJ') ||
            latin.contains("'") ||
            latin.contains('"'))) {
      decodedStreams.add(latin);
    }

    final out = StringBuffer();
    for (final content in decodedStreams) {
      final btBlocks = RegExp(r'BT([\s\S]*?)ET').allMatches(content);
      for (final block in btBlocks) {
        final body = block.group(1) ?? '';
        final lineBuf = StringBuffer();
        final opRegex = RegExp(
          r'\[([\s\S]*?)\]\s*TJ|\(([^()\\]*(?:\\.[^()\\]*)*)\)\s*(?:Tj|[\x27\x22])|<([0-9A-Fa-f\s]+)>\s*Tj|(?:T\*|\b(?:Td|TD|Tm)\b)',
        );
        for (final op in opRegex.allMatches(body)) {
          final tjArray = op.group(1);
          final litStr = op.group(2);
          final hexStr = op.group(3);
          if (tjArray != null) {
            final itemRegex = RegExp(
              r'\(([^()\\]*(?:\\.[^()\\]*)*)\)|<([0-9A-Fa-f\s]+)>|(-?\d+(?:\.\d+)?)',
            );
            for (final item in itemRegex.allMatches(tjArray)) {
              final s = item.group(1);
              final h = item.group(2);
              final numKern = item.group(3);
              if (s != null) {
                lineBuf.write(_decodePdfLiteral(s, cmap));
              } else if (h != null) {
                lineBuf.write(_decodePdfHex(h, cmap));
              } else if (numKern != null) {
                final k = double.tryParse(numKern) ?? 0;
                if (k < -180 && !lineBuf.toString().endsWith(' ')) {
                  lineBuf.write(' ');
                }
              }
            }
          } else if (litStr != null) {
            lineBuf.write(_decodePdfLiteral(litStr, cmap));
          } else if (hexStr != null) {
            lineBuf.write(_decodePdfHex(hexStr, cmap));
          } else {
            // Operador de posicionamento (Td/TD/T*/Tm): separa linhas
            final cur = lineBuf.toString().trim();
            if (cur.isNotEmpty) {
              out.writeln(cur);
              lineBuf.clear();
            }
          }
        }
        final tail = lineBuf.toString().trim();
        if (tail.isNotEmpty) out.writeln(tail);
      }
    }

    return out
        .toString()
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
  }

  static void _parseToUnicodeCMap(String cmapText, Map<int, String> out) {
    final bfCharBlocks =
        RegExp(r'beginbfchar([\s\S]*?)endbfchar').allMatches(cmapText);
    for (final block in bfCharBlocks) {
      final pairs = RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')
          .allMatches(block.group(1) ?? '');
      for (final p in pairs) {
        final code = int.tryParse(p.group(1)!, radix: 16);
        final mapped = _hexToUnicodeString(p.group(2)!);
        if (code != null && mapped.isNotEmpty) {
          out[code] = mapped;
        }
      }
    }

    final bfRangeBlocks =
        RegExp(r'beginbfrange([\s\S]*?)endbfrange').allMatches(cmapText);
    for (final block in bfRangeBlocks) {
      final body = block.group(1) ?? '';
      // Formato array: <start> <end> [<u1> <u2> ...]
      final arrayRanges =
          RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*\[([\s\S]*?)\]')
              .allMatches(body);
      for (final r in arrayRanges) {
        final start = int.tryParse(r.group(1)!, radix: 16);
        final end = int.tryParse(r.group(2)!, radix: 16);
        if (start == null || end == null) continue;
        final targets = RegExp(r'<([0-9A-Fa-f]+)>')
            .allMatches(r.group(3) ?? '')
            .map((m) => _hexToUnicodeString(m.group(1)!))
            .toList();
        final limit = (end - start + 1).clamp(0, targets.length);
        for (var i = 0; i < limit; i++) {
          if (targets[i].isNotEmpty) {
            out[start + i] = targets[i];
          }
        }
      }

      // Formato sequencial: <start> <end> <dstStart>
      final ranges =
          RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')
              .allMatches(body);
      for (final r in ranges) {
        final start = int.tryParse(r.group(1)!, radix: 16);
        final end = int.tryParse(r.group(2)!, radix: 16);
        final dstStart = int.tryParse(r.group(3)!, radix: 16);
        if (start == null || end == null || dstStart == null) continue;
        final count = (end - start).clamp(0, 512);
        for (var i = 0; i <= count; i++) {
          out[start + i] = String.fromCharCode(dstStart + i);
        }
      }
    }
  }

  static String _decodePdfLiteral(String rawLit, Map<int, String> cmap) {
    final decoded = _unescapePdfLiteral(rawLit);
    if (decoded.length >= 2 && decoded.codeUnits.every((c) => c <= 0xFF)) {
      if (decoded.codeUnitAt(0) == 0xFE && decoded.codeUnitAt(1) == 0xFF) {
        final buf = StringBuffer();
        for (var i = 2; i + 1 < decoded.length; i += 2) {
          buf.writeCharCode(
            (decoded.codeUnitAt(i) << 8) | decoded.codeUnitAt(i + 1),
          );
        }
        return buf.toString();
      }
      if (cmap.isNotEmpty && decoded.length.isEven) {
        final buf = StringBuffer();
        var hits = 0;
        for (var i = 0; i + 1 < decoded.length; i += 2) {
          final code =
              (decoded.codeUnitAt(i) << 8) | decoded.codeUnitAt(i + 1);
          final mapped = cmap[code];
          if (mapped != null) {
            buf.write(mapped);
            hits++;
          } else if (code >= 32 && code <= 126) {
            buf.writeCharCode(code);
          }
        }
        if (hits > 0 && hits * 2 >= decoded.length ~/ 2) {
          return buf.toString();
        }
      }
    }
    return decoded;
  }

  static String _hexToUnicodeString(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s+'), '');
    if (clean.isEmpty) return '';
    if (clean.length <= 4) {
      final cp = int.tryParse(clean, radix: 16);
      return cp == null ? '' : String.fromCharCode(cp);
    }
    final buf = StringBuffer();
    for (var i = 0; i + 4 <= clean.length; i += 4) {
      final cp = int.tryParse(clean.substring(i, i + 4), radix: 16);
      if (cp != null && cp != 0xFEFF) buf.writeCharCode(cp);
    }
    return buf.toString();
  }

  static String _decodePdfHex(String rawHex, Map<int, String> cmap) {
    final hex = rawHex.replaceAll(RegExp(r'\s+'), '');
    if (hex.isEmpty) return '';
    if (hex.toUpperCase().startsWith('FEFF')) {
      return _hexToUnicodeString(hex.substring(4));
    }
    if (cmap.isNotEmpty && hex.length % 4 == 0) {
      final buf = StringBuffer();
      var hits = 0;
      for (var i = 0; i + 4 <= hex.length; i += 4) {
        final code = int.tryParse(hex.substring(i, i + 4), radix: 16);
        if (code != null && cmap.containsKey(code)) {
          buf.write(cmap[code]);
          hits++;
        } else if (code != null && code >= 32 && code <= 126) {
          buf.writeCharCode(code);
        }
      }
      if (hits > 0) return buf.toString();
    }
    final buf = StringBuffer();
    for (var i = 0; i + 2 <= hex.length; i += 2) {
      final b = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (b != null && (b >= 32 || b == 10 || b == 13 || b == 9)) {
        buf.writeCharCode(b);
      }
    }
    return buf.toString();
  }

  static String _unescapePdfLiteral(String s) {
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (ch == r'\' && i + 1 < s.length) {
        final next = s[++i];
        switch (next) {
          case 'n':
            buf.write('\n');
          case 'r':
            buf.write('\r');
          case 't':
            buf.write('\t');
          case '(':
          case ')':
          case r'\':
            buf.write(next);
          default:
            if (next.codeUnitAt(0) >= 48 && next.codeUnitAt(0) <= 55) {
              var oct = next;
              for (var k = 0; k < 2 && i + 1 < s.length; k++) {
                final c = s[i + 1].codeUnitAt(0);
                if (c >= 48 && c <= 55) {
                  oct += s[++i];
                } else {
                  break;
                }
              }
              final code = int.tryParse(oct, radix: 8);
              if (code != null) buf.writeCharCode(code);
            } else {
              buf.write(next);
            }
        }
      } else {
        buf.write(ch);
      }
    }
    return buf.toString();
  }

  /// Interpreta o texto extraído de um relatório ou plano semanal PDF do openGym
  /// em treinos, séries, PRs, rotinas semanais e registros de peso corporal.
  static OpenGymSummary parsePdfReportText(
    String rawText, {
    String sourceName = 'opengym-report.pdf',
  }) {
    final lines = const LineSplitter()
        .convert(rawText)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final workouts = <OpenGymWorkout>[];
    final routines = <OpenGymRoutine>[];
    final weights = <OpenGymWeightEntry>[];

    var currentDate = DateTime.now();
    var currentWorkoutName = 'Relatório openGym';
    final currentExercises = <String, List<OpenGymSet>>{};
    String? activeRoutineName;
    final activeRoutineExercises = <String>[];
    String? lastExerciseName;

    void flushWorkout() {
      if (currentExercises.isEmpty) return;
      final logs = currentExercises.entries
          .map((e) => OpenGymExerciseLog(name: e.key, sets: e.value))
          .toList();
      workouts.add(
        OpenGymWorkout(
          name: currentWorkoutName,
          date: currentDate,
          exercises: logs,
        ),
      );
      currentExercises.clear();
      lastExerciseName = null;
    }

    void flushRoutine() {
      if (activeRoutineName != null && activeRoutineExercises.isNotEmpty) {
        routines.add(
          OpenGymRoutine(
            name: activeRoutineName!,
            exercises: List<String>.from(activeRoutineExercises),
          ),
        );
      }
      activeRoutineName = null;
      activeRoutineExercises.clear();
    }

    void recordRoutineExercise(String name) {
      if (activeRoutineName == null) return;
      final clean = name.trim();
      if (clean.length < 3) return;
      if (!activeRoutineExercises.contains(clean)) {
        activeRoutineExercises.add(clean);
      }
    }

    final dateLineRegex = RegExp(
      r'\b(\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}/\d{4})\b',
    );
    final routineHeaderRegex = RegExp(
      r'^(?:treino\s+[a-z0-9]+(?:\s*[-–:|·].*)?|treino\s+de\s+.+|rotina\s*[:\-–]?\s*.+|workout\s+[a-z0-9]+(?:\s*[-–:|·].*)?|dia\s+\d+(?:\s*[-–:|·].*)?|day\s+\d+(?:\s*[-–:|·].*)?|(?:segunda|ter[çc]a|quarta|quinta|sexta|s[áa]bado|domingo)(?:-feira)?(?:\s*[-–:|·].*)?|(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)(?:\s*[-–:|·].*)?|(?:push|pull|legs|upper|lower|full\s*body)(?:\s+[a-z0-9]|\s*[-–:|·].*)?)$',
      caseSensitive: false,
    );
    final bodyWeightRegex = RegExp(
      r'(?:body\s*weight|peso\s*(?:corporal)?)\s*[:\-]?\s*(\d{2,3}(?:[.,]\d{1,2})?)\s*(?:kg|lbs?)',
      caseSensitive: false,
    );
    // Ex: "Supino Reto 80 kg x 10" ou "80kg x 10"
    final weightRepsRegex = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(?:kg|lbs?)\s*[x×]\s*(\d{1,3})\b',
      caseSensitive: false,
    );
    // Ex: "10 reps @ 80 kg" / "80 kg · 10 reps" / "80 kg (10)"
    final altWeightRepsRegex = RegExp(
      r'(?:(\d{1,3})\s*(?:reps?|repeti[çc][õo]es)\s*(?:@|a|com)\s*(\d+(?:[.,]\d+)?)\s*(?:kg|lbs?)|(\d+(?:[.,]\d+)?)\s*(?:kg|lbs?)\s*(?:[·•|/\-]|\()\s*(\d{1,3})\s*(?:reps?)?\)?)',
      caseSensitive: false,
    );
    // Ex: "4 x 10 @ 80 kg" ou "4 x 8-12 - 80 kg"
    final setsRepsAtWeightRegex = RegExp(
      r'(\d{1,2})\s*[x×]\s*(\d{1,3})(?:\s*[-–]\s*\d{1,3})?(?:\s*(?:reps?)?)?\s*(?:@|com|[-–·|])\s*(\d+(?:[.,]\d+)?)\s*(?:kg|lbs?)',
      caseSensitive: false,
    );
    // Ex: "3 x 8-12", "4x10", "3 séries de 10", "3 sets x 10-12 reps"
    final setsRepsOnlyRegex = RegExp(
      r'\b(\d{1,2})\s*(?:sets?|s[eé]ries?)?\s*(?:[x×]|de)\s*(\d{1,3})(?:\s*[-–]\s*\d{1,3})?\s*(?:reps?|repeti[çc][õo]es)?\b',
      caseSensitive: false,
    );

    for (final line in lines) {
      final bw = bodyWeightRegex.firstMatch(line);
      if (bw != null) {
        final kg = _toDouble(bw.group(1));
        if (kg > 20 && kg < 300) {
          weights.add(OpenGymWeightEntry(date: currentDate, weightKg: kg));
        }
        continue;
      }

      final dateMatch = dateLineRegex.firstMatch(line);
      if (dateMatch != null) {
        final parsed = _parseDate(dateMatch.group(1));
        if (parsed != null) {
          if (currentExercises.isNotEmpty) flushWorkout();
          currentDate = parsed;
          final rest = line
              .replaceFirst(dateMatch.group(0)!, '')
              .replaceAll(RegExp(r'^[\s\-–:|·]+|[\s\-–:|·]+$'), '')
              .trim();
          if (rest.length >= 3 && rest.length <= 60) {
            currentWorkoutName = rest;
          }
          continue;
        }
      }

      // Cabeçalho de rotina/split semanal (sem séries/cargas na própria linha)
      if (!weightRepsRegex.hasMatch(line) &&
          !setsRepsOnlyRegex.hasMatch(line) &&
          !altWeightRepsRegex.hasMatch(line) &&
          line.length <= 70 &&
          routineHeaderRegex.hasMatch(line)) {
        flushRoutine();
        activeRoutineName = line;
        currentWorkoutName = line;
        lastExerciseName = null;
        continue;
      }

      final mSetsAt = setsRepsAtWeightRegex.firstMatch(line);
      if (mSetsAt != null) {
        final setCount = int.tryParse(mSetsAt.group(1)!)?.clamp(1, 20) ?? 1;
        final reps = int.tryParse(mSetsAt.group(2)!) ?? 0;
        final kg = _toDouble(mSetsAt.group(3));
        final prefix = line
            .substring(0, mSetsAt.start)
            .replaceAll(RegExp(r'[\s:\-–•|·]+$'), '')
            .trim();
        final exName = prefix.length >= 3 ? prefix : (lastExerciseName ?? 'Exercício');
        lastExerciseName = exName;
        recordRoutineExercise(exName);
        final list = currentExercises.putIfAbsent(exName, () => <OpenGymSet>[]);
        for (var i = 0; i < setCount; i++) {
          list.add(OpenGymSet(weightKg: kg, reps: reps));
        }
        continue;
      }

      final mWeightReps = weightRepsRegex.allMatches(line).toList();
      if (mWeightReps.isNotEmpty) {
        final prefix = line
            .substring(0, mWeightReps.first.start)
            .replaceAll(
              RegExp(r'(?:set\s*\d+|s[eé]rie\s*\d+|[\s:\-–•|·])+$', caseSensitive: false),
              '',
            )
            .trim();
        final exName = prefix.length >= 3 ? prefix : (lastExerciseName ?? 'Exercício');
        lastExerciseName = exName;
        recordRoutineExercise(exName);
        final list = currentExercises.putIfAbsent(exName, () => <OpenGymSet>[]);
        for (final m in mWeightReps) {
          final kg = _toDouble(m.group(1));
          final reps = int.tryParse(m.group(2)!) ?? 0;
          if (kg > 0 || reps > 0) {
            list.add(OpenGymSet(weightKg: kg, reps: reps));
          }
        }
        continue;
      }

      final mAlt = altWeightRepsRegex.allMatches(line).toList();
      if (mAlt.isNotEmpty) {
        final prefix = line
            .substring(0, mAlt.first.start)
            .replaceAll(RegExp(r'[\s:\-–•|·]+$'), '')
            .trim();
        final exName = prefix.length >= 3 ? prefix : (lastExerciseName ?? 'Exercício');
        lastExerciseName = exName;
        recordRoutineExercise(exName);
        final list = currentExercises.putIfAbsent(exName, () => <OpenGymSet>[]);
        for (final m in mAlt) {
          final kg = m.group(2) != null ? _toDouble(m.group(2)) : _toDouble(m.group(3));
          final reps = m.group(1) != null
              ? (int.tryParse(m.group(1)!) ?? 0)
              : (int.tryParse(m.group(4)!) ?? 0);
          if (kg > 0 || reps > 0) {
            list.add(OpenGymSet(weightKg: kg, reps: reps));
          }
        }
        continue;
      }

      final mSetsOnly = setsRepsOnlyRegex.firstMatch(line);
      if (mSetsOnly != null) {
        final setCount = int.tryParse(mSetsOnly.group(1)!)?.clamp(1, 20) ?? 1;
        final reps = int.tryParse(mSetsOnly.group(2)!) ?? 0;
        final prefix = line
            .substring(0, mSetsOnly.start)
            .replaceAll(RegExp(r'[\s:\-–•|·]+$'), '')
            .trim();
        final exName = prefix.length >= 3 ? prefix : (lastExerciseName ?? '');
        if (exName.length >= 3) {
          lastExerciseName = exName;
          recordRoutineExercise(exName);
          final list = currentExercises.putIfAbsent(exName, () => <OpenGymSet>[]);
          for (var i = 0; i < setCount; i++) {
            list.add(OpenGymSet(weightKg: 0, reps: reps));
          }
          continue;
        }
      }

      // Possível nome de exercício em linha isolada (sem números puros ou rodapé)
      if (line.length >= 3 &&
          line.length <= 56 &&
          !RegExp(r'^\d+$').hasMatch(line) &&
          !line.toLowerCase().startsWith('opengym') &&
          !line.toLowerCase().startsWith('page ') &&
          !line.toLowerCase().startsWith('página ')) {
        lastExerciseName = line;
        recordRoutineExercise(line);
      }
    }

    flushRoutine();
    // Se só temos um plano/rotina semanal (sem datas nem cargas registradas em kg),
    // priorizamos `routines` sem inflar `workouts` com cargas 0kg.
    final hasAnyWeight = currentExercises.values.any(
      (sets) => sets.any((s) => s.weightKg > 0),
    );
    if (routines.isEmpty || workouts.isNotEmpty || hasAnyWeight) {
      flushWorkout();
    }

    return OpenGymSummary(
      sourceName: sourceName,
      workouts: workouts,
      routines: routines,
      personalRecords: _computePersonalRecords(workouts),
      weightEntries: weights,
      rawExtractedText: rawText.trim(),
    );
  }

  /// Faz parse flexível de backups JSON (`opengym-state.json` / `state-*.json`).
  static OpenGymSummary parseJsonExport(
    String rawJson, {
    String sourceName = 'opengym-state.json',
  }) {
    final decoded = jsonDecode(rawJson);
    Map<String, dynamic> root;
    if (decoded is Map<String, dynamic>) {
      if (decoded['state'] is Map<String, dynamic>) {
        root = decoded['state'] as Map<String, dynamic>;
      } else if (decoded['data'] is Map<String, dynamic>) {
        root = decoded['data'] as Map<String, dynamic>;
      } else {
        root = decoded;
      }
    } else if (decoded is List) {
      root = <String, dynamic>{'workouts': decoded};
    } else {
      throw const FormatException('JSON do openGym inválido.');
    }

    // Mapa opcional id -> nome de exercício (algumas versões referenciam exerciseId)
    final exerciseCatalog = <String, ({String name, String muscle})>{};
    final rawCatalog = root['exercises'] ?? root['customExercises'] ?? root['exerciseCatalog'];
    if (rawCatalog is List) {
      for (final item in rawCatalog) {
        if (item is Map) {
          final id = '${item['id'] ?? item['exerciseId'] ?? ''}'.trim();
          final name = '${item['name'] ?? item['title'] ?? ''}'.trim();
          final muscle = '${item['muscleGroup'] ?? item['muscle'] ?? item['bodyPart'] ?? ''}'.trim();
          if (id.isNotEmpty && name.isNotEmpty) {
            exerciseCatalog[id] = (name: name, muscle: muscle);
          }
        }
      }
    }

    // 1. Workouts / History / Sessions
    final workouts = <OpenGymWorkout>[];
    final rawWorkouts = root['workouts'] ??
        root['workoutHistory'] ??
        root['history'] ??
        root['sessions'] ??
        root['logs'];
    if (rawWorkouts is List) {
      for (final w in rawWorkouts) {
        if (w is! Map) continue;
        final wName = '${w['name'] ?? w['title'] ?? w['routineName'] ?? 'Treino'}'.trim();
        final date = _parseDate(
              w['date'] ?? w['startedAt'] ?? w['startTime'] ?? w['createdAt'] ?? w['timestamp'],
            ) ??
            DateTime.now();
        final durRaw = w['durationMinutes'] ?? w['duration'] ?? w['durationSec'];
        var durationMin = 0;
        if (durRaw is num) {
          durationMin = durRaw > 300 ? (durRaw / 60).round() : durRaw.round();
        }
        final notes = '${w['notes'] ?? w['note'] ?? ''}'.trim();
        final exList = <OpenGymExerciseLog>[];
        final rawEx = w['exercises'] ?? w['items'] ?? w['entries'];
        if (rawEx is List) {
          for (final ex in rawEx) {
            if (ex is! Map) continue;
            final exId = '${ex['exerciseId'] ?? ex['id'] ?? ''}'.trim();
            final catalogEntry = exerciseCatalog[exId];
            final exName = '${ex['name'] ?? ex['exerciseName'] ?? ex['title'] ?? catalogEntry?.name ?? 'Exercício'}'
                .trim();
            final muscle = '${ex['muscleGroup'] ?? ex['muscle'] ?? catalogEntry?.muscle ?? ''}'.trim();
            final sets = <OpenGymSet>[];
            final rawSets = ex['sets'] ?? ex['records'];
            if (rawSets is List) {
              for (final s in rawSets) {
                if (s is! Map) continue;
                final kg = _toDouble(s['weight'] ?? s['weightKg'] ?? s['kg'] ?? s['load']);
                final reps = _toInt(s['reps'] ?? s['repetitions'] ?? s['count']);
                final rpe = _toNullableDouble(s['rpe']);
                final completed = s['completed'] != false && s['done'] != false;
                if (kg > 0 || reps > 0) {
                  sets.add(
                    OpenGymSet(
                      weightKg: kg,
                      reps: reps,
                      rpe: rpe,
                      completed: completed,
                    ),
                  );
                }
              }
            }
            if (exName.isNotEmpty) {
              exList.add(
                OpenGymExerciseLog(
                  name: exName,
                  sets: sets,
                  muscleGroup: muscle,
                ),
              );
            }
          }
        }
        workouts.add(
          OpenGymWorkout(
            name: wName.isEmpty ? 'Treino' : wName,
            date: date,
            exercises: exList,
            durationMinutes: durationMin,
            notes: notes,
          ),
        );
      }
    }

    // 2. Routines / Templates
    final routines = <OpenGymRoutine>[];
    final rawRoutines = root['routines'] ?? root['templates'] ?? root['plans'];
    if (rawRoutines is List) {
      for (final r in rawRoutines) {
        if (r is! Map) continue;
        final rName = '${r['name'] ?? r['title'] ?? 'Rotina'}'.trim();
        final exNames = <String>[];
        final rEx = r['exercises'] ?? r['items'];
        if (rEx is List) {
          for (final item in rEx) {
            if (item is String && item.trim().isNotEmpty) {
              exNames.add(item.trim());
            } else if (item is Map) {
              final id = '${item['exerciseId'] ?? item['id'] ?? ''}'.trim();
              final n = '${item['name'] ?? item['exerciseName'] ?? exerciseCatalog[id]?.name ?? ''}'
                  .trim();
              if (n.isNotEmpty) exNames.add(n);
            }
          }
        }
        if (rName.isNotEmpty) {
          routines.add(OpenGymRoutine(name: rName, exercises: exNames));
        }
      }
    }

    // 3. Body weight logs
    final weights = <OpenGymWeightEntry>[];
    final rawWeights = root['bodyWeight'] ??
        root['bodyWeights'] ??
        root['bodyweightLogs'] ??
        root['weights'] ??
        root['weighIns'] ??
        root['weightHistory'];
    if (rawWeights is List) {
      for (final item in rawWeights) {
        if (item is! Map) continue;
        final kg = _toDouble(item['weight'] ?? item['weightKg'] ?? item['kg'] ?? item['value']);
        final dt = _parseDate(item['date'] ?? item['timestamp'] ?? item['createdAt']);
        if (kg > 0 && dt != null) {
          weights.add(OpenGymWeightEntry(date: dt, weightKg: kg));
        }
      }
    }

    return OpenGymSummary(
      sourceName: sourceName,
      workouts: workouts,
      routines: routines,
      personalRecords: _computePersonalRecords(workouts),
      weightEntries: weights,
    );
  }

  /// Faz parse de exportações CSV do openGym / Strong / Hevy (treinos ou peso corporal).
  static OpenGymSummary parseCsvExport(
    String rawCsv, {
    String sourceName = 'opengym.csv',
  }) {
    final lines = const LineSplitter()
        .convert(rawCsv)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length < 2) {
      return OpenGymSummary(
        sourceName: sourceName,
        workouts: const [],
        routines: const [],
        personalRecords: const [],
        weightEntries: const [],
      );
    }

    final sep = lines.first.contains(';') && !lines.first.contains(',') ? ';' : ',';
    final headers = _splitCsvLine(lines.first, sep)
        .map((h) => h.trim().toLowerCase().replaceAll('"', ''))
        .toList();

    int col(List<String> candidates) {
      for (final c in candidates) {
        final idx = headers.indexWhere((h) => h == c || h.contains(c));
        if (idx >= 0) return idx;
      }
      return -1;
    }

    final dateIdx = col(['date', 'data', 'timestamp', 'start']);
    final workoutIdx = col(['workout', 'treino', 'routine', 'session']);
    final exerciseIdx = col(['exercise', 'exercicio', 'exercício']);
    final weightIdx = col(['weight', 'peso', 'kg', 'load', 'carga']);
    final repsIdx = col(['reps', 'rep', 'repet']);
    final rpeIdx = col(['rpe']);

    // CSV apenas de peso corporal (sem coluna de exercício)
    if (exerciseIdx < 0 && weightIdx >= 0 && dateIdx >= 0) {
      final weights = <OpenGymWeightEntry>[];
      for (final line in lines.skip(1)) {
        final cells = _splitCsvLine(line, sep);
        if (dateIdx >= cells.length || weightIdx >= cells.length) continue;
        final dt = _parseDate(cells[dateIdx]);
        final kg = _toDouble(cells[weightIdx]);
        if (dt != null && kg > 0) {
          weights.add(OpenGymWeightEntry(date: dt, weightKg: kg));
        }
      }
      return OpenGymSummary(
        sourceName: sourceName,
        workouts: const [],
        routines: const [],
        personalRecords: const [],
        weightEntries: weights,
      );
    }

    // CSV de treinos/séries
    final groupedWorkouts = <String, ({String name, DateTime date, Map<String, List<OpenGymSet>> exMap})>{};
    for (final line in lines.skip(1)) {
      final cells = _splitCsvLine(line, sep);
      if (exerciseIdx < 0 || exerciseIdx >= cells.length) continue;
      final exName = cells[exerciseIdx].trim();
      if (exName.isEmpty) continue;
      final date = (dateIdx >= 0 && dateIdx < cells.length)
          ? (_parseDate(cells[dateIdx]) ?? DateTime.now())
          : DateTime.now();
      final wName = (workoutIdx >= 0 && workoutIdx < cells.length && cells[workoutIdx].trim().isNotEmpty)
          ? cells[workoutIdx].trim()
          : 'Treino';
      final kg = (weightIdx >= 0 && weightIdx < cells.length) ? _toDouble(cells[weightIdx]) : 0.0;
      final reps = (repsIdx >= 0 && repsIdx < cells.length) ? _toInt(cells[repsIdx]) : 0;
      final rpe = (rpeIdx >= 0 && rpeIdx < cells.length) ? _toNullableDouble(cells[rpeIdx]) : null;

      final dayKey = '${date.year}-${date.month}-${date.day}|$wName';
      final bucket = groupedWorkouts.putIfAbsent(
        dayKey,
        () => (name: wName, date: date, exMap: <String, List<OpenGymSet>>{}),
      );
      bucket.exMap
          .putIfAbsent(exName, () => <OpenGymSet>[])
          .add(OpenGymSet(weightKg: kg, reps: reps, rpe: rpe));
    }

    final workouts = groupedWorkouts.values.map((b) {
      final exLogs = b.exMap.entries
          .map((e) => OpenGymExerciseLog(name: e.key, sets: e.value))
          .toList();
      return OpenGymWorkout(name: b.name, date: b.date, exercises: exLogs);
    }).toList();

    return OpenGymSummary(
      sourceName: sourceName,
      workouts: workouts,
      routines: const [],
      personalRecords: _computePersonalRecords(workouts),
      weightEntries: const [],
    );
  }

  static List<OpenGymPersonalRecord> _computePersonalRecords(
    List<OpenGymWorkout> workouts,
  ) {
    final bestByExercise = <String, OpenGymPersonalRecord>{};
    for (final w in workouts) {
      for (final ex in w.exercises) {
        final key = ex.name.trim().toLowerCase();
        if (key.isEmpty) continue;
        for (final s in ex.sets) {
          if (!s.completed || s.weightKg <= 0 || s.reps <= 0) continue;
          final current = bestByExercise[key];
          final isBetter = current == null ||
              s.weightKg > current.maxWeightKg ||
              (s.weightKg == current.maxWeightKg && s.reps > current.repsAtMax);
          if (isBetter) {
            bestByExercise[key] = OpenGymPersonalRecord(
              exerciseName: ex.name.trim(),
              maxWeightKg: s.weightKg,
              repsAtMax: s.reps,
              estimated1RmKg: s.estimated1Rm,
              achievedOn: w.date,
            );
          }
        }
      }
    }
    final list = bestByExercise.values.toList()
      ..sort((a, b) => b.maxWeightKg.compareTo(a.maxWeightKg));
    return list;
  }

  static List<String> _splitCsvLine(String line, String sep) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == sep && !inQuotes) {
        out.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    out.add(buf.toString().trim());
    return out;
  }

  static double _toDouble(Object? raw) {
    if (raw is num) return raw.toDouble();
    final s = '${raw ?? ''}'.trim().replaceAll(',', '.');
    return double.tryParse(s) ?? 0.0;
  }

  static double? _toNullableDouble(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    final s = '$raw'.trim().replaceAll(',', '.');
    return double.tryParse(s);
  }

  static int _toInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    final s = '${raw ?? ''}'.trim();
    return int.tryParse(s) ?? double.tryParse(s.replaceAll(',', '.'))?.round() ?? 0;
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    if (raw is num) {
      final v = raw.toInt();
      if (v > 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(v);
      }
      if (v > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch(v * 1000);
      }
    }
    final s = '$raw'.trim();
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    // Suporte a formato BR DD/MM/YYYY
    final br = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(s);
    if (br != null) {
      return DateTime(
        int.parse(br.group(3)!),
        int.parse(br.group(2)!),
        int.parse(br.group(1)!),
      );
    }
    return null;
  }
}
