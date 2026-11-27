import 'package:flutter/foundation.dart';

import '../core/security/action_gate.dart';
import 'deep_research_service.dart';
import 'workflow_scheduler_service.dart';

enum SignalLedgerState {
  inProgress('Em andamento'),
  awaitingApproval('Aguardando aprovação'),
  completed('Concluído');

  const SignalLedgerState(this.label);
  final String label;
}

enum SignalSourceKind {
  deepResearch('Pesquisa'),
  workflow('Fluxo'),
  desktopTask('Desktop PC'),
  actionGate('ActionGate'),
  remoteCommand('Remoto');

  const SignalSourceKind(this.label);
  final String label;
}

class SignalLedgerItem {
  const SignalLedgerItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.state,
    required this.source,
    required this.timestamp,
    this.obsidianNotePath,
    this.resultSummary,
    this.riskLevel,
    this.actionCode,
    this.canApprove = false,
    this.canReject = false,
    this.canCancel = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final SignalLedgerState state;
  final SignalSourceKind source;
  final DateTime timestamp;
  final String? obsidianNotePath;
  final String? resultSummary;
  final RiskLevel? riskLevel;
  final String? actionCode;
  final bool canApprove;
  final bool canReject;
  final bool canCancel;

  SignalLedgerItem copyWith({
    String? title,
    String? subtitle,
    SignalLedgerState? state,
    SignalSourceKind? source,
    DateTime? timestamp,
    String? obsidianNotePath,
    String? resultSummary,
    RiskLevel? riskLevel,
    String? actionCode,
    bool? canApprove,
    bool? canReject,
    bool? canCancel,
  }) =>
      SignalLedgerItem(
        id: id,
        title: title ?? this.title,
        subtitle: subtitle ?? this.subtitle,
        state: state ?? this.state,
        source: source ?? this.source,
        timestamp: timestamp ?? this.timestamp,
        obsidianNotePath: obsidianNotePath ?? this.obsidianNotePath,
        resultSummary: resultSummary ?? this.resultSummary,
        riskLevel: riskLevel ?? this.riskLevel,
        actionCode: actionCode ?? this.actionCode,
        canApprove: canApprove ?? this.canApprove,
        canReject: canReject ?? this.canReject,
        canCancel: canCancel ?? this.canCancel,
      );
}

class _PendingApprovalCallbacks {
  const _PendingApprovalCallbacks({this.onApprove, this.onReject});
  final Future<void> Function()? onApprove;
  final Future<void> Function()? onReject;
}

/// Quadro "Sinal vs. Ruído" (Signal & Approval Ledger) do U.L.T.R.O.N. Mobile.
///
/// Consolida entregas e aprovações em 3 estados objetivos:
/// - [SignalLedgerState.inProgress]: pesquisas ativas, fluxos em execução, tarefas delegadas ao PC.
/// - [SignalLedgerState.awaitingApproval]: ActionGate / fluxos pausados / comandos remotos pendentes.
/// - [SignalLedgerState.completed]: entregas finalizadas com link direto ao Obsidian ou resultado.
class SignalLedgerService extends ChangeNotifier {
  SignalLedgerService({
    DeepResearchService? deepResearch,
    DateTime Function()? now,
  })  : _deepResearch = deepResearch,
        _now = now ?? DateTime.now {
    _deepResearch?.addListener(_onDeepResearchChanged);
  }

  final DeepResearchService? _deepResearch;
  final DateTime Function() _now;
  final Map<String, SignalLedgerItem> _customItems =
      <String, SignalLedgerItem>{};
  final Map<String, _PendingApprovalCallbacks> _approvalCallbacks =
      <String, _PendingApprovalCallbacks>{};
  int _seq = 0;

  void _onDeepResearchChanged() => notifyListeners();

  @override
  void dispose() {
    _deepResearch?.removeListener(_onDeepResearchChanged);
    _approvalCallbacks.clear();
    super.dispose();
  }

  List<SignalLedgerItem> get allItems {
    final merged = <SignalLedgerItem>[
      ..._buildDeepResearchItems(),
      ..._customItems.values,
    ];
    merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return List<SignalLedgerItem>.unmodifiable(merged);
  }

  List<SignalLedgerItem> get inProgressItems => allItems
      .where((i) => i.state == SignalLedgerState.inProgress)
      .toList(growable: false);

