import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

enum CoreStage { center, corner, hidden }

/// Renders the animated crimson U.L.T.R.O.N. holographic reactor core using a
/// runtime [FragmentProgram] plasma sphere layered with crisp 2D tactical HUD
/// gyroscopes, or falling back cleanly to [CorePainter].
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
  FragmentProgram? _cachedProgram;
  FragmentShader? _cachedShader;
  bool _lifecycleActive = true;
  bool? _lastNotifiedTickerActive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initialLifecycle = WidgetsBinding.instance.lifecycleState;
    _lifecycleActive = initialLifecycle == null ||
        initialLifecycle == AppLifecycleState.resumed;
    _syncShader();
    _ticker = createTicker((duration) {
      _time.value = duration.inMicroseconds / 1000000.0;
    });
    _syncTicker();
  }

  void _syncShader() {
    final nextProgram = widget.shaderProgram;
    if (identical(nextProgram, _cachedProgram)) return;
    _cachedShader?.dispose();
    _cachedShader = null;
    _cachedProgram = nextProgram;
    if (nextProgram != null) {
      try {
        _cachedShader = nextProgram.fragmentShader();
      } catch (_) {
        _cachedShader = null;
      }
    }
  }

  @override
  void didUpdateWidget(covariant CoreOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.shaderProgram, widget.shaderProgram)) {
      _syncShader();
    }
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
    _cachedShader?.dispose();
    _cachedShader = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stage == CoreStage.hidden) {
      return const SizedBox.shrink();
    }
    final shader = _cachedShader;
    if (shader != null) {
      return RepaintBoundary(
        child: CustomPaint(
          painter: _ShaderCorePainter(
            shader: shader,
            timeListenable: _time,
            energy: widget.energy,
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: _time,
        builder: (context, time, _) {
          return CustomPaint(
            painter: CorePainter(time, energy: widget.energy),
          );
        },
      ),
    );
  }
}

class _ShaderCorePainter extends CustomPainter {
  _ShaderCorePainter({
    required this.shader,
    required this.timeListenable,
    required this.energy,
  }) : super(repaint: timeListenable);

  final FragmentShader shader;
  final ValueListenable<double> timeListenable;
  final double energy;
  final Paint _shaderPaint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final time = timeListenable.value;
    var shaderDrawn = false;
    try {
      shader.setFloat(0, size.width);
      shader.setFloat(1, size.height);
      shader.setFloat(2, time);
      shader.setFloat(3, energy);
      _shaderPaint.shader = shader;
      canvas.drawRect(Offset.zero & size, _shaderPaint);
      shaderDrawn = true;
    } catch (_) {
      CorePainter(time, energy: energy).paint(canvas, size);
      return;
    }
    if (shaderDrawn) {
      _paintTacticalGyroscope(canvas, size, time, energy);
    }
  }

  @override
  bool shouldRepaint(covariant _ShaderCorePainter oldDelegate) =>
      oldDelegate.shader != shader ||
      oldDelegate.timeListenable != timeListenable ||
      oldDelegate.energy != energy;
}

class CorePainter extends CustomPainter {
  CorePainter(this.time, {this.energy = 0.2});

  final double time;
  final double energy;

  static const _auraGradient = RadialGradient(
    colors: [
      Color(0x669E0616),
      Color(0x3851080D),
      Color(0x142B0307),
      Color(0x0019171B),
    ],
    stops: [0.0, 0.36, 0.72, 1.0],
  );

