import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/startup_coordinator.dart';

class BootLoadingScreen extends StatefulWidget {
  const BootLoadingScreen({super.key, required this.coordinator});

  final StartupCoordinator coordinator;

  @override
  State<BootLoadingScreen> createState() => _BootLoadingScreenState();
}

class _BootLoadingScreenState extends State<BootLoadingScreen> {
  static const _crimson = Color(0xFFE50914);

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
          backgroundColor: const Color(0xFF0A0002),
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.radar, size: 72, color: _crimson),
                    const SizedBox(height: 16),
                    const Text(
                      'U.L.T.R.O.N.',
                      style: TextStyle(
                        color: Color(0xFFFFD0D3),
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 6,
                      ),
                    ),
                    const SizedBox(height: 20),
                    LinearProgressIndicator(
                      value: coordinator.progress,
                      backgroundColor: const Color(0xFF28050A),
                      color: _crimson,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      coordinator.statusLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFFFA0A0)),
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
                      label: 'Núcleo visual crimson',
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
                          color: Color(0xFFFF6B73),
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
        ? const Color(0xFFFF4D57)
        : active
            ? const Color(0xFFFFA0A0)
            : const Color(0xFF5A2227);

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
