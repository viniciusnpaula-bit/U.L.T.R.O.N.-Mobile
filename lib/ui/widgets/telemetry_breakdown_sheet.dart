import 'package:flutter/material.dart';

import '../../services/ai_provider_service.dart';
import '../theme/ultron_theme.dart';

/// Abre o modal de breakdown detalhado de consumo, latência e failovers por provedor.
Future<void> showTelemetryBreakdownSheet(
  BuildContext context, {
  required SessionTelemetry telemetry,
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
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.84,
        ),
        child: TelemetryBreakdownSheet(
          telemetry: telemetry,
          onClose: () => Navigator.of(ctx).pop(),
        ),
      ),
    ),
  );
}

class TelemetryBreakdownSheet extends StatelessWidget {
  const TelemetryBreakdownSheet({
    super.key,
    required this.telemetry,
    this.onClose,
  });

  final SessionTelemetry telemetry;
  final VoidCallback? onClose;

  static String _formatClock(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}:${l.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = UltronTheme.accentOf(context);
    final accentDark = UltronTheme.accentDarkOf(context);
    final accentBorder = UltronTheme.accentBorderOf(context);
    final breakdown = telemetry.providerBreakdown;
    final totalTok = telemetry.totalTokens;
    final realTok = telemetry.realTokens;
    final estTok = telemetry.estimatedTokens;
    final realRatio = totalTok > 0 ? (realTok / totalTok).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
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
                child: Icon(Icons.analytics_outlined, size: 17, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Consumo e Telemetria por Provedor',
                      style: TextStyle(
                        color: UltronColors.textPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Sessão iniciada às ${_formatClock(telemetry.startedAt)}',
                      style: UltronTheme.mono.copyWith(
                        color: UltronColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClose != null)
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: UltronColors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _KpiTile(
                        label: 'Turnos',
                        value: '${telemetry.turns}',
                        accent: accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _KpiTile(
                        label: 'Total Tokens',
                        value: SessionTelemetry.formatCompactTokens(totalTok),
                        subtitle:
                            '↑${SessionTelemetry.formatCompactTokens(telemetry.promptTokens)} ↓${SessionTelemetry.formatCompactTokens(telemetry.completionTokens)}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _KpiTile(
                        label: 'Latência Média',
                        value: telemetry.averageLatencyMs > 0
                            ? '${telemetry.averageLatencyMs}ms'
                            : '--',
                        subtitle: telemetry.lastLatencyMs > 0
                            ? 'última ${telemetry.lastLatencyMs}ms'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _KpiTile(
                        label: 'Failovers',
                        value: '${telemetry.failoverEvents}',
                        subtitle: '${telemetry.totalFailedAttempts} falha(s)',
                        valueColor: telemetry.failoverEvents > 0
                            ? UltronColors.warning
                            : UltronColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const UltronSectionLabel('Tokens reais vs. estimados'),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: UltronColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: UltronColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          height: 8,
                          child: totalTok == 0
                              ? Container(color: UltronColors.surface)
                              : Row(
                                  children: [
                                    if (realTok > 0)
                                      Expanded(
                                        flex: realTok,
                                        child: Container(
                                          color: UltronColors.positive,
                                        ),
                                      ),
                                    if (estTok > 0)
                                      Expanded(
                                        flex: estTok,
                                        child: Container(
                                          color: UltronColors.warning,
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          Text(
                            'Reais: ${SessionTelemetry.formatCompactTokens(realTok)} (${(realRatio * 100).round()}%)',
                            style: UltronTheme.mono.copyWith(
                              color: UltronColors.positive,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'Estimados: ${SessionTelemetry.formatCompactTokens(estTok)} (${totalTok > 0 ? 100 - (realRatio * 100).round() : 0}%)',
                            style: UltronTheme.mono.copyWith(
                              color: UltronColors.warning,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const UltronSectionLabel('Breakdown por provedor / modelo'),
                if (breakdown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Nenhum turno de IA registrado nesta sessão.',
                      style: TextStyle(
                        color: UltronColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  )
                else
                  for (final stat in breakdown) ...[
                    _ProviderStatCard(
                      stat: stat,
                      maxTokens: totalTok,
                      isActive: stat.provider == telemetry.lastProvider,
                      accent: accent,
                    ),
                    const SizedBox(height: 8),
                  ],
                const SizedBox(height: 8),
                const UltronSectionLabel('Eventos de failover da sessão'),
                if (telemetry.failoverHistory.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: UltronColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: UltronColors.borderSubtle),
                    ),
                    child: const Text(
                      'Nenhum failover registrado nesta sessão.',
                      style: TextStyle(
                        color: UltronColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  )
                else
                  for (final ev in telemetry.failoverHistory.reversed) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: UltronColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: UltronColors.warning.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.swap_horiz_rounded,
                                size: 15,
                                color: UltronColors.warning,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Assumiu: ${ev.resolvedProvider}',
                                  style: const TextStyle(
                                    color: UltronColors.textPrimary,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                _formatClock(ev.timestamp),
                                style: UltronTheme.mono.copyWith(
                                  color: UltronColors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${ev.failedAttempts} tentativa(s) falha(s) · ${ev.latencyMs}ms'
                            '${ev.failedProviders.isEmpty ? '' : '\nFalharam: ${ev.failedProviders.join(' → ')}'}',
                            style: UltronTheme.mono.copyWith(
                              color: UltronColors.textSecondary,
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    this.subtitle,
    this.accent,
    this.valueColor,
  });

  final String label;
  final String value;
  final String? subtitle;
  final Color? accent;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: UltronColors.surfaceElevated,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: UltronColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: UltronColors.textMuted,
              fontSize: 10.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: UltronTheme.mono.copyWith(
              color: valueColor ?? accent ?? UltronColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: UltronTheme.mono.copyWith(
                color: UltronColors.textSecondary,
                fontSize: 9.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProviderStatCard extends StatelessWidget {
  const _ProviderStatCard({
    required this.stat,
    required this.maxTokens,
    required this.isActive,
    required this.accent,
  });

  final ProviderTelemetryStats stat;
  final int maxTokens;
  final bool isActive;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final share =
        maxTokens > 0 ? (stat.totalTokens / maxTokens).clamp(0.0, 1.0) : 0.0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: UltronColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? accent.withValues(alpha: 0.55) : UltronColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  stat.provider,
                  style: const TextStyle(
                    color: UltronColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isActive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'ATIVO',
                    style: UltronTheme.mono.copyWith(
                      color: accent,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 5,
              backgroundColor: UltronColors.surface,
              color: accent,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Turnos: ${stat.turns}  ·  Tokens: ${SessionTelemetry.formatCompactTokens(stat.totalTokens)} '
            '(↑${SessionTelemetry.formatCompactTokens(stat.promptTokens)} ↓${SessionTelemetry.formatCompactTokens(stat.completionTokens)})',
            style: UltronTheme.mono.copyWith(
              color: UltronColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Latência média: ${stat.averageLatencyMsRounded}ms  ·  '
            'Reais: ${SessionTelemetry.formatCompactTokens(stat.realTokens)} · '
            'Est.: ${SessionTelemetry.formatCompactTokens(stat.estimatedTokens)} · '
            'Falhas: ${stat.failedAttempts} · Failovers: ${stat.failovers}',
            style: UltronTheme.mono.copyWith(
              color: UltronColors.textMuted,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}
