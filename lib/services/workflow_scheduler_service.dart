import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/security/action_gate.dart';
import '../core/security/auth_gate.dart';
import 'audit_log_service.dart';

class WorkflowDefinition {
  const WorkflowDefinition({
    required this.id,
    required this.name,
    required this.stepsPayload,
    this.scheduleSpec = '',
    this.nextRunMs,
    this.intervalMinutes = 0,
    this.enabled = true,
    this.lastRunMs,
    this.lastStatus = 'IDLE',
  });

  factory WorkflowDefinition.fromRow(Map<String, Object?> row) =>
      WorkflowDefinition(
        id: (row['id'] as num).toInt(),
        name: (row['name'] as String? ?? '').trim(),
        stepsPayload: (row['steps_payload'] as String? ?? '').trim(),
        scheduleSpec: (row['schedule_spec'] as String? ?? '').trim(),
        nextRunMs: (row['next_run_ms'] as num?)?.toInt(),
        intervalMinutes: (row['interval_minutes'] as num?)?.toInt() ?? 0,
        enabled: ((row['enabled'] as num?)?.toInt() ?? 1) == 1,
        lastRunMs: (row['last_run_ms'] as num?)?.toInt(),
        lastStatus: (row['last_status'] as String? ?? 'IDLE').trim(),
      );

  final int id;
  final String name;
  final String stepsPayload;
  final String scheduleSpec;
  final int? nextRunMs;
  final int intervalMinutes;
  final bool enabled;
  final int? lastRunMs;
  final String lastStatus;

  static String _two(int v) => v.toString().padLeft(2, '0');

  String get formattedNextRun {
    if (nextRunMs == null || nextRunMs! <= 0) return 'manual';
    final dt = DateTime.fromMillisecondsSinceEpoch(nextRunMs!);
    final base =
        '${_two(dt.day)}/${_two(dt.month)} ${_two(dt.hour)}:${_two(dt.minute)}';
    if (intervalMinutes > 0) {
      return '$base (a cada ${intervalMinutes}m)';
    }
    return base;
  }

  String formatLine() =>
      '• [#$id] $name — Agendamento: $formattedNextRun • Passos: $stepsPayload [$lastStatus]';
}

class WorkflowExecutionResult {
  const WorkflowExecutionResult({
    required this.flowId,
    required this.flowName,
    required this.executed,
    required this.blockedByAuthGate,
    required this.logs,
    required this.message,
    this.pausedForConfirmation = false,
    this.completedSteps = 0,
    this.totalSteps = 0,
  });

  final int flowId;
  final String flowName;
  final bool executed;
  final bool blockedByAuthGate;
  final List<String> logs;
  final String message;
  final bool pausedForConfirmation;
  final int completedSteps;
  final int totalSteps;
}

class WorkflowStepResult {
  const WorkflowStepResult({
    required this.outcome,
    required this.log,
  });

  final ExecutionOutcome outcome;
  final String log;
}

class WorkflowCheckpoint {
  const WorkflowCheckpoint({
    required this.flowId,
    required this.nextStepIndex,
    required this.completedSteps,
    required this.status,
    required this.pausedReason,
    required this.updatedMs,
  });

  factory WorkflowCheckpoint.fromRow(Map<String, Object?> row) {
    final rawJson = (row['completed_steps_json'] as String?) ?? '[]';
    List<String> steps = const [];
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is List) {
        steps = decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return WorkflowCheckpoint(
      flowId: (row['flow_id'] as num).toInt(),
      nextStepIndex: (row['next_step_index'] as num).toInt(),
      completedSteps: steps,
      status: (row['status'] as String? ?? 'PAUSED_UNCERTAIN').trim(),
      pausedReason: (row['paused_reason'] as String? ?? '').trim(),
      updatedMs: (row['updated_ms'] as num?)?.toInt() ?? 0,
    );
  }

  final int flowId;
  final int nextStepIndex;
  final List<String> completedSteps;
  final String status;
  final String pausedReason;
  final int updatedMs;
}

typedef WorkflowStepExecutor = Future<WorkflowStepResult> Function(
  String stepTag, {
  required bool isBackgroundTrigger,
});

class ParsedScheduleSpec {
  const ParsedScheduleSpec({
    required this.label,
    required this.nextRunAt,
    this.intervalMinutes = 0,
  });

