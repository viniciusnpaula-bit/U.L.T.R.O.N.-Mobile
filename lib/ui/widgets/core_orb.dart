import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

enum CoreStage { center, corner, hidden }

/// Renders the animated crimson U.L.T.R.O.N. orb using a runtime
/// [FragmentProgram] when available and falling back to [CorePainter].
/// Automatically pauses its [Ticker] when hidden or when the app leaves
/// [AppLifecycleState.resumed].
class CoreOrb extends StatefulWidget {
  const CoreOrb({
    super.key,
    required this.stage,
    this.shaderProgram,
    this.energy = 0.2,
    this.onTickerStateChanged,
  });

  final CoreStage stage;
  final FragmentProgram? shaderProgram;
  final double energy;
  final ValueChanged<bool>? onTickerStateChanged;

  @override
  State<CoreOrb> createState() => _CoreOrbState();
}

class _CoreOrbState extends State<CoreOrb>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  bool _lifecycleActive = true;
  bool? _lastNotifiedTickerActive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initialLifecycle = WidgetsBinding.instance.lifecycleState;
    _lifecycleActive =
        initialLifecycle == null || initialLifecycle == AppLifecycleState.resumed;
    _ticker = createTicker((duration) {
      _time.value = duration.inMicroseconds / 1000000.0;
    });
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant CoreOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage != widget.stage ||
        oldWidget.onTickerStateChanged != widget.onTickerStateChanged) {
      _syncTicker();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleActive = state == AppLifecycleState.resumed;
    _syncTicker();
  }

  void _syncTicker() {
    final shouldRun = _lifecycleActive && widget.stage != CoreStage.hidden;
    if (shouldRun && !_ticker.isActive) {
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
    }
    if (_lastNotifiedTickerActive != _ticker.isActive) {
      _lastNotifiedTickerActive = _ticker.isActive;
      widget.onTickerStateChanged?.call(_ticker.isActive);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stage == CoreStage.hidden) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<double>(
      valueListenable: _time,
      builder: (context, time, _) {
        final program = widget.shaderProgram;
        final CustomPainter painter = program != null
            ? _ShaderCorePainter(
                program: program,
                time: time,
                energy: widget.energy,
              )
            : CorePainter(time, energy: widget.energy);
        return CustomPaint(painter: painter);
      },
    );
  }
}

class _ShaderCorePainter extends CustomPainter {
  _ShaderCorePainter({
    required this.program,
    required this.time,
    required this.energy,
  });

  final FragmentProgram program;
  final double time;
  final double energy;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    try {
      final shader = program.fragmentShader();
      shader.setFloat(0, size.width);
      shader.setFloat(1, size.height);
      shader.setFloat(2, time);
      shader.setFloat(3, energy);
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    } catch (_) {
      CorePainter(time, energy: energy).paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant _ShaderCorePainter oldDelegate) =>
      oldDelegate.program != program ||
      oldDelegate.time != time ||
      oldDelegate.energy != energy;
}

class CorePainter extends CustomPainter {
  CorePainter(this.time, {this.energy = 0.2});

  final double time;
  final double energy;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final pulse = 1.0 + 0.04 * energy * math.sin(time * 4.0);
    final paint = Paint()
      ..color = const Color(0xFFE50914)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        center,
        size.shortestSide * (0.22 + i * 0.12) * pulse,
        paint,
      );
    }
    canvas.drawCircle(
      center,
      size.shortestSide * 0.07 * pulse,
      Paint()..color = const Color(0xFFFF1A24),
    );
  }

  @override
  bool shouldRepaint(covariant CorePainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.energy != energy;
}
