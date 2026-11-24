import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

enum CoreStage { center, corner, hidden }

/// Renders the animated crimson 3D geodesic U.L.T.R.O.N. holographic core using
/// a runtime [FragmentProgram] volumetric glow layered with a real-time 3D
/// subdivided icosahedron wireframe mesh, luminous nodes, and tilted orbital
/// rings, or falling back cleanly to [CorePainter].
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
      _paintGeodesicCore(canvas, size, time, energy);
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
      Color(0xEEFFF0F2),
      Color(0xBBFF7A8C),
      Color(0x66B01A32),
      Color(0x28490812),
      Color(0x00080808),
    ],
    stops: [0.0, 0.14, 0.36, 0.68, 1.0],
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final side = size.shortestSide;
    final center = size.center(Offset.zero);
    final pulse = 1.0 + 0.025 * (0.35 + energy) * math.sin(time * 2.8);

    final auraRadius = side * 0.44 * pulse;
    final auraRect = Rect.fromCircle(center: center, radius: auraRadius);
    canvas.drawCircle(
      center,
      auraRadius,
      Paint()..shader = _auraGradient.createShader(auraRect),
    );

    // Subtle horizontal scanlines inside the geodesic core aura
    final scanR = side * 0.28;
    final scanPaint = Paint()
      ..color = const Color(0x14FF8A98)
      ..strokeWidth = 0.7;
    for (var dy = -scanR; dy <= scanR; dy += 4.2) {
      final chord = math.sqrt(math.max(0.0, scanR * scanR - dy * dy));
      canvas.drawLine(
        Offset(center.dx - chord, center.dy + dy),
        Offset(center.dx + chord, center.dy + dy),
        scanPaint,
      );
    }

    _paintGeodesicCore(canvas, size, time, energy);
  }

  @override
  bool shouldRepaint(covariant CorePainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.energy != energy;
}

class _Vec3 {
  const _Vec3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;

  _Vec3 normalized() {
    final len = math.sqrt(x * x + y * y + z * z);
    if (len == 0) return const _Vec3(0, 0, 1);
    return _Vec3(x / len, y / len, z / len);
  }
}

class _ProjectedVertex {
  const _ProjectedVertex(this.offset, this.z);
  final Offset offset;
  final double z;
}

class _GeodesicMesh {
  const _GeodesicMesh(this.vertices, this.edges);
  final List<_Vec3> vertices;
  final List<(int, int)> edges;
}

/// Precomputed 3D icosahedron (outer ghost shell) and frequency-2 subdivided
/// geodesic sphere (42 vertices, 120 edges) for zero-allocation 60 FPS rendering.
final _GeodesicMesh _outerIcoMesh = _buildIcosahedronMesh(subdivisions: 0);
final _GeodesicMesh _innerGeodesicMesh = _buildIcosahedronMesh(subdivisions: 1);

_GeodesicMesh _buildIcosahedronMesh({required int subdivisions}) {
  final t = (1.0 + math.sqrt(5.0)) / 2.0;
  final rawVerts = <_Vec3>[
    const _Vec3(-1, 0, 0), // replaced below
  ]..clear();

  final baseCoords = <(double, double, double)>[
    (-1, t, 0),
    (1, t, 0),
    (-1, -t, 0),
    (1, -t, 0),
    (0, -1, t),
    (0, 1, t),
    (0, -1, -t),
    (0, 1, -t),
    (t, 0, -1),
    (t, 0, 1),
    (-t, 0, -1),
    (-t, 0, 1),
  ];
  for (final c in baseCoords) {
    rawVerts.add(_Vec3(c.$1, c.$2, c.$3).normalized());
  }

  var faces = <(int, int, int)>[
    (0, 11, 5),
    (0, 5, 1),
    (0, 1, 7),
    (0, 7, 10),
    (0, 10, 11),
    (1, 5, 9),
    (5, 11, 4),
    (11, 10, 2),
    (10, 7, 6),
    (7, 1, 8),
    (3, 9, 4),
    (3, 4, 2),
    (3, 2, 6),
    (3, 6, 8),
    (3, 8, 9),
    (4, 9, 5),
    (2, 4, 11),
    (6, 2, 10),
    (8, 6, 7),
    (9, 8, 1),
  ];

  final verts = List<_Vec3>.from(rawVerts);
  for (var s = 0; s < subdivisions; s++) {
    final midpointCache = <int, int>{};
    int getMidpoint(int i1, int i2) {
      final a = math.min(i1, i2);
      final b = math.max(i1, i2);
      final key = (a << 16) | b;
      final existing = midpointCache[key];
      if (existing != null) return existing;
      final v1 = verts[a];
      final v2 = verts[b];
      final mid = _Vec3(
        (v1.x + v2.x) * 0.5,
        (v1.y + v2.y) * 0.5,
        (v1.z + v2.z) * 0.5,
      ).normalized();
      final idx = verts.length;
      verts.add(mid);
      midpointCache[key] = idx;
      return idx;
    }

    final nextFaces = <(int, int, int)>[];
    for (final f in faces) {
      final a = getMidpoint(f.$1, f.$2);
      final b = getMidpoint(f.$2, f.$3);
      final c = getMidpoint(f.$3, f.$1);
      nextFaces.add((f.$1, a, c));
      nextFaces.add((f.$2, b, a));
      nextFaces.add((f.$3, c, b));
      nextFaces.add((a, b, c));
    }
    faces = nextFaces;
  }

  final edgeSet = <int>{};
  final edges = <(int, int)>[];
  void addEdge(int i1, int i2) {
    final a = math.min(i1, i2);
    final b = math.max(i1, i2);
    final key = (a << 16) | b;
    if (edgeSet.add(key)) {
      edges.add((a, b));
    }
  }

  for (final f in faces) {
    addEdge(f.$1, f.$2);
    addEdge(f.$2, f.$3);
    addEdge(f.$3, f.$1);
  }

  return _GeodesicMesh(verts, edges);
}

