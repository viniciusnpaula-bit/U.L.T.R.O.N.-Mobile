import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/startup_coordinator.dart';
import '../theme/ultron_theme.dart';

class BootLoadingScreen extends StatefulWidget {
  const BootLoadingScreen({super.key, required this.coordinator});

  final StartupCoordinator coordinator;

  @override
  State<BootLoadingScreen> createState() => _BootLoadingScreenState();
}

class _BootLoadingScreenState extends State<BootLoadingScreen> {
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() {
      if (mounted) {
        unawaited(widget.coordinator.start());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.coordinator,
      builder: (context, _) {
        final coordinator = widget.coordinator;
        final current = coordinator.stage;
        final error = coordinator.error;

        return Scaffold(
          backgroundColor: UltronColors.bg,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const UltronMark(size: 56),
                    const SizedBox(height: 16),
                    const Text(
                      'U.L.T.R.O.N.',
                      style: TextStyle(
                        color: UltronColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    LinearProgressIndicator(
                      value: coordinator.progress,
                      backgroundColor: UltronColors.surfaceElevated,
                      color: UltronTheme.accentOf(context),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      coordinator.statusLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: UltronColors.textSecondary),
                    ),
                    const SizedBox(height: 20),
                    _StageRow(
                      label: 'Cofre e histórico local',
                      stage: BootStage.vault,
                      current: current,
                      hasError: error != null,
                    ),
                    _StageRow(
                      label: 'Provedores de IA e STT',
                      stage: BootStage.aiProviders,
                      current: current,
                      hasError: error != null,
                    ),
                    _StageRow(
                      label: 'Pipeline de voz',
                      stage: BootStage.audio,
                      current: current,
                      hasError: error != null,
                    ),
                    _StageRow(
                      label: 'Núcleo visual 3D',
                      stage: BootStage.shader,
                      current: current,
                      hasError: error != null,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        error,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFF10D28),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: coordinator.isRunning
                            ? null
                            : () => unawaited(coordinator.start()),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.label,
    required this.stage,
    required this.current,
    required this.hasError,
  });

  final String label;
  final BootStage stage;
  final BootStage current;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final completed = current.index > stage.index;
    final active = current == stage;
    final icon = completed
        ? Icons.check_circle_outline
        : active && hasError
            ? Icons.error_outline
            : active
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked;
    final color = completed
        ? UltronTheme.accentOf(context)
        : active
            ? const Color(0xFF9A9AA3)
            : const Color(0xFF222228);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontSize: 13)),
        ],
      ),
    );
  }
}