  final String label;
  final DateTime nextRunAt;
  final int intervalMinutes;
}

typedef WorkflowActionsExecutor = Future<List<String>> Function(
  String stepsPayload, {
  required bool isBackgroundTrigger,
});

/// Agendador e executor de Fluxos Dinâmicos (`[ACTION:FLOW_CREATE]`, `[ACTION:FLOW_LIST]`,
/// `[ACTION:FLOW_RUN]`, `[ACTION:FLOW_SCHEDULE]`, `[ACTION:FLOW_DELETE]`).
///
/// Respeita estritamente [AuthGate] e [ActionGate]:
/// - Se um fluxo agendado disparar em segundo plano (ou com sessão sem o nível exigido),
///   qualquer ação `sensitive` ou `critical` é **bloqueada automaticamente** (fail-closed)
///   e jamais executa silenciosamente sem sessão autorizada.
class WorkflowSchedulerService {
  WorkflowSchedulerService._(
    this._db, {
    MethodChannel? channel,
  }) : _channel = channel ??
            const MethodChannel('com.viniciusnpaula.ultron_mobile/device');

  final Database _db;
  final MethodChannel _channel;
  final ActionGate actionGate = const ActionGate();
  static WorkflowSchedulerService? _sharedInstance;

  static Future<WorkflowSchedulerService> instance({
    MethodChannel? channel,
  }) async {
    if (_sharedInstance != null && _sharedInstance!._db.isOpen) {
      return _sharedInstance!;
    }
    final svc = await open(channel: channel);
    _sharedInstance = svc;
    return svc;
  }