List<_ProjectedVertex> _projectMesh(
  _GeodesicMesh mesh, {
  required double radius,
  required double rotX,
  required double rotY,
  required double rotZ,
}) {
  final cx = math.cos(rotX);
  final sx = math.sin(rotX);
  final cy = math.cos(rotY);
  final sy = math.sin(rotY);
  final cz = math.cos(rotZ);
  final sz = math.sin(rotZ);
  const focal = 3.4;

  return List<_ProjectedVertex>.generate(mesh.vertices.length, (i) {
    final v = mesh.vertices[i];
    // Rotate around Y
    final x1 = v.x * cy + v.z * sy;
    final y1 = v.y;
    final z1 = -v.x * sy + v.z * cy;
    // Rotate around X
    final x2 = x1;
    final y2 = y1 * cx - z1 * sx;
    final z2 = y1 * sx + z1 * cx;
    // Rotate around Z
    final x3 = x2 * cz - y2 * sz;
    final y3 = x2 * sz + y2 * cz;
    final z3 = z2;

    final perspective = focal / (focal - z3);
    return _ProjectedVertex(
      Offset(x3 * radius * perspective, y3 * radius * perspective),
      z3,
    );
  }, growable: false);
}

void _paintGeodesicCore(
  Canvas canvas,
  Size size,
  double time,
  double energy,
) {
  final side = size.shortestSide;
  if (side <= 0) return;
  final center = size.center(Offset.zero);
  final e = energy.clamp(0.0, 1.2);
  final speed = 0.28 + e * 0.55;
  final scale = (side / 200.0).clamp(0.32, 2.2);
  final breathe = 1.0 + 0.022 * (0.4 + e) * math.sin(time * 2.8);

  canvas.save();
  canvas.translate(center.dx, center.dy);

  // 1. Subtle floating micro-particles around the outer perimeter
  final particlePaint = Paint()..style = PaintingStyle.fill;
  for (var i = 0; i < 16; i++) {
    final seed = i * 1.61803398875;
    final angle = seed * 6.2831 + time * (0.04 + (i % 3) * 0.015);
    final dist = side * (0.37 + (i % 5) * 0.026);
    final alpha = (0.18 + 0.25 * (0.5 + 0.5 * math.sin(time * 1.4 + i)))
        .clamp(0.0, 0.55);
    particlePaint.color =
        const Color(0xFFFF8896).withValues(alpha: alpha);
    canvas.drawCircle(
      Offset(math.cos(angle) * dist, math.sin(angle) * dist),
      (i % 3 == 0 ? 1.15 : 0.75) * scale,
      particlePaint,
    );
  }

  // 2. Delicate tilted orbital rings & diagonal axis ellipse (matches reference photo)
  _paintOrbitalRings(canvas, side, time, speed, e, scale);

  // 3. Outer ghost wireframe geodesic cage (counter-rotating, faint burgundy-rose)
  final outerRadius = side * 0.315 * breathe;
  final outerProjected = _projectMesh(
    _outerIcoMesh,
    radius: outerRadius,
    rotX: -0.32 - time * 0.14 * speed,
    rotY: -time * 0.22 * speed,
    rotZ: 0.18,
  );
  final ghostEdgePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.65 * scale;
  for (final edge in _outerIcoMesh.edges) {
    final p1 = outerProjected[edge.$1];
    final p2 = outerProjected[edge.$2];
    final avgZ = (p1.z + p2.z) * 0.5;
    final depthT = ((avgZ + 1.0) * 0.5).clamp(0.0, 1.0);
    ghostEdgePaint.color = const Color(0xFF9C3848)
        .withValues(alpha: 0.08 + depthT * (0.18 + 0.08 * e));
    canvas.drawLine(p1.offset, p2.offset, ghostEdgePaint);
  }

  // 4. Primary 3D subdivided geodesic wireframe sphere (42 vertices, 120 edges)
  final innerRadius = side * 0.222 * breathe;
  final innerProjected = _projectMesh(
    _innerGeodesicMesh,
    radius: innerRadius,
    rotX: 0.28 + math.sin(time * 0.35 * speed) * 0.18,
    rotY: time * 0.42 * speed,
    rotZ: -0.14 + time * 0.09 * speed,
  );

  final backEdgePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.7 * scale;
  final frontGlowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 2.4 * scale;
  final frontEdgePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 0.95 * scale;

  // Back hemisphere edges first (translucent crystal depth)
  for (final edge in _innerGeodesicMesh.edges) {
    final p1 = innerProjected[edge.$1];
    final p2 = innerProjected[edge.$2];
    final avgZ = (p1.z + p2.z) * 0.5;
    if (avgZ >= 0.0) continue;
    final depthT = ((avgZ + 1.0)).clamp(0.0, 1.0);
    backEdgePaint.color = const Color(0xFF8C2535)
        .withValues(alpha: 0.14 + depthT * 0.24);
    canvas.drawLine(p1.offset, p2.offset, backEdgePaint);
  }

  // Front hemisphere edges on top (crisp luminous rose-crimson)
  for (final edge in _innerGeodesicMesh.edges) {
    final p1 = innerProjected[edge.$1];
    final p2 = innerProjected[edge.$2];
    final avgZ = (p1.z + p2.z) * 0.5;
    if (avgZ < 0.0) continue;
    final depthT = avgZ.clamp(0.0, 1.0);

    frontGlowPaint.color = const Color(0xFFF10D28)
        .withValues(alpha: 0.10 + depthT * (0.18 + 0.12 * e));
    canvas.drawLine(p1.offset, p2.offset, frontGlowPaint);

    frontEdgePaint.color = Color.lerp(
      const Color(0xFFB83C4E),
      const Color(0xFFFFB5C0),
      (depthT * 0.85 + e * 0.15).clamp(0.0, 1.0),
    )!
        .withValues(alpha: 0.52 + depthT * 0.44);
    canvas.drawLine(p1.offset, p2.offset, frontEdgePaint);
  }

  // 5. Luminous vertex nodes (bright white-pink stars on front intersections)
  final nodeHaloPaint = Paint()..style = PaintingStyle.fill;
  final nodeCorePaint = Paint()..style = PaintingStyle.fill;
  for (final p in innerProjected) {
    if (p.z < -0.15) {
      nodeCorePaint.color = const Color(0x55D46878);
      canvas.drawCircle(p.offset, 0.85 * scale, nodeCorePaint);
      continue;
    }
    final depthT = ((p.z + 0.15) / 1.15).clamp(0.0, 1.0);
    nodeHaloPaint.color = const Color(0xFFFF4D66)
        .withValues(alpha: 0.16 + depthT * (0.32 + 0.16 * e));
    canvas.drawCircle(p.offset, (2.2 + depthT * 1.8) * scale, nodeHaloPaint);

    nodeCorePaint.color = Color.lerp(
      const Color(0xFFFFA8B4),
      const Color(0xFFFFFFFF),
      depthT,
    )!
        .withValues(alpha: 0.55 + depthT * 0.45);
    canvas.drawCircle(p.offset, (0.9 + depthT * 0.85) * scale, nodeCorePaint);
  }

  canvas.restore();
}

