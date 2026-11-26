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
  });

  final String sourceName;
  final List<OpenGymWorkout> workouts;
  final List<OpenGymRoutine> routines;
  final List<OpenGymPersonalRecord> personalRecords;
  final List<OpenGymWeightEntry> weightEntries;
  final String? savedNotePath;

  OpenGymSummary withSavedNotePath(String path) => OpenGymSummary(
        sourceName: sourceName,
        workouts: workouts,
        routines: routines,
        personalRecords: personalRecords,
        weightEntries: weightEntries,
        savedNotePath: path,
      );

  bool get isEmpty =>
      workouts.isEmpty && routines.isEmpty && weightEntries.isEmpty;

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

    return sb.toString().trim();
  }

  String formatChatSummary() {
    if (isEmpty) {
      return 'Nenhum treino, rotina ou peso encontrado em "$sourceName". '
          'Exporte o backup JSON ou CSV no app openGym e importe novamente.';
    }
    final sb = StringBuffer()
      ..writeln('openGym sincronizado ($sourceName):')
      ..writeln('• Treinos: ${workouts.length} · Rotinas: ${routines.length} · Pesagens: ${weightEntries.length}');

    if (weightEntries.isNotEmpty) {
      final sortedW = [...weightEntries]..sort((a, b) => a.date.compareTo(b.date));
      final latest = sortedW.last;
      sb.writeln('• Peso atual: ${latest.weightKg.toStringAsFixed(1)} kg (${_fmtDate(latest.date)})');
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

    if (savedNotePath != null) {
      sb.writeln('• Memória do Modo Treino atualizada em `$savedNotePath`.');
    }
    return sb.toString().trim();
  }

  String get speakText {
    if (isEmpty) {
      return 'Não encontrei registros de treino nesse arquivo do OpenGym.';
    }
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
      final sortedW = [...weightEntries]..sort((a, b) => a.date.compareTo(b.date));
      parts.add(
        'peso corporal atual em ${sortedW.last.weightKg.toStringAsFixed(1)} quilos',
      );
    }
    return '${parts.join(', ')}.';
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

  /// Abre o seletor SAF nativo para escolher o backup `.json` ou `.csv` exportado do openGym.
  Future<File?> pickBackupFileSaf() async {
    try {
      final raw = await _channel.invokeListMethod<String>(
        'pickMultipleFilesSaf',
        <String, Object?>{
          'mimeTypes': const <String>[
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

  /// Procura automaticamente o backup mais recente do openGym em Downloads / Documents.
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
          final isJsonOrCsv = name.endsWith('.json') || name.endsWith('.csv');
          if (isJsonOrCsv &&
              (name.contains('opengym') ||
                  name.contains('open_gym') ||
                  name.contains('open-gym') ||
                  name.contains('workout'))) {
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

  /// Importa um arquivo JSON ou CSV do openGym e grava o resumo consolidado
  /// em `Memoria/Treino/OpenGym_Resumo.md` no cofre Obsidian.
  Future<OpenGymSummary> importFile(
    File file, {
    required ObsidianService obsidian,
    DateTime? now,
  }) async {
    final raw = await file.readAsString();
    final name = p.basename(file.path);
    final trimmed = raw.trimLeft();
    final summary = (name.toLowerCase().endsWith('.json') ||
            trimmed.startsWith('{') ||
            trimmed.startsWith('['))
        ? parseJsonExport(raw, sourceName: name)
        : parseCsvExport(raw, sourceName: name);

    if (!summary.isEmpty) {
      await obsidian.initialize();
      final noteFile = File(p.join(obsidian.root.path, summaryNotePath));
      await noteFile.parent.create(recursive: true);
      await noteFile.writeAsString(summary.toObsidianMarkdown(syncedAt: now));
      return summary.withSavedNotePath(summaryNotePath);
    }
    return summary;
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