  List<SignalLedgerItem> get awaitingApprovalItems => allItems
      .where((i) => i.state == SignalLedgerState.awaitingApproval)
      .toList(growable: false);

  List<SignalLedgerItem> get completedItems => allItems
      .where((i) => i.state == SignalLedgerState.completed)
      .toList(growable: false);

  int get activeCount => inProgressItems.length;
  int get pendingApprovalCount => awaitingApprovalItems.length;
  int get completedCount => completedItems.length;

  List<SignalLedgerItem> _buildDeepResearchItems() {
    final dr = _deepResearch;
    if (dr == null) return const <SignalLedgerItem>[];
    return dr.tasks.map((task) {
      final state = switch (task.status) {
        DeepResearchStatus.queued ||
        DeepResearchStatus.running =>
          SignalLedgerState.inProgress,
        DeepResearchStatus.completed ||
        DeepResearchStatus.cancelled ||
        DeepResearchStatus.failed =>
          SignalLedgerState.completed,
      };
      final subtitle = task.progressMessage.isNotEmpty
          ? task.progressMessage
          : '${task.status.label} · ${task.sources.length} fonte(s)';
      return SignalLedgerItem(
        id: 'dr:${task.id}',
        title: task.topic,
        subtitle: subtitle,
        state: state,
        source: SignalSourceKind.deepResearch,
        timestamp: task.completedAt ?? task.startedAt,
        obsidianNotePath: task.savedNotePath,
        resultSummary: task.status == DeepResearchStatus.completed
            ? '${task.sources.length} fonte(s) coletada(s)'
            : task.error,
        canCancel: state == SignalLedgerState.inProgress,
      );
    }).toList(growable: false);
  }

  void trackWorkflowStarted({
    required int flowId,
    required String flowName,
    int totalSteps = 0,
  }) {
    final id = 'wf:$flowId';
    _customItems[id] = SignalLedgerItem(
      id: id,
      title: 'Fluxo: $flowName',
      subtitle: totalSteps > 0
          ? 'Executando $totalSteps etapa(s)...'
          : 'Execução em andamento...',
      state: SignalLedgerState.inProgress,
      source: SignalSourceKind.workflow,
      timestamp: _now(),
      canCancel: false,
    );
    notifyListeners();
  }

  void recordWorkflowResult(
    WorkflowExecutionResult result, {
    Future<void> Function()? onApproveResume,
    Future<void> Function()? onRejectResume,
  }) {
    final id = 'wf:${result.flowId}';
    final needsApproval =
        result.pausedForConfirmation || result.blockedByAuthGate;
    if (needsApproval) {
      if (onApproveResume != null || onRejectResume != null) {
        _approvalCallbacks[id] = _PendingApprovalCallbacks(
          onApprove: onApproveResume,
          onReject: onRejectResume,
        );
      }
      _customItems[id] = SignalLedgerItem(
        id: id,
        title: 'Fluxo: ${result.flowName}',
        subtitle: result.message,
        state: SignalLedgerState.awaitingApproval,
        source: SignalSourceKind.workflow,
        timestamp: _now(),
        riskLevel: RiskLevel.sensitive,
        actionCode: result.blockedByAuthGate ? 'AUTH_GATE' : 'FLOW_RESUME',
        canApprove: true,
        canReject: true,
      );
    } else {
      _approvalCallbacks.remove(id);
      _customItems[id] = SignalLedgerItem(
        id: id,
        title: 'Fluxo: ${result.flowName}',
        subtitle: result.executed
            ? 'Concluído (${result.completedSteps}/${result.totalSteps} etapa(s))'
            : 'Interrompido',
        state: SignalLedgerState.completed,
        source: SignalSourceKind.workflow,
        timestamp: _now(),
        resultSummary: result.message,
      );
    }
    notifyListeners();
  }