void _paintOrbitalRings(
  Canvas canvas,
  double side,
  double time,
  double speed,
  double energy,
  double scale,
) {
  // Subtle outermost faint circular halo
  canvas.drawCircle(
    Offset.zero,
    side * 0.445,
    Paint()
      ..color = const Color(0x22A83C4C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7 * scale,
  );

  // Primary crisp tilted orbital ellipse
  canvas.save();
  canvas.rotate(-0.42 + time * 0.12 * speed);
  final ring1 = Rect.fromCenter(
    center: Offset.zero,
    width: side * 0.82,
    height: side * 0.69,
  );
  canvas.drawOval(
    ring1,
    Paint()
      ..color = Color.lerp(
        const Color(0x88D96A7A),
        const Color(0xDDFFA6B2),
        (energy * 0.55).clamp(0.0, 1.0),
      )!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15 * scale,
  );
  canvas.restore();

  // Secondary counter-tilted thin orbital ring
  canvas.save();
  canvas.rotate(0.58 - time * 0.09 * speed);
  final ring2 = Rect.fromCenter(
    center: Offset.zero,
    width: side * 0.76,
    height: side * 0.63,
  );
  canvas.drawOval(
    ring2,
    Paint()
      ..color = const Color(0x4CB84A5A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.85 * scale,
  );
  canvas.restore();

  // Signature razor-thin diagonal orbital axis ellipse (top-left to bottom-right)
  canvas.save();
  canvas.rotate(0.78 + math.sin(time * 0.18 * speed) * 0.04);
  final diagRing = Rect.fromCenter(
    center: Offset.zero,
    width: side * 0.94,
    height: side * 0.032,
  );
  canvas.drawOval(
    diagRing,
    Paint()
      ..color = Color.lerp(
        const Color(0x66D66272),
        const Color(0xBBFFAAB6),
        (energy * 0.5).clamp(0.0, 1.0),
      )!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9 * scale,
  );
  canvas.restore();
}
