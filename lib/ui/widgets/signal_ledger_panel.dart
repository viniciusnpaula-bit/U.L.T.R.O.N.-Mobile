import 'package:flutter/material.dart';

import '../../core/security/action_gate.dart';
import '../../services/signal_ledger_service.dart';
import '../theme/ultron_theme.dart';

/// Card resumo compacto para acesso ao Quadro "Sinal vs. Ruído" em seções do cockpit.
class SignalLedgerSummaryCard extends StatelessWidget {
  const SignalLedgerSummaryCard({
    super.key,
    required this.ledger,
    required this.onOpenBoard,
  });

  final SignalLedgerService ledger;
  final VoidCallback onOpenBoard;

  @override
  Widget build(BuildContext context) {
    final accent = UltronTheme.accentOf(context);
    final accentDark = UltronTheme.accentDarkOf(context);
    final accentBorder = UltronTheme.accentBorderOf(context);

    return ListenableBuilder(
      listenable: ledger,
      builder: (context, _) {
        final active = ledger.activeCount;
        final pending = ledger.pendingApprovalCount;
        final completed = ledger.completedCount;

        return Material(
          color: UltronColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: pending > 0
                  ? UltronColors.warning.withValues(alpha: 0.6)
                  : active > 0
                      ? accentBorder
                      : UltronColors.border,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const Key('signal_ledger_summary_card'),
            onTap: onOpenBoard,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: accentDark,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: accentBorder),
                        ),
                        child: Icon(
                          Icons.radar_rounded,
                          size: 18,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sinal vs. Ruído',
                              style: TextStyle(
                                color: UltronColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 1),
                            Text(
                              'Entregas ativas, aprovações e notas geradas',
                              style: TextStyle(
                                color: UltronColors.textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: UltronColors.textMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _StatusCounterPill(
                        label: 'Em andamento',
                        count: active,
                        color: accent,
                      ),
                      _StatusCounterPill(
                        label: 'Aprovação',
                        count: pending,
                        color: UltronColors.warning,
                      ),
                      _StatusCounterPill(
                        label: 'Concluído',
                        count: completed,
                        color: UltronColors.positive,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusCounterPill extends StatelessWidget {
  const _StatusCounterPill({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.14) : UltronColors.surfaceElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active ? color.withValues(alpha: 0.45) : UltronColors.borderSubtle,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? color : UltronColors.textMuted,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count $label',
            style: UltronTheme.mono.copyWith(
              color: active ? UltronColors.textPrimary : UltronColors.textSecondary,
              fontSize: 11,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

/// Abre o painel modal "Sinal vs. Ruído" integrado ao tema AMOLED + acento dinâmico.
Future<void> showSignalLedgerSheet(
  BuildContext context, {
  required SignalLedgerService ledger,
  Future<void> Function(String notePath)? onOpenObsidianNote,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: UltronColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      side: BorderSide(color: UltronColors.border),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.82,
        ),
        child: SignalLedgerBoard(
          ledger: ledger,
          onClose: () => Navigator.of(ctx).pop(),
          onOpenObsidianNote: onOpenObsidianNote == null
              ? null
              : (path) async {
                  Navigator.of(ctx).pop();
                  await onOpenObsidianNote(path);
                },
        ),
      ),
    ),
  );
}

/// Quadro visual completo de entregas e aprovações em 3 estados.
class SignalLedgerBoard extends StatefulWidget {
  const SignalLedgerBoard({
    super.key,
    required this.ledger,
    this.onClose,
    this.onOpenObsidianNote,
  });

  final SignalLedgerService ledger;
  final VoidCallback? onClose;
  final Future<void> Function(String notePath)? onOpenObsidianNote;

  @override
  State<SignalLedgerBoard> createState() => _SignalLedgerBoardState();
}

class _SignalLedgerBoardState extends State<SignalLedgerBoard> {
  late SignalLedgerState _selectedState;

  @override
  void initState() {
    super.initState();
    if (widget.ledger.pendingApprovalCount > 0) {
      _selectedState = SignalLedgerState.awaitingApproval;
    } else if (widget.ledger.activeCount > 0) {
      _selectedState = SignalLedgerState.inProgress;
    } else {
      _selectedState = SignalLedgerState.completed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = UltronTheme.accentOf(context);
    final accentDark = UltronTheme.accentDarkOf(context);
    final accentBorder = UltronTheme.accentBorderOf(context);

    return ListenableBuilder(
      listenable: widget.ledger,
      builder: (context, _) {
        final inProg = widget.ledger.inProgressItems;
        final awaiting = widget.ledger.awaitingApprovalItems;
        final completed = widget.ledger.completedItems;

        final visibleItems = switch (_selectedState) {
          SignalLedgerState.inProgress => inProg,
          SignalLedgerState.awaitingApproval => awaiting,
          SignalLedgerState.completed => completed,
        };

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accentDark,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: accentBorder),
                    ),
                    child: Icon(Icons.radar_rounded, size: 17, color: accent),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sinal vs. Ruído',
                          style: TextStyle(
                            color: UltronColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Consolidação operacional sem ruído de fundo',
                          style: TextStyle(
                            color: UltronColors.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedState == SignalLedgerState.completed &&
                      completed.isNotEmpty)
                    TextButton(
                      onPressed: widget.ledger.clearCompleted,
                      child: const Text(
                        'Limpar',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  if (widget.onClose != null)
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: UltronColors.textSecondary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _LedgerTabButton(
                      key: const Key('signal_tab_in_progress'),
                      label: 'Andamento',
                      count: inProg.length,
                      selected: _selectedState == SignalLedgerState.inProgress,
                      color: accent,
                      onTap: () => setState(
                        () => _selectedState = SignalLedgerState.inProgress,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _LedgerTabButton(
                      key: const Key('signal_tab_awaiting'),
                      label: 'Aprovação',
                      count: awaiting.length,
                      selected:
                          _selectedState == SignalLedgerState.awaitingApproval,
                      color: UltronColors.warning,
                      onTap: () => setState(
                        () =>
                            _selectedState = SignalLedgerState.awaitingApproval,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _LedgerTabButton(
                      key: const Key('signal_tab_completed'),
                      label: 'Concluído',
                      count: completed.length,
                      selected: _selectedState == SignalLedgerState.completed,
                      color: UltronColors.positive,
                      onTap: () => setState(
                        () => _selectedState = SignalLedgerState.completed,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: visibleItems.isEmpty
                    ? _EmptyLedgerState(state: _selectedState)
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: visibleItems.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _SignalLedgerCard(
                          item: visibleItems[index],
                          accent: accent,
                          onCancel: () =>
                              widget.ledger.cancelItem(visibleItems[index].id),
                          onApprove: () => widget.ledger.resolveApproval(
                            visibleItems[index].id,
                            approved: true,
                          ),
                          onReject: () => widget.ledger.resolveApproval(
                            visibleItems[index].id,
                            approved: false,
                          ),
                          onOpenNote: visibleItems[index].obsidianNotePath ==
                                      null ||
                                  widget.onOpenObsidianNote == null
                              ? null
                              : () => widget.onOpenObsidianNote!(
                                    visibleItems[index].obsidianNotePath!,
                                  ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LedgerTabButton extends StatelessWidget {
  const _LedgerTabButton({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? color.withValues(alpha: 0.16)
          : UltronColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(
          color: selected ? color.withValues(alpha: 0.6) : UltronColors.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? UltronColors.textPrimary
                        : UltronColors.textSecondary,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: 0.25)
                        : UltronColors.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: UltronTheme.mono.copyWith(
                      color: selected ? color : UltronColors.textSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SignalLedgerCard extends StatelessWidget {
  const _SignalLedgerCard({
    required this.item,
    required this.accent,
    required this.onCancel,
    required this.onApprove,
    required this.onReject,
    this.onOpenNote,
  });

  final SignalLedgerItem item;
  final Color accent;
  final VoidCallback onCancel;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback? onOpenNote;

  static String _formatTime(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final stateColor = switch (item.state) {
      SignalLedgerState.inProgress => accent,
      SignalLedgerState.awaitingApproval => UltronColors.warning,
      SignalLedgerState.completed => UltronColors.positive,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: UltronColors.surfaceElevated,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: item.state == SignalLedgerState.awaitingApproval
              ? UltronColors.warning.withValues(alpha: 0.45)
              : UltronColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.source.label.toUpperCase(),
                  style: UltronTheme.mono.copyWith(
                    color: stateColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (item.riskLevel != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: item.riskLevel == RiskLevel.critical
                        ? UltronColors.crimson.withValues(alpha: 0.16)
                        : UltronColors.warning.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item.riskLevel!.name.toUpperCase(),
                    style: UltronTheme.mono.copyWith(
                      color: item.riskLevel == RiskLevel.critical
                          ? UltronColors.crimson
                          : UltronColors.warning,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                _formatTime(item.timestamp),
                style: UltronTheme.mono.copyWith(
                  color: UltronColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            style: const TextStyle(
              color: UltronColors.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (item.subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.subtitle,
              style: const TextStyle(
                color: UltronColors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (item.state == SignalLedgerState.inProgress && item.canCancel) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded, size: 15),
                label: const Text('Cancelar'),
              ),
            ),
          ],
          if (item.state == SignalLedgerState.awaitingApproval &&
              (item.canApprove || item.canReject)) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (item.canReject)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReject,
                      child: const Text('Recusar'),
                    ),
                  ),
                if (item.canReject && item.canApprove)
                  const SizedBox(width: 8),
                if (item.canApprove)
                  Expanded(
                    child: FilledButton(
                      onPressed: onApprove,
                      child: const Text('Aprovar'),
                    ),
                  ),
              ],
            ),
          ],
          if (item.state == SignalLedgerState.completed &&
              item.obsidianNotePath != null) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: onOpenNote,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: UltronColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: UltronColors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 15,
                      color: accent,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        item.obsidianNotePath!,
                        style: UltronTheme.mono.copyWith(
                          color: UltronColors.textPrimary,
                          fontSize: 11.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (onOpenNote != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        'Abrir',
                        style: TextStyle(
                          color: accent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyLedgerState extends StatelessWidget {
  const _EmptyLedgerState({required this.state});

  final SignalLedgerState state;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = switch (state) {
      SignalLedgerState.inProgress => (
          Icons.hourglass_empty_rounded,
          'Nenhuma pesquisa, fluxo ou tarefa delegada ativa no momento.',
        ),
      SignalLedgerState.awaitingApproval => (
          Icons.verified_user_outlined,
          'Nenhuma solicitação aguardando aprovação no ActionGate.',
        ),
      SignalLedgerState.completed => (
          Icons.task_alt_rounded,
          'Nenhuma entrega finalizada registrada nesta sessão.',
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: UltronColors.textMuted),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: UltronColors.textSecondary,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