  static Future<WorkflowSchedulerService> open({
    Database? database,
    String? dbPath,
    MethodChannel? channel,
  }) async {
    late final Database db;
    if (database != null) {
      db = database;
    } else {
      final resolved =
          dbPath ?? p.join(await getDatabasesPath(), 'ultron_workflows.db');
      db = await openDatabase(resolved, version: 1);
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workflows (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        steps_payload TEXT NOT NULL,
        schedule_spec TEXT NOT NULL DEFAULT '',
        next_run_ms INTEGER,
        interval_minutes INTEGER NOT NULL DEFAULT 0,
        enabled INTEGER NOT NULL DEFAULT 1,
        last_run_ms INTEGER,
        last_status TEXT NOT NULL DEFAULT 'IDLE'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS workflow_checkpoints (
        flow_id INTEGER PRIMARY KEY,
        next_step_index INTEGER NOT NULL DEFAULT 0,
        completed_steps_json TEXT NOT NULL DEFAULT '[]',
        status TEXT NOT NULL DEFAULT 'RUNNING',
        paused_reason TEXT NOT NULL DEFAULT '',
        updated_ms INTEGER NOT NULL
      )
    ''');
    return WorkflowSchedulerService._(db, channel: channel);
  }

  static String normalizeFlowName(String raw) {
    final clean = raw.trim().replaceAll(RegExp(r'\s+'), '_');
    if (clean.isEmpty) {
      throw ArgumentError('Nome do fluxo não pode ser vazio.');
    }
    return clean;
  }

  /// Normaliza uma lista de passos (ex: `"TORCH_ON -> VOLUME_SET:30 -> SKILL:modo_estudo"`
  /// ou tags `[ACTION:...]`) para tags `[ACTION:...]` canônicas.
  static String normalizeStepsPayload(String rawSteps) {
    final trimmed = rawSteps.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('O fluxo deve conter ao menos uma ação ou skill.');
    }
    if (RegExp(r'\[(?:ACTION|HTTP):', caseSensitive: false).hasMatch(trimmed)) {
      return trimmed;
    }
    final tokens = trimmed
        .split(RegExp(r'\s*(?:->|;|,|\+)\s*'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (tokens.isEmpty) {
      throw ArgumentError('O fluxo deve conter ao menos uma ação válida.');
    }
    return tokens.map((token) {
      if (token.startsWith('[') && token.endsWith(']')) return token;
      final upper = token.toUpperCase();
      if (upper.startsWith('ACTION:')) return '[$token]';
      return '[ACTION:$token]';
    }).join(' ');
  }

  /// Extrai todas as tags `[ACTION:...]` / `[HTTP:...]` contidas no payload do fluxo.
  static List<String> extractActionTags(String stepsPayload) {
    final pattern = RegExp(
      r'\[(?:ACTION:((?:(?:\[\s*[xX ]?\s*\])|[^\]])+)|HTTP:(GET|POST|PUT|PATCH|DELETE):([^\]]+))\]',
      caseSensitive: false,
    );
    return pattern.allMatches(stepsPayload).map((m) => m.group(0)!).toList();
  }

  /// FLOW_CREATE: Cria ou atualiza um fluxo encadeado, opcionalmente com agendamento inicial.
  Future<WorkflowDefinition> createFlow({
    required String name,
    required String stepsPayload,
    String scheduleSpec = '',
    DateTime? now,
  }) async {
    final cleanName = normalizeFlowName(name);
    final normalizedSteps = normalizeStepsPayload(stepsPayload);
    final parsedSchedule = scheduleSpec.trim().isEmpty
        ? null
        : parseScheduleSpec(scheduleSpec, now: now);

    final nextRunMs = parsedSchedule?.nextRunAt.millisecondsSinceEpoch;
    final intervalMins = parsedSchedule?.intervalMinutes ?? 0;
    final specLabel = parsedSchedule?.label ?? '';

    final existing = await findFlow(cleanName);
    late final int flowId;
    if (existing != null) {
      flowId = existing.id;
      await _db.update(
        'workflows',
        {
          'name': cleanName,
          'steps_payload': normalizedSteps,
          'schedule_spec': specLabel,
          'next_run_ms': nextRunMs,
          'interval_minutes': intervalMins,
          'enabled': 1,
        },
        where: 'id = ?',
        whereArgs: [flowId],
      );
    } else {
      flowId = await _db.insert('workflows', {
        'name': cleanName,
        'steps_payload': normalizedSteps,
        'schedule_spec': specLabel,
        'next_run_ms': nextRunMs,
        'interval_minutes': intervalMins,
        'enabled': 1,
        'last_status': 'IDLE',
      });
    }

    if (nextRunMs != null) {
      await _scheduleNativeAlarm(
        flowId: flowId,
        name: cleanName,
        triggerAtMs: nextRunMs,
        intervalMinutes: intervalMins,
      );
    }

    return (await findFlow('$flowId'))!;
  }

  /// FLOW_SCHEDULE: Define ou atualiza o horário/periodicidade de um fluxo existente.
  Future<WorkflowDefinition> scheduleFlow({
    required String nameOrId,
    required String scheduleSpec,
    DateTime? now,
  }) async {
    final target = await findFlow(nameOrId);
    if (target == null) {
      throw ArgumentError('Fluxo "$nameOrId" não encontrado.');
    }
    final parsed = parseScheduleSpec(scheduleSpec, now: now);
    if (parsed == null) {
      throw ArgumentError('Especificação de horário inválida: "$scheduleSpec"');
    }
    final nextMs = parsed.nextRunAt.millisecondsSinceEpoch;
    await _db.update(
      'workflows',
      {
        'schedule_spec': parsed.label,
        'next_run_ms': nextMs,
        'interval_minutes': parsed.intervalMinutes,
        'enabled': 1,
      },
      where: 'id = ?',
      whereArgs: [target.id],
    );

    await _scheduleNativeAlarm(
      flowId: target.id,
      name: target.name,
      triggerAtMs: nextMs,
      intervalMinutes: parsed.intervalMinutes,
    );

    return (await findFlow('${target.id}'))!;
  }

  /// FLOW_LIST: Lista todos os fluxos cadastrados.
  Future<List<WorkflowDefinition>> listFlows() async {
    final rows = await _db.query('workflows', orderBy: 'id ASC');
    return rows.map(WorkflowDefinition.fromRow).toList();
  }

  /// Busca um fluxo por ID numérico ou nome.
  Future<WorkflowDefinition?> findFlow(String nameOrId) async {
    final clean = nameOrId.trim().replaceFirst(RegExp(r'^#'), '').trim();
    if (clean.isEmpty) return null;

    final asId = int.tryParse(clean);
    if (asId != null) {
      final byId = await _db.query(
        'workflows',
        where: 'id = ?',
        whereArgs: [asId],
        limit: 1,
      );
      if (byId.isNotEmpty) return WorkflowDefinition.fromRow(byId.first);
    }

    final normalized = clean.replaceAll(RegExp(r'\s+'), '_').toLowerCase();
    final all = await listFlows();
    for (final f in all) {
      if (f.name.toLowerCase() == normalized ||
          f.name.toLowerCase().contains(normalized)) {
        return f;
      }
    }
    return null;
  }

  /// FLOW_DELETE: Remove um fluxo do SQLite e cancela seu alarme nativo (`AlarmManager`).
  Future<WorkflowDefinition?> deleteFlow(String nameOrId) async {
    final target = await findFlow(nameOrId);
    if (target == null) return null;

    await _db.delete('workflows', where: 'id = ?', whereArgs: [target.id]);
    try {
      await _channel.invokeMethod<bool>('cancelWorkflowAlarm', {
        'id': target.id,
      });
    } catch (_) {}
    return target;
  }

  /// FLOW_RUN: Executa um fluxo validando cada ação pelo [ActionGate] e [AuthGate].
  ///
  /// Regra de segurança obrigatória:
  /// - Em execuções automáticas/agendadas (`isBackgroundTrigger: true`), ações
  ///   `RiskLevel.sensitive` ou `RiskLevel.critical` NUNCA executam silenciosamente
  ///   sem sessão autorizada; se a sessão estiver bloqueada (`locked` / `guarded`)
  ///   ou não tiver nível soberano (`sovereign`), o fluxo é bloqueado com status
  ///   `BLOCKED_AUTH_GATE`.
  Future<WorkflowExecutionResult> runFlow(
    String nameOrId, {
    required WorkflowActionsExecutor executor,
    AuthGate? authGate,
    bool isBackgroundTrigger = false,
    DateTime? now,
  }) async {
    final flow = await findFlow(nameOrId);
    if (flow == null) {
      throw ArgumentError('Fluxo "$nameOrId" não encontrado.');
    }

    final tags = extractActionTags(flow.stepsPayload);
    final currentLevel = authGate?.level ??
        (isBackgroundTrigger ? AccessLevel.locked : AccessLevel.basic);

    for (final tag in tags) {
      final sim = actionGate.simulate(tag);
      if (isBackgroundTrigger && sim.riskLevel != RiskLevel.safe) {
        // Disparo agendado só pode rodar ações sensíveis se a sessão ativa já estiver em sovereign (Biometria)
        // e nunca executa ações críticas silenciosamente.
        final allowedSilently = sim.riskLevel == RiskLevel.sensitive &&
            authGate != null &&
            currentLevel == AccessLevel.sovereign;
        if (!allowedSilently) {
          final reason =
              '🚫 Fluxo "${flow.name}" bloqueado pelo AuthGate: ação ${sim.actionCode} (${sim.riskLevel.name}) não pode executar silenciosamente sem sessão autorizada.';
          await _updateLastRun(
            flow,
            now: now ?? DateTime.now(),
            status: 'BLOCKED_AUTH_GATE',
          );
          return WorkflowExecutionResult(
            flowId: flow.id,
            flowName: flow.name,
            executed: false,
            blockedByAuthGate: true,
            logs: [reason],
            message: reason,
          );
        }
      } else if (authGate != null) {
        final decision = actionGate.evaluatePrivilege(sim, currentLevel);
        if (!decision.allowed) {
          final reason =
              '🚫 Fluxo "${flow.name}" bloqueado pelo AuthGate: ${decision.reason}';
          await _updateLastRun(
            flow,
            now: now ?? DateTime.now(),
            status: 'BLOCKED_AUTH_GATE',
          );
          return WorkflowExecutionResult(
            flowId: flow.id,
            flowName: flow.name,
            executed: false,
            blockedByAuthGate: true,
            logs: [reason],
            message: reason,
          );
        }
      }
    }

    final logs = await executor(
      flow.stepsPayload,
      isBackgroundTrigger: isBackgroundTrigger,
    );
    await _updateLastRun(
      flow,
      now: now ?? DateTime.now(),
      status: 'EXECUTED',
    );

    return WorkflowExecutionResult(
      flowId: flow.id,
      flowName: flow.name,
      executed: true,
      blockedByAuthGate: false,
      logs: logs,
      message:
          '⚙️ Fluxo "${flow.name}" executado (${logs.length} passo(s)): ${logs.join(' • ')}',
      completedSteps: tags.length,
      totalSteps: tags.length,
    );
  }

  /// Lê o checkpoint persistido de um fluxo pausado/interrompido (ou null se não houver).
  Future<WorkflowCheckpoint?> getCheckpoint(int flowId) async {
    final rows = await _db.query(
      'workflow_checkpoints',
      where: 'flow_id = ?',
      whereArgs: [flowId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return WorkflowCheckpoint.fromRow(rows.first);
  }

  /// Remove o checkpoint de um fluxo (após conclusão ou cancelamento manual).
  Future<void> clearCheckpoint(int flowId) async {
    await _db.delete(
      'workflow_checkpoints',
      where: 'flow_id = ?',
      whereArgs: [flowId],
    );
  }

  Future<void> _saveCheckpoint({
    required int flowId,
    required int nextStepIndex,
    required List<String> completedSteps,
    required String status,
    required String pausedReason,
    required DateTime now,
  }) async {
    await _db.insert(
      'workflow_checkpoints',
      {
        'flow_id': flowId,
        'next_step_index': nextStepIndex,
        'completed_steps_json': jsonEncode(completedSteps),
        'status': status,
        'paused_reason': pausedReason,
        'updated_ms': now.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Executa um fluxo etapa por etapa persistindo checkpoints no SQLite (Marco 2 — v1.7.0).
  ///
  /// - Se uma etapa retorna [ExecutionOutcome.uncertain] (ex.: Intent externo WhatsApp/Dial),
  ///   o fluxo **pausa** gravando o checkpoint na próxima etapa (`i + 1`) para que a retomada
  ///   nunca reexecute a ação já disparada.
  /// - Se uma etapa retorna [ExecutionOutcome.failed], o fluxo interrompe imediatamente.
  Future<WorkflowExecutionResult> runFlowWithCheckpoints(
    String nameOrId, {
    required WorkflowStepExecutor stepExecutor,
    AuthGate? authGate,
    bool isBackgroundTrigger = false,
    bool resumeFromCheckpoint = true,
    DateTime? now,
  }) async {
    final flow = await findFlow(nameOrId);
    if (flow == null) {
      throw ArgumentError('Fluxo "$nameOrId" não encontrado.');
    }
    final refNow = now ?? DateTime.now();
    final tags = extractActionTags(flow.stepsPayload);
    final currentLevel = authGate?.level ??
        (isBackgroundTrigger ? AccessLevel.locked : AccessLevel.basic);

    for (final tag in tags) {
      final sim = actionGate.simulate(tag);
      if (isBackgroundTrigger && sim.riskLevel != RiskLevel.safe) {
        final allowedSilently = sim.riskLevel == RiskLevel.sensitive &&
            authGate != null &&
            currentLevel == AccessLevel.sovereign;
        if (!allowedSilently) {
          final reason =
              '🚫 Fluxo "${flow.name}" bloqueado pelo AuthGate: ação ${sim.actionCode} (${sim.riskLevel.name}) não pode executar silenciosamente.';
          await _updateLastRun(flow, now: refNow, status: 'BLOCKED_AUTH_GATE');
          return WorkflowExecutionResult(
            flowId: flow.id,
            flowName: flow.name,
            executed: false,
            blockedByAuthGate: true,
            logs: [reason],
            message: reason,
            totalSteps: tags.length,
          );
        }
      } else if (authGate != null) {
        final decision = actionGate.evaluatePrivilege(sim, currentLevel);
        if (!decision.allowed) {
          final reason =
              '🚫 Fluxo "${flow.name}" bloqueado pelo AuthGate: ${decision.reason}';
          await _updateLastRun(flow, now: refNow, status: 'BLOCKED_AUTH_GATE');
          return WorkflowExecutionResult(
            flowId: flow.id,
            flowName: flow.name,
            executed: false,
            blockedByAuthGate: true,
            logs: [reason],
            message: reason,
            totalSteps: tags.length,
          );
        }
      }
    }

    final existing = resumeFromCheckpoint ? await getCheckpoint(flow.id) : null;
    final startIdx = (existing?.nextStepIndex ?? 0).clamp(0, tags.length);
    final completed = <String>[...(existing?.completedSteps ?? const [])];
    final logs = <String>[];

    for (var i = startIdx; i < tags.length; i++) {
      final tag = tags[i];
      final stepRes = await stepExecutor(
        tag,
        isBackgroundTrigger: isBackgroundTrigger,
      );
      logs.add(stepRes.log);

      if (stepRes.outcome == ExecutionOutcome.confirmed) {
        completed.add(tag);
        await _saveCheckpoint(
          flowId: flow.id,
          nextStepIndex: i + 1,
          completedSteps: completed,
          status: 'RUNNING',
          pausedReason: '',
          now: refNow,
        );
      } else if (stepRes.outcome == ExecutionOutcome.uncertain) {
        completed.add(tag);
        final reason =
            '⏸️ Fluxo "${flow.name}" pausado na etapa ${i + 1}/${tags.length} ($tag): efeito externo incerto. Confirme para retomar da etapa ${i + 2}.';
        await _saveCheckpoint(
          flowId: flow.id,
          nextStepIndex: i + 1,
          completedSteps: completed,
          status: 'PAUSED_UNCERTAIN',
          pausedReason: reason,
          now: refNow,
        );
        await _updateLastRun(flow, now: refNow, status: 'PAUSED_UNCERTAIN');
        return WorkflowExecutionResult(
          flowId: flow.id,
          flowName: flow.name,
          executed: false,
          blockedByAuthGate: false,
          pausedForConfirmation: true,
          completedSteps: completed.length,
          totalSteps: tags.length,
          logs: [...logs, reason],
          message: reason,
        );
      } else {
        final reason =
            '❌ Fluxo "${flow.name}" interrompido na etapa ${i + 1}/${tags.length} ($tag): falha na execução.';
        await _saveCheckpoint(
          flowId: flow.id,
          nextStepIndex: i,
          completedSteps: completed,
          status: 'FAILED',
          pausedReason: reason,
          now: refNow,
        );
        await _updateLastRun(flow, now: refNow, status: 'FAILED');
        return WorkflowExecutionResult(
          flowId: flow.id,
          flowName: flow.name,
          executed: false,
          blockedByAuthGate: false,
          completedSteps: completed.length,
          totalSteps: tags.length,
          logs: [...logs, reason],
          message: reason,
        );
      }
    }

    await clearCheckpoint(flow.id);
    await _updateLastRun(flow, now: refNow, status: 'EXECUTED');
    return WorkflowExecutionResult(
      flowId: flow.id,
      flowName: flow.name,
      executed: true,
      blockedByAuthGate: false,
      completedSteps: completed.length,
      totalSteps: tags.length,
      logs: logs,
      message:
          '⚙️ Fluxo "${flow.name}" concluído (${completed.length}/${tags.length} etapa(s)).',
    );
  }

  /// Verifica e executa fluxos cujo horário agendado (`nextRunMs`) já venceu.
  Future<List<WorkflowExecutionResult>> runDueFlows({
    required WorkflowActionsExecutor executor,
    AuthGate? authGate,
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final nowMs = current.millisecondsSinceEpoch;
    final rows = await _db.query(
      'workflows',
      where: 'enabled = 1 AND next_run_ms IS NOT NULL AND next_run_ms <= ?',
      whereArgs: [nowMs],
      orderBy: 'next_run_ms ASC',
    );
    final results = <WorkflowExecutionResult>[];
    for (final row in rows) {
      final flow = WorkflowDefinition.fromRow(row);
      final res = await runFlow(
        '${flow.id}',
        executor: executor,
        authGate: authGate,
        isBackgroundTrigger: true,
        now: current,
      );
      results.add(res);
    }
    return results;
  }

  Future<void> _updateLastRun(
    WorkflowDefinition flow, {
    required DateTime now,
    required String status,
  }) async {
    int? nextMs;
    if (flow.intervalMinutes > 0) {
      nextMs = now
          .add(Duration(minutes: flow.intervalMinutes))
          .millisecondsSinceEpoch;
      await _scheduleNativeAlarm(
        flowId: flow.id,
        name: flow.name,
        triggerAtMs: nextMs,
        intervalMinutes: flow.intervalMinutes,
      );
    }
    await _db.update(
      'workflows',
      {
        'last_run_ms': now.millisecondsSinceEpoch,
        'last_status': status,
        'next_run_ms': nextMs,
      },
      where: 'id = ?',
      whereArgs: [flow.id],
    );
  }

  Future<void> _scheduleNativeAlarm({
    required int flowId,
    required String name,
    required int triggerAtMs,
    required int intervalMinutes,
  }) async {
    try {
      await _channel.invokeMethod<bool>('scheduleWorkflowAlarm', {
        'id': flowId,
        'name': name,
        'triggerAtMs': triggerAtMs,
        'intervalMinutes': intervalMinutes,
      });
    } catch (_) {}
  }

  /// Faz parse de especificações de agendamento de fluxo:
  /// - `"07:30"` ou `"diario 07:30"` -> diário (intervalo 1440m)
  /// - `"a cada 30m"` / `"every 2h"` / `"15m"` -> periódico em minutos
  /// - `"daqui 10m"` / `"in 20m"` -> único relativo
  /// - `"2026-11-23 08:00"` -> único em data/hora fixa
  static ParsedScheduleSpec? parseScheduleSpec(
    String rawSpec, {
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final clean = rawSpec.trim();
    if (clean.isEmpty) return null;

    // 1. Periódico: "a cada 30m", "a cada 2 horas", "every 15m", "intervalo 60m"
    final periodicMatch = RegExp(
      r'^(?:a\s+cada|cada|every|intervalo)\s+(\d+)\s*(m|min|minutos?|h|horas?)$',
      caseSensitive: false,
    ).firstMatch(clean);
    if (periodicMatch != null) {
      final val = int.parse(periodicMatch.group(1)!);
      final unit = periodicMatch.group(2)!.toLowerCase();
      final mins = unit.startsWith('h') ? val * 60 : val;
      if (mins > 0) {
        return ParsedScheduleSpec(
          label: 'a cada ${mins}m',
          nextRunAt: ref.add(Duration(minutes: mins)),
          intervalMinutes: mins,
        );
      }
    }

    // 2. Relativo único: "daqui 15m", "em 30 minutos", "15m"
    final relMatch = RegExp(
      r'^(?:(?:daqui(?:\s+a)?|em|in)\s+)?(\d+)\s*(m|min|minutos?|h|horas?)$',
      caseSensitive: false,
    ).firstMatch(clean);
    if (relMatch != null) {
      final val = int.parse(relMatch.group(1)!);
      final unit = relMatch.group(2)!.toLowerCase();
      final mins = unit.startsWith('h') ? val * 60 : val;
      if (mins > 0) {
        return ParsedScheduleSpec(
          label: 'daqui ${mins}m',
          nextRunAt: ref.add(Duration(minutes: mins)),
          intervalMinutes: 0,
        );
      }
    }

    // 3. Diário em HH:MM ("diario 07:30", "daily 08:00", ou apenas "07:30")
    final dailyMatch = RegExp(
      r'^(?:(di[aá]rio|daily|todo\s+dia)\s+)?(\d{1,2}):(\d{2})$',
      caseSensitive: false,
    ).firstMatch(clean);
    if (dailyMatch != null) {
      final isRecurring = dailyMatch.group(1) != null;
      final hh = int.parse(dailyMatch.group(2)!).clamp(0, 23);
      final mm = int.parse(dailyMatch.group(3)!).clamp(0, 59);
      var next = DateTime(ref.year, ref.month, ref.day, hh, mm);
      if (!next.isAfter(ref)) {
        next = next.add(const Duration(days: 1));
      }
      final hhStr = hh.toString().padLeft(2, '0');
      final mmStr = mm.toString().padLeft(2, '0');
      return ParsedScheduleSpec(
        label: isRecurring ? 'diário $hhStr:$mmStr' : '$hhStr:$mmStr',
        nextRunAt: next,
        intervalMinutes: isRecurring ? 1440 : 0,
      );
    }

    // 4. Data/hora ISO: "YYYY-MM-DD HH:MM"
    final isoMatch = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})$',
    ).firstMatch(clean);
    if (isoMatch != null) {
      final y = int.parse(isoMatch.group(1)!);
      final m = int.parse(isoMatch.group(2)!);
      final d = int.parse(isoMatch.group(3)!);
      final hh = int.parse(isoMatch.group(4)!).clamp(0, 23);
      final mm = int.parse(isoMatch.group(5)!).clamp(0, 59);
      return ParsedScheduleSpec(
        label: clean,
        nextRunAt: DateTime(y, m, d, hh, mm),
        intervalMinutes: 0,
      );
    }

    return null;
  }

  Future<void> close() async {
    if (_db.isOpen) {
      await _db.close();
    }
    if (identical(_sharedInstance, this)) {
      _sharedInstance = null;
    }
  }
}