  void syncWorkflows(
    List<WorkflowDefinition> flows, {
    Map<int, WorkflowCheckpoint> checkpoints = const {},
  }) {
    var changed = false;
    for (final f in flows) {
      final cp = checkpoints[f.id];
      final status = (cp?.status ?? f.lastStatus).toUpperCase();
      final id = 'wf:${f.id}';
      if (status == 'RUNNING') {
        _customItems[id] = SignalLedgerItem(
          id: id,
          title: 'Fluxo: ${f.name}',
          subtitle: 'Em execução (${f.scheduleSpec.isEmpty ? 'manual' : f.scheduleSpec})',
          state: SignalLedgerState.inProgress,
          source: SignalSourceKind.workflow,
          timestamp: f.lastRunMs != null
              ? DateTime.fromMillisecondsSinceEpoch(f.lastRunMs!)
              : _now(),
        );
        changed = true;
      } else if (status == 'PAUSED_UNCERTAIN' || status == 'BLOCKED_AUTH_GATE') {
        _customItems[id] = SignalLedgerItem(
          id: id,
          title: 'Fluxo: ${f.name}',
          subtitle: cp?.pausedReason.isNotEmpty == true
              ? cp!.pausedReason
              : 'Aguardando confirmação ou elevação do AuthGate.',
          state: SignalLedgerState.awaitingApproval,
          source: SignalSourceKind.workflow,
          timestamp: f.lastRunMs != null
              ? DateTime.fromMillisecondsSinceEpoch(f.lastRunMs!)
              : _now(),
          riskLevel: RiskLevel.sensitive,
          actionCode: status,
          canApprove: true,
          canReject: true,
        );
        changed = true;
      } else if (status == 'EXECUTED' && f.lastRunMs != null) {
        _customItems[id] = SignalLedgerItem(
          id: id,
          title: 'Fluxo: ${f.name}',
          subtitle: 'Última execução concluída',
          state: SignalLedgerState.completed,
          source: SignalSourceKind.workflow,
          timestamp: DateTime.fromMillisecondsSinceEpoch(f.lastRunMs!),
          resultSummary: f.stepsPayload,
        );
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  String recordDesktopTaskDelegated({
    required String topic,
    String? id,
    String? detail,
  }) {
    final itemId = id?.trim().isNotEmpty == true
        ? 'pc:${id!.trim()}'
        : 'pc:${++_seq}_${_now().millisecondsSinceEpoch}';
    _customItems[itemId] = SignalLedgerItem(
      id: itemId,
      title: topic.trim().isEmpty ? 'Tarefa delegada ao PC' : topic.trim(),
      subtitle: detail?.trim().isNotEmpty == true
          ? detail!.trim()
          : 'Delegada para subagente no U.L.T.R.O.N. Desktop.',
      state: SignalLedgerState.inProgress,
      source: SignalSourceKind.desktopTask,
      timestamp: _now(),
      canCancel: true,
    );
    notifyListeners();
    return itemId;
  }

  void completeDesktopTask(
    String id, {
    String? resultSummary,
    String? obsidianNotePath,
    bool failed = false,
  }) {
    final key = id.startsWith('pc:') ? id : 'pc:$id';
    final existing = _customItems[key];
    if (existing == null) return;
    _customItems[key] = existing.copyWith(
      subtitle: failed
          ? (resultSummary ?? 'Falha na execução remota')
          : (resultSummary ?? 'Entrega concluída pelo Desktop'),
      state: SignalLedgerState.completed,
      timestamp: _now(),
      obsidianNotePath: obsidianNotePath,
      resultSummary: resultSummary,
      canCancel: false,
    );
    notifyListeners();
  }

  void syncDesktopTasksPayload(List<Map<String, dynamic>> tasks) {
    for (final raw in tasks) {
      final rawId = (raw['id'] ?? raw['task_id'] ?? '').toString().trim();
      final topic = (raw['topic'] ?? raw['query'] ?? raw['title'] ?? 'Tarefa PC')
          .toString()
          .trim();
      if (rawId.isEmpty && topic.isEmpty) continue;
      final id = rawId.isNotEmpty ? 'pc:$rawId' : 'pc:$topic';
      final statusStr = (raw['status'] ?? '').toString().trim().toLowerCase();
      final notePath =
          (raw['note_path'] ?? raw['obsidian_path'] ?? raw['savedNotePath'])
              ?.toString()
              .trim();
      final summary =
          (raw['result'] ?? raw['summary'] ?? raw['message'])?.toString().trim();

      final state = switch (statusStr) {
        'awaiting_approval' ||
        'pending_approval' ||
        'paused' =>
          SignalLedgerState.awaitingApproval,
        'completed' ||
        'done' ||
        'finished' ||
        'failed' ||
        'cancelled' =>
          SignalLedgerState.completed,
        _ => SignalLedgerState.inProgress,
      };
      _customItems[id] = SignalLedgerItem(
        id: id,
        title: topic,
        subtitle: summary?.isNotEmpty == true
            ? summary!
            : 'Status PC: ${statusStr.isEmpty ? 'ativo' : statusStr}',
        state: state,
        source: SignalSourceKind.desktopTask,
        timestamp: _now(),
        obsidianNotePath:
            (notePath != null && notePath.isNotEmpty) ? notePath : null,
        resultSummary: summary,
        canApprove: state == SignalLedgerState.awaitingApproval,
        canReject: state == SignalLedgerState.awaitingApproval,
        canCancel: state == SignalLedgerState.inProgress,
      );
    }
    notifyListeners();
  }

  String registerPendingApproval({
    required ActionSimulation simulation,
    String? id,
    SignalSourceKind source = SignalSourceKind.actionGate,
    String? requester,
    Future<void> Function()? onApprove,
    Future<void> Function()? onReject,
  }) {
    final itemId = id?.trim().isNotEmpty == true
        ? id!.trim()
        : 'gate:${++_seq}_${_now().millisecondsSinceEpoch}';
    if (onApprove != null || onReject != null) {
      _approvalCallbacks[itemId] = _PendingApprovalCallbacks(
        onApprove: onApprove,
        onReject: onReject,
      );
    }
    final reqPrefix =
        requester != null && requester.trim().isNotEmpty ? '[$requester] ' : '';
    _customItems[itemId] = SignalLedgerItem(
      id: itemId,
      title: '${simulation.actionCode}: ${simulation.targetResource}',
      subtitle: '$reqPrefix${simulation.description}',
      state: SignalLedgerState.awaitingApproval,
      source: source,
      timestamp: _now(),
      riskLevel: simulation.riskLevel,
      actionCode: simulation.actionCode,
      resultSummary: simulation.estimatedImpact,
      canApprove: true,
      canReject: true,
    );
    notifyListeners();
    return itemId;
  }

  Future<bool> resolveApproval(
    String id, {
    required bool approved,
    String? outcomeSummary,
  }) async {
    final existing = _customItems[id];
    if (existing == null || existing.state != SignalLedgerState.awaitingApproval) {
      return false;
    }
    final callbacks = _approvalCallbacks.remove(id);
    if (approved) {
      await callbacks?.onApprove?.call();
    } else {
      await callbacks?.onReject?.call();
    }
    _customItems[id] = existing.copyWith(
      state: SignalLedgerState.completed,
      subtitle: outcomeSummary ??
          (approved ? 'Aprovado pelo Operador' : 'Recusado pelo Operador'),
      resultSummary: outcomeSummary ??
          (approved ? 'Execução autorizada' : 'Execução negada no ActionGate'),
      timestamp: _now(),
      canApprove: false,
      canReject: false,
    );
    notifyListeners();
    return true;
  }

  bool cancelItem(String id) {
    if (id.startsWith('dr:')) {
      final drId = id.substring(3);
      return _deepResearch?.cancel(drId) ?? false;
    }
    final existing = _customItems[id];
    if (existing == null || existing.state != SignalLedgerState.inProgress) {
      return false;
    }
    _customItems[id] = existing.copyWith(
      state: SignalLedgerState.completed,
      subtitle: 'Cancelado pelo operador.',
      timestamp: _now(),
      canCancel: false,
    );
    notifyListeners();
    return true;
  }

  void recordCompletedDelivery({
    required String id,
    required String title,
    required String subtitle,
    required SignalSourceKind source,
    String? obsidianNotePath,
    String? resultSummary,
  }) {
    _customItems[id] = SignalLedgerItem(
      id: id,
      title: title,
      subtitle: subtitle,
      state: SignalLedgerState.completed,
      source: source,
      timestamp: _now(),
      obsidianNotePath: obsidianNotePath,
      resultSummary: resultSummary,
    );
    notifyListeners();
  }

  void clearCompleted() {
    _customItems.removeWhere(
      (_, item) => item.state == SignalLedgerState.completed,
    );
    notifyListeners();
  }
}