  static const _sphereGradient = RadialGradient(
    colors: [
      Color(0xFFFFD8D6),
      Color(0xFFFF4A4E),
      Color(0xFFB80714),
      Color(0xFF280207),
      Color(0xFF0E0003),
    ],
    stops: [0.0, 0.18, 0.45, 0.82, 1.0],
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final side = size.shortestSide;
    final center = size.center(Offset.zero);
    final pulse = 1.0 + 0.03 * (0.4 + energy) * math.sin(time * 3.6);

    final auraRadius = side * 0.49;
    final auraRect = Rect.fromCircle(center: center, radius: auraRadius);
    canvas.drawCircle(
      center,
      auraRadius,
      Paint()..shader = _auraGradient.createShader(auraRect),
    );

    final sphereR = side * 0.235 * pulse;
    final sphereRect = Rect.fromCircle(center: center, radius: sphereR);
    canvas.drawCircle(
      center,
      sphereR,
      Paint()..shader = _sphereGradient.createShader(sphereRect),
    );
    canvas.drawCircle(
      center,
      sphereR,
      Paint()
        ..color = const Color(0xCCFF3B47)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    _paintTacticalGyroscope(canvas, size, time, energy);
  }

  @override
  bool shouldRepaint(covariant CorePainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.energy != energy;
}

void _paintTacticalGyroscope(
  Canvas canvas,
  Size size,
  double time,
  double energy,
) {
  final side = size.shortestSide;
  if (side <= 0) return;
  final center = size.center(Offset.zero);
  final speed = 0.75 + energy * 1.15;
  final scale = (side / 210.0).clamp(0.35, 2.2);

  canvas.save();
  canvas.translate(center.dx, center.dy);

  // 1. Segmented outer tactical brackets (4 arcs rotating slowly)
  final bracketR = side * 0.435;
  final bracketRect = Rect.fromCircle(center: Offset.zero, radius: bracketR);
  final bracketPaint = Paint()
    ..color = Color.lerp(
      const Color(0x99E50914),
      const Color(0xFFFF6B73),
      (energy * 0.6).clamp(0.0, 1.0),
    )!
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 2.1 * scale;

  final bracketAngle = time * 0.35 * speed;
  for (var i = 0; i < 4; i++) {
    final start = bracketAngle + i * (math.pi / 2) + 0.16;
    canvas.drawArc(bracketRect, start, math.pi / 2 - 0.32, false, bracketPaint);
  }

  // 2. Precision 24-tick azimuth dial
  final dialR = side * 0.375;
  final majorTickPaint = Paint()
    ..color = const Color(0xDDE50914)
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 1.6 * scale;
  final minorTickPaint = Paint()
    ..color = const Color(0x66FFA0A0)
    ..strokeWidth = 1.0 * scale;

  const tickCount = 24;
  for (var i = 0; i < tickCount; i++) {
    final theta = -time * 0.18 * speed + (i / tickCount) * math.pi * 2;
    final isMajor = i % 6 == 0;
    final inner = dialR - (isMajor ? 6.5 : 3.2) * scale;
    final outer = dialR + (isMajor ? 2.5 : 0.5) * scale;
    canvas.drawLine(
      Offset(math.cos(theta) * inner, math.sin(theta) * inner),
      Offset(math.cos(theta) * outer, math.sin(theta) * outer),
      isMajor ? majorTickPaint : minorTickPaint,
    );
  }

  // 3. Primary 3D-tilted elliptical orbital ring + glowing orbital nodes
  final baseR = side * 0.25;
  canvas.save();
  canvas.rotate(0.42 + time * 0.82 * speed);
  final orbit1Rect = Rect.fromCenter(
    center: Offset.zero,
    width: baseR * 1.48 * 2,
    height: baseR * 0.72 * 2,
  );
  canvas.drawOval(
    orbit1Rect,
    Paint()
      ..color = const Color(0xB8FF2E3A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * scale,
  );
  final nodeGlowPaint = Paint()..color = const Color(0x55FF3B47);
  final nodeCorePaint = Paint()..color = const Color(0xFFFFD8D6);
  for (var i = 0; i < 2; i++) {
    final th = time * 1.6 * speed + i * math.pi;
    final pos =
        Offset(math.cos(th) * baseR * 1.48, math.sin(th) * baseR * 0.72);
    canvas.drawCircle(pos, 4.6 * scale, nodeGlowPaint);
    canvas.drawCircle(pos, 2.0 * scale, nodeCorePaint);
  }
  canvas.restore();

  // 4. Counter-rotating secondary orbital ring
  canvas.save();
  canvas.rotate(-0.55 - time * 1.05 * speed);
  final orbit2Rect = Rect.fromCenter(
    center: Offset.zero,
    width: baseR * 0.78 * 2,
    height: baseR * 1.44 * 2,
  );
  canvas.drawOval(
    orbit2Rect,
    Paint()
      ..color = const Color(0x8CE50914)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * scale,
  );
  canvas.restore();

  // 5. Dual counter-rotating Ultron hexagonal containment lattice
  _drawPolygon(
    canvas,
    radius: side * 0.165,
    sides: 6,
    rotation: time * 0.45 * speed,
    color: const Color(0xB0FF5560),
    strokeWidth: 1.3 * scale,
  );
  _drawPolygon(
    canvas,
    radius: side * 0.125,
    sides: 6,
    rotation: -time * 0.65 * speed + math.pi / 6,
    color: const Color(0xCCFFA0A0),
    strokeWidth: 1.0 * scale,
  );

  canvas.restore();
}

void _drawPolygon(
  Canvas canvas, {
  required double radius,
  required int sides,
  required double rotation,
  required Color color,
  required double strokeWidth,
}) {
  canvas.save();
  canvas.rotate(rotation);
  final path = Path();
  for (var i = 0; i <= sides; i++) {
    final angle = (i / sides) * math.pi * 2;
    final pt = Offset(math.cos(angle) * radius, math.sin(angle) * radius);
    if (i == 0) {
      path.moveTo(pt.dx, pt.dy);
    } else {
      path.lineTo(pt.dx, pt.dy);
    }
  }
  path.close();
  canvas.drawPath(
    path,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth,
  );
  canvas.restore();
}
