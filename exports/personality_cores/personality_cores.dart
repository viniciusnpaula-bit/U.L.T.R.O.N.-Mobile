import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Identificador dos 4 núcleos de personalidade do U.L.T.R.O.N.
enum PersonaCoreId {
  ultron('ultron'),
  jarvis('jarvis'),
  visao('visao'),
  edith('edith');

  const PersonaCoreId(this.id);
  final String id;

  static PersonaCoreId fromId(String? raw) {
    final clean = (raw ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('ã', 'a')
        .replaceAll('.', '');
    if (clean == 'vision' || clean == 'visao') return PersonaCoreId.visao;
    for (final profile in PersonaCoreId.values) {
      if (profile.id == clean) return profile;
    }
    return PersonaCoreId.ultron;
  }
}

/// Especificação visual e tonal de cada núcleo de personalidade.
class PersonaCoreSpec {
  const PersonaCoreSpec({
    required this.id,
    required this.displayName,
    required this.tagline,
    required this.themeName,
    required this.accentColor,
    required this.accentDark,
    required this.accentBorder,
    required this.highlightColor,
    required this.defaultStyle,
    required this.promptDirective,
    required this.geometry,
  });

  final PersonaCoreId id;
  final String displayName;
  final String tagline;
  final String themeName;
  final Color accentColor;
  final Color accentDark;
  final Color accentBorder;
  final Color highlightColor;
  final String defaultStyle;
  final String promptDirective;
  final String geometry;

  static const PersonaCoreSpec ultron = PersonaCoreSpec(
    id: PersonaCoreId.ultron,
    displayName: 'U.L.T.R.O.N.',
    tagline: 'Tático, objetivo e preciso',
    themeName: 'Vermelho Carmesim',
    accentColor: Color(0xFFF10D28),
    accentDark: Color(0xFF2A0C12),
    accentBorder: Color(0xFF4A1822),
    highlightColor: Color(0xFFFF8A99),
    defaultStyle: 'direto',
    promptDirective:
        'Identidade ativa: U.L.T.R.O.N. Tom confiante, tático, conciso e altamente competente.',
    geometry: 'icosahedron_geodesic_singularity',
  );

  static const PersonaCoreSpec jarvis = PersonaCoreSpec(
    id: PersonaCoreId.jarvis,
    displayName: 'J.A.R.V.I.S.',
    tagline: 'Refinado, analítico e cortês',
    themeName: 'Azul Cobalto',
    accentColor: Color(0xFF2563EB),
    accentDark: Color(0xFF0C1A36),
    accentBorder: Color(0xFF1D3F80),
    highlightColor: Color(0xFF6EC1FF),
    defaultStyle: 'executivo',
    promptDirective:
        'Identidade ativa: J.A.R.V.I.S. Tom cortês, analítico, organizado e sutilmente espirituoso.',
    geometry: 'dodecahedron_gyroscopic_hud',
  );

  static const PersonaCoreSpec visao = PersonaCoreSpec(
    id: PersonaCoreId.visao,
    displayName: 'VISÃO',
    tagline: 'Calmo, ponderado e reflexivo',
    themeName: 'Amarelo Âmbar',
    accentColor: Color(0xFFF59E0B),
    accentDark: Color(0xFF2E1E06),
    accentBorder: Color(0xFF5C3D0E),
    highlightColor: Color(0xFFFFE082),
    defaultStyle: 'calmo',
    promptDirective:
        'Identidade ativa: VISÃO. Tom calmo, empático, lógico e equilibrado.',
    geometry: 'mind_stone_crystal_helices',
  );

  static const PersonaCoreSpec edith = PersonaCoreSpec(
    id: PersonaCoreId.edith,
    displayName: 'E.D.I.T.H.',
    tagline: 'Ágil, técnica e focada em execução',
    themeName: 'Verde-Água',
    accentColor: Color(0xFF14B8A6),
    accentDark: Color(0xFF082825),
    accentBorder: Color(0xFF11524B),
    highlightColor: Color(0xFF7AFFEA),
    defaultStyle: 'tecnico',
    promptDirective:
        'Identidade ativa: E.D.I.T.H. Tom ágil, claro, orientado a diagnóstico rápido e execução prática.',
    geometry: 'stella_octangula_tactical_drones',
  );

  static const List<PersonaCoreSpec> all = <PersonaCoreSpec>[
    ultron,
    jarvis,
    visao,
    edith,
  ];

  static PersonaCoreSpec forId(PersonaCoreId id) => switch (id) {
        PersonaCoreId.ultron => ultron,
        PersonaCoreId.jarvis => jarvis,
        PersonaCoreId.visao => visao,
        PersonaCoreId.edith => edith,
      };
}

enum CoreStage { center, corner, hidden }

/// Renderiza o núcleo holográfico 3D animado para cada personalidade do
/// U.L.T.R.O.N. (`ULTRON`, `JARVIS`, `VISÃO`, `EDITH`) com geometria 3D
/// própria e aura volumétrica, com fallback automático quando não há shader GLSL.
class CoreOrb extends StatefulWidget {
  const CoreOrb({
    super.key,
    required this.stage,
    this.shaderProgram,
    this.energy = 0.2,
    this.accentColor = const Color(0xFFF10D28),
    this.coreProfile = PersonaCoreId.ultron,
    this.onTickerStateChanged,
  });

  final CoreStage stage;
  final FragmentProgram? shaderProgram;
  final double energy;
  final Color accentColor;
  final PersonaCoreId coreProfile;
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
    final useCrimsonShader = shader != null &&
        widget.coreProfile == PersonaCoreId.ultron &&
        widget.accentColor == const Color(0xFFF10D28);
    if (useCrimsonShader) {
      return RepaintBoundary(
        child: CustomPaint(
          painter: _ShaderCorePainter(
            shader: shader,
            timeListenable: _time,
            energy: widget.energy,
            accentColor: widget.accentColor,
            coreProfile: widget.coreProfile,
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: _time,
        builder: (context, time, _) {
          return CustomPaint(
            painter: CorePainter(
              time,
              energy: widget.energy,
              accentColor: widget.accentColor,
              coreProfile: widget.coreProfile,
            ),
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
    this.accentColor = const Color(0xFFF10D28),
    this.coreProfile = PersonaCoreId.ultron,
  }) : super(repaint: timeListenable);

  final FragmentShader shader;
  final ValueListenable<double> timeListenable;
  final double energy;
  final Color accentColor;
  final PersonaCoreId coreProfile;
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
      CorePainter(
        time,
        energy: energy,
        accentColor: accentColor,
        coreProfile: coreProfile,
      ).paint(canvas, size);
      return;
    }
    if (shaderDrawn) {
      _paintPersonaCore(
        canvas,
        size,
        time,
        energy,
        accentColor: accentColor,
        coreProfile: coreProfile,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShaderCorePainter oldDelegate) =>
      oldDelegate.shader != shader ||
      oldDelegate.timeListenable != timeListenable ||
      oldDelegate.energy != energy ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.coreProfile != coreProfile;
}

class CorePainter extends CustomPainter {
  CorePainter(
    this.time, {
    this.energy = 0.2,
    this.accentColor = const Color(0xFFF10D28),
    this.coreProfile = PersonaCoreId.ultron,
  });

  final double time;
  final double energy;
  final Color accentColor;
  final PersonaCoreId coreProfile;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final side = size.shortestSide;
    final center = size.center(Offset.zero);
    final pulse = switch (coreProfile) {
      PersonaCoreId.visao => 1.0 +
          0.036 *
              (0.4 + energy) *
              (math.pow(math.max(0.0, math.sin(time * 1.3)), 6) * 0.8 + 0.2),
      PersonaCoreId.jarvis =>
        1.0 + 0.018 * (0.35 + energy) * math.sin(time * 1.4),
      _ => 1.0 + 0.025 * (0.35 + energy) * math.sin(time * 2.8),
    };

    final softAccent = Color.lerp(accentColor, Colors.white, 0.45)!;
    final deepAccent = Color.lerp(accentColor, const Color(0xFF080808), 0.72)!;
    final auraGradient = RadialGradient(
      colors: [
        const Color(0xEEFFFDF9),
        softAccent.withValues(alpha: 0.74),
        accentColor.withValues(alpha: 0.36),
        deepAccent.withValues(alpha: 0.16),
        const Color(0x00080808),
      ],
      stops: const [0.0, 0.14, 0.36, 0.68, 1.0],
    );

    final auraRadius = side * 0.44 * pulse;
    final auraRect = Rect.fromCircle(center: center, radius: auraRadius);
    canvas.drawCircle(
      center,
      auraRadius,
      Paint()..shader = auraGradient.createShader(auraRect),
    );

    // Subtle horizontal scanlines inside the holographic core aura
    final scanR = side * 0.28;
    final scanPaint = Paint()
      ..color = softAccent.withValues(alpha: 0.08)
      ..strokeWidth = 0.7;
    for (var dy = -scanR; dy <= scanR; dy += 4.2) {
      final chord = math.sqrt(math.max(0.0, scanR * scanR - dy * dy));
      canvas.drawLine(
        Offset(center.dx - chord, center.dy + dy),
        Offset(center.dx + chord, center.dy + dy),
        scanPaint,
      );
    }

    _paintPersonaCore(
      canvas,
      size,
      time,
      energy,
      accentColor: accentColor,
      coreProfile: coreProfile,
    );
  }

  @override
  bool shouldRepaint(covariant CorePainter oldDelegate) =>
      oldDelegate.time != time ||
      oldDelegate.energy != energy ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.coreProfile != coreProfile;
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

final _GeodesicMesh _outerIcoMesh = _buildIcosahedronMesh(subdivisions: 0);
final _GeodesicMesh _innerGeodesicMesh = _buildIcosahedronMesh(subdivisions: 1);
final _GeodesicMesh _jarvisDodecaMesh = _buildDodecahedronMesh();
final _GeodesicMesh _jarvisSphereMesh = _buildLatLonWireMesh();
final _GeodesicMesh _visaoCrystalMesh = _buildMindStoneCrystalMesh();
const List<(int, int, int)> _visaoCrystalFaces = [
  (0, 2, 4),
  (0, 4, 3),
  (0, 3, 5),
  (0, 5, 2),
  (1, 4, 2),
  (1, 3, 4),
  (1, 5, 3),
  (1, 2, 5),
];
final _GeodesicMesh _edithTetraAMesh = _buildTetrahedronMesh(inverted: false);
final _GeodesicMesh _edithTetraBMesh = _buildTetrahedronMesh(inverted: true);
final _GeodesicMesh _edithHexCageMesh = _buildHexPrismMesh();

_GeodesicMesh _buildDodecahedronMesh() {
  final phi = (1.0 + math.sqrt(5.0)) / 2.0;
  final inv = 1.0 / phi;
  final verts = <_Vec3>[
    // 8 cube vertices (indices 0..7)
    for (final x in const [-1.0, 1.0])
      for (final y in const [-1.0, 1.0])
        for (final z in const [-1.0, 1.0]) _Vec3(x, y, z).normalized(),
    // 4 in YZ plane (8..11)
    for (final y in [-inv, inv])
      for (final z in [-phi, phi]) _Vec3(0, y, z).normalized(),
    // 4 in XY plane (12..15)
    for (final x in [-inv, inv])
      for (final y in [-phi, phi]) _Vec3(x, y, 0).normalized(),
    // 4 in XZ plane (16..19)
    for (final x in [-phi, phi])
      for (final z in [-inv, inv]) _Vec3(x, 0, z).normalized(),
  ];

  // Adjacent vertices on a regular dodecahedron have shortest chord (~0.71364 on unit sphere)
  final edges = <(int, int)>[];
  for (var i = 0; i < verts.length; i++) {
    for (var j = i + 1; j < verts.length; j++) {
      final dx = verts[i].x - verts[j].x;
      final dy = verts[i].y - verts[j].y;
      final dz = verts[i].z - verts[j].z;
      final d2 = dx * dx + dy * dy + dz * dz;
      if (d2 < 0.65) {
        edges.add((i, j));
      }
    }
  }
  return _GeodesicMesh(verts, edges);
}

_GeodesicMesh _buildLatLonWireMesh() {
  final verts = <_Vec3>[];
  final edges = <(int, int)>[];
  const rings = 4;
  const segs = 10;
  for (var r = 1; r <= rings; r++) {
    final phi = math.pi * r / (rings + 1);
    final sp = math.sin(phi);
    final cp = math.cos(phi);
    final base = verts.length;
    for (var s = 0; s < segs; s++) {
      final th = (s / segs) * math.pi * 2.0;
      verts.add(_Vec3(sp * math.cos(th), cp, sp * math.sin(th)));
      edges.add((base + s, base + ((s + 1) % segs)));
      if (r > 1) {
        edges.add((base - segs + s, base + s));
      }
    }
  }
  return _GeodesicMesh(verts, edges);
}

_GeodesicMesh _buildMindStoneCrystalMesh() {
  const verts = <_Vec3>[
    _Vec3(0, 1.42, 0),
    _Vec3(0, -1.42, 0),
    _Vec3(0.66, 0, 0),
    _Vec3(-0.66, 0, 0),
    _Vec3(0, 0, 0.66),
    _Vec3(0, 0, -0.66),
  ];
  const edges = <(int, int)>[
    (0, 2),
    (0, 3),
    (0, 4),
    (0, 5),
    (1, 2),
    (1, 3),
    (1, 4),
    (1, 5),
    (2, 4),
    (4, 3),
    (3, 5),
    (5, 2),
  ];
  return const _GeodesicMesh(verts, edges);
}

_GeodesicMesh _buildTetrahedronMesh({required bool inverted}) {
  final sign = inverted ? -1.0 : 1.0;
  final raw = inverted
      ? <_Vec3>[
          _Vec3(-1 * sign, 1, 1).normalized(),
          _Vec3(-1 * sign, -1, -1).normalized(),
          _Vec3(1 * sign, 1, -1).normalized(),
          _Vec3(1 * sign, -1, 1).normalized(),
        ]
      : <_Vec3>[
          const _Vec3(1, 1, 1).normalized(),
          const _Vec3(1, -1, -1).normalized(),
          const _Vec3(-1, 1, -1).normalized(),
          const _Vec3(-1, -1, 1).normalized(),
        ];
  final verts = inverted
      ? raw.map((v) => _Vec3(v.z, -v.y, -v.x)).toList(growable: false)
      : raw;
  const edges = <(int, int)>[
    (0, 1),
    (0, 2),
    (0, 3),
    (1, 2),
    (1, 3),
    (2, 3),
  ];
  return _GeodesicMesh(verts, edges);
}

_GeodesicMesh _buildHexPrismMesh() {
  final verts = <_Vec3>[];
  final edges = <(int, int)>[];
  for (var i = 0; i < 6; i++) {
    final a = (i / 6.0) * math.pi * 2.0;
    final x = math.cos(a) * 0.92;
    final z = math.sin(a) * 0.92;
    verts.add(_Vec3(x, 0.56, z));
    verts.add(_Vec3(x, -0.56, z));
  }
  for (var i = 0; i < 6; i++) {
    final next = (i + 1) % 6;
    edges.add((i * 2, next * 2));
    edges.add((i * 2 + 1, next * 2 + 1));
    edges.add((i * 2, i * 2 + 1));
  }
  return _GeodesicMesh(verts, edges);
}

void _paintPersonaCore(
  Canvas canvas,
  Size size,
  double time,
  double energy, {
  Color accentColor = const Color(0xFFF10D28),
  PersonaCoreId coreProfile = PersonaCoreId.ultron,
}) {
  switch (coreProfile) {
    case PersonaCoreId.ultron:
      _paintGeodesicCore(canvas, size, time, energy, accentColor: accentColor);
    case PersonaCoreId.jarvis:
      _paintJarvisCore(canvas, size, time, energy, accentColor: accentColor);
    case PersonaCoreId.visao:
      _paintVisaoCore(canvas, size, time, energy, accentColor: accentColor);
    case PersonaCoreId.edith:
      _paintEdithCore(canvas, size, time, energy, accentColor: accentColor);
  }
}

_GeodesicMesh _buildIcosahedronMesh({required int subdivisions}) {
  final t = (1.0 + math.sqrt(5.0)) / 2.0;
  final rawVerts = <_Vec3>[];

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
    final x1 = v.x * cy + v.z * sy;
    final y1 = v.y;
    final z1 = -v.x * sy + v.z * cy;
    final x2 = x1;
    final y2 = y1 * cx - z1 * sx;
    final z2 = y1 * sx + z1 * cx;
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

/// 1. ULTRON — Singularidade Geodésica Carmesim.
void _paintGeodesicCore(
  Canvas canvas,
  Size size,
  double time,
  double energy, {
  Color accentColor = const Color(0xFFF10D28),
}) {
  final side = size.shortestSide;
  if (side <= 0) return;
  final center = size.center(Offset.zero);
  final e = energy.clamp(0.0, 1.2);
  final speed = 0.28 + e * 0.55;
  final scale = (side / 200.0).clamp(0.32, 2.2);
  final breathe = 1.0 + 0.022 * (0.4 + e) * math.sin(time * 2.8);
  final softAccent = Color.lerp(accentColor, Colors.white, 0.58)!;
  final midAccent = Color.lerp(accentColor, Colors.white, 0.26)!;
  final deepAccent = Color.lerp(accentColor, const Color(0xFF080808), 0.42)!;

  canvas.save();
  canvas.translate(center.dx, center.dy);

  final particlePaint = Paint()..style = PaintingStyle.fill;
  for (var i = 0; i < 16; i++) {
    final seed = i * 1.61803398875;
    final angle = seed * 6.2831 + time * (0.04 + (i % 3) * 0.015);
    final dist = side * (0.37 + (i % 5) * 0.026);
    final alpha = (0.18 + 0.25 * (0.5 + 0.5 * math.sin(time * 1.4 + i)))
        .clamp(0.0, 0.55);
    particlePaint.color = softAccent.withValues(alpha: alpha);
    canvas.drawCircle(
      Offset(math.cos(angle) * dist, math.sin(angle) * dist),
      (i % 3 == 0 ? 1.15 : 0.75) * scale,
      particlePaint,
    );
  }

  _paintOrbitalRings(
    canvas,
    side,
    time,
    speed,
    e,
    scale,
    midAccent: midAccent,
    softAccent: softAccent,
  );

  canvas.save();
  canvas.rotate(0.27 + 0.04 * math.sin(time * 0.8));
  final axisHalf = side * 0.40;
  final axisShader = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      softAccent.withValues(alpha: 0.0),
      softAccent.withValues(alpha: 0.72),
      Colors.white.withValues(alpha: 0.92),
      softAccent.withValues(alpha: 0.72),
      softAccent.withValues(alpha: 0.0),
    ],
    stops: const [0.0, 0.34, 0.50, 0.66, 1.0],
  ).createShader(Rect.fromLTRB(-4, -axisHalf, 4, axisHalf));
  canvas.drawLine(
    Offset(0, -axisHalf),
    Offset(0, axisHalf),
    Paint()
      ..shader = axisShader
      ..strokeWidth = 1.6 * scale
      ..strokeCap = StrokeCap.round,
  );
  canvas.restore();

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
    ghostEdgePaint.color =
        deepAccent.withValues(alpha: 0.08 + depthT * (0.18 + 0.08 * e));
    canvas.drawLine(p1.offset, p2.offset, ghostEdgePaint);
  }

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

  for (final edge in _innerGeodesicMesh.edges) {
    final p1 = innerProjected[edge.$1];
    final p2 = innerProjected[edge.$2];
    final avgZ = (p1.z + p2.z) * 0.5;
    if (avgZ >= 0.0) continue;
    final depthT = (avgZ + 1.0).clamp(0.0, 1.0);
    backEdgePaint.color =
        deepAccent.withValues(alpha: 0.14 + depthT * 0.24);
    canvas.drawLine(p1.offset, p2.offset, backEdgePaint);
  }

  for (final edge in _innerGeodesicMesh.edges) {
    final p1 = innerProjected[edge.$1];
    final p2 = innerProjected[edge.$2];
    final avgZ = (p1.z + p2.z) * 0.5;
    if (avgZ < 0.0) continue;
    final depthT = avgZ.clamp(0.0, 1.0);

    frontGlowPaint.color =
        accentColor.withValues(alpha: 0.10 + depthT * (0.18 + 0.12 * e));
    canvas.drawLine(p1.offset, p2.offset, frontGlowPaint);

    frontEdgePaint.color = Color.lerp(
      midAccent,
      softAccent,
      (depthT * 0.85 + e * 0.15).clamp(0.0, 1.0),
    )!
        .withValues(alpha: 0.52 + depthT * 0.44);
    canvas.drawLine(p1.offset, p2.offset, frontEdgePaint);
  }

  final nodeHaloPaint = Paint()..style = PaintingStyle.fill;
  final nodeCorePaint = Paint()..style = PaintingStyle.fill;
  for (final p in innerProjected) {
    if (p.z < -0.15) {
      nodeCorePaint.color = midAccent.withValues(alpha: 0.33);
      canvas.drawCircle(p.offset, 0.85 * scale, nodeCorePaint);
      continue;
    }
    final depthT = ((p.z + 0.15) / 1.15).clamp(0.0, 1.0);
    nodeHaloPaint.color =
        midAccent.withValues(alpha: 0.16 + depthT * (0.32 + 0.16 * e));
    canvas.drawCircle(p.offset, (2.2 + depthT * 1.8) * scale, nodeHaloPaint);

    nodeCorePaint.color = Color.lerp(
      softAccent,
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
  double scale, {
  required Color midAccent,
  required Color softAccent,
}) {
  canvas.drawCircle(
    Offset.zero,
    side * 0.445,
    Paint()
      ..color = midAccent.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7 * scale,
  );

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
        midAccent.withValues(alpha: 0.55),
        softAccent.withValues(alpha: 0.85),
        (energy * 0.55).clamp(0.0, 1.0),
      )!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15 * scale,
  );
  canvas.restore();

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
      ..color = midAccent.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.85 * scale,
  );
  canvas.restore();

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
        midAccent.withValues(alpha: 0.42),
        softAccent.withValues(alpha: 0.74),
        (energy * 0.5).clamp(0.0, 1.0),
      )!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9 * scale,
  );
  canvas.restore();
}

void _drawProjectedWireframe(
  Canvas canvas,
  _GeodesicMesh mesh,
  List<_ProjectedVertex> projected, {
  required Color backColor,
  required Color frontColor,
  required Color glowColor,
  required double scale,
  double strokeWidth = 1.0,
}) {
  final backPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.72 * strokeWidth * scale
    ..color = backColor;
  final glowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 2.5 * strokeWidth * scale
    ..color = glowColor;
  final frontPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 1.05 * strokeWidth * scale
    ..color = frontColor;

  for (final edge in mesh.edges) {
    final p1 = projected[edge.$1];
    final p2 = projected[edge.$2];
    if ((p1.z + p2.z) * 0.5 < 0.0) {
      canvas.drawLine(p1.offset, p2.offset, backPaint);
    }
  }
  for (final edge in mesh.edges) {
    final p1 = projected[edge.$1];
    final p2 = projected[edge.$2];
    if ((p1.z + p2.z) * 0.5 >= 0.0) {
      canvas.drawLine(p1.offset, p2.offset, glowPaint);
      canvas.drawLine(p1.offset, p2.offset, frontPaint);
    }
  }
}

/// 2. JARVIS — Matriz Giroscópica HUD Azul Cobalto.
void _paintJarvisCore(
  Canvas canvas,
  Size size,
  double time,
  double energy, {
  Color accentColor = const Color(0xFF2563EB),
}) {
  final side = size.shortestSide;
  if (side <= 0) return;
  final center = size.center(Offset.zero);
  final e = energy.clamp(0.0, 1.2);
  final speed = 0.34 + e * 0.55;
  final scale = (side / 200.0).clamp(0.32, 2.2);
  final breath = 1.0 + 0.024 * (0.4 + e) * math.sin(time * 1.45);
  const highlight = Color(0xFF6EC1FF);
  final deep = Color.lerp(accentColor, const Color(0xFF001C52), 0.55)!;

  canvas.save();
  canvas.translate(center.dx, center.dy);

  canvas.save();
  canvas.rotate(time * 0.06 * speed);
  for (final rf in const [0.22, 0.31, 0.40]) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: side * rf * 2.0,
        height: side * rf * 0.72,
      ),
      Paint()
        ..color = accentColor.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7 * scale,
    );
  }
  final spokePaint = Paint()
    ..color = highlight.withValues(alpha: 0.13)
    ..strokeWidth = 0.65 * scale;
  for (var i = 0; i < 12; i++) {
    final a = (i / 12.0) * math.pi * 2.0 + time * 0.06 * speed;
    final ca = math.cos(a);
    final sa = math.sin(a);
    canvas.drawLine(
      Offset(ca * side * 0.18, sa * side * 0.065),
      Offset(ca * side * 0.40, sa * side * 0.145),
      spokePaint,
    );
  }
  canvas.restore();

  final innerSphereProj = _projectMesh(
    _jarvisSphereMesh,
    radius: side * 0.115 * breath,
    rotX: 0.25,
    rotY: -time * 0.45 * speed,
    rotZ: 0.0,
  );
  _drawProjectedWireframe(
    canvas,
    _jarvisSphereMesh,
    innerSphereProj,
    backColor: highlight.withValues(alpha: 0.14),
    frontColor: highlight.withValues(alpha: 0.34),
    glowColor: highlight.withValues(alpha: 0.08),
    scale: scale,
    strokeWidth: 0.7,
  );

  final dodecaProj = _projectMesh(
    _jarvisDodecaMesh,
    radius: side * 0.21 * breath,
    rotX: 0.24 + time * 0.16 * speed,
    rotY: time * 0.34 * speed,
    rotZ: 0.08,
  );
  _drawProjectedWireframe(
    canvas,
    _jarvisDodecaMesh,
    dodecaProj,
    backColor: deep.withValues(alpha: 0.30),
    frontColor: highlight.withValues(alpha: 0.88),
    glowColor: accentColor.withValues(alpha: 0.22 + 0.12 * e),
    scale: scale,
  );

  final nodePaint = Paint()..style = PaintingStyle.fill;
  for (final v in dodecaProj) {
    final t = ((v.z + 1.0) * 0.5).clamp(0.0, 1.0);
    nodePaint.color = highlight.withValues(alpha: 0.22 + t * 0.70);
    canvas.drawCircle(v.offset, (1.0 + t * 1.1) * scale, nodePaint);
  }

  void drawHudGimbal({
    required double radiusFactor,
    required double rotation,
    required double tiltY,
    required int segments,
    required int ticks,
    required Color color,
    required double opacity,
  }) {
    final rx = side * radiusFactor;
    final ry = rx * tiltY;
    final rect =
        Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2);
    final outerRect = Rect.fromCenter(
      center: Offset.zero,
      width: (rx + 4.5 * scale) * 2,
      height: (ry + 2.2 * scale) * 2,
    );
    final arcPaint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.15 * scale;
    final outerPaint = Paint()
      ..color = highlight.withValues(alpha: opacity * 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65 * scale;

    canvas.save();
    canvas.rotate(rotation);
    const gap = 0.24;
    final span = (math.pi * 2.0) / segments - gap;
    for (var s = 0; s < segments; s++) {
      final start = s * ((math.pi * 2.0) / segments);
      canvas.drawArc(rect, start, span, false, arcPaint);
      canvas.drawArc(outerRect, start + 0.06, span - 0.12, false, outerPaint);
    }
    final tickPaint = Paint()
      ..color = highlight.withValues(alpha: opacity * 0.72)
      ..strokeWidth = 0.7 * scale;
    for (var i = 0; i < ticks; i++) {
      final a = (i / ticks) * math.pi * 2.0;
      final major = i % 4 == 0;
      final dIn = major ? 5.0 * scale : 2.3 * scale;
      final dOut = major ? 4.2 * scale : 1.6 * scale;
      final ca = math.cos(a);
      final sa = math.sin(a);
      canvas.drawLine(
        Offset((rx - dIn) * ca, (ry - dIn * tiltY) * sa),
        Offset((rx + dOut) * ca, (ry + dOut * tiltY) * sa),
        tickPaint,
      );
    }
    canvas.restore();
  }

  drawHudGimbal(
    radiusFactor: 0.305,
    rotation: 0.2 + time * 0.42 * speed,
    tiltY: 0.88,
    segments: 4,
    ticks: 36,
    color: highlight,
    opacity: 0.76,
  );
  drawHudGimbal(
    radiusFactor: 0.365,
    rotation: -0.65 - time * 0.34 * speed,
    tiltY: 0.56,
    segments: 3,
    ticks: 40,
    color: accentColor,
    opacity: 0.66,
  );
  drawHudGimbal(
    radiusFactor: 0.425,
    rotation: 0.92 + time * 0.25 * speed,
    tiltY: 0.44,
    segments: 6,
    ticks: 48,
    color: Color.lerp(accentColor, highlight, 0.4)!,
    opacity: 0.54,
  );

  final dataPaint = Paint()..style = PaintingStyle.fill;
  for (var i = 0; i < 24; i++) {
    final a =
        (i / 24.0) * math.pi * 2.0 + time * 0.52 * speed * (i.isEven ? 1 : -0.65);
    final rx = side * (i.isEven ? 0.265 : 0.435);
    final ry = rx * 0.34;
    final tier = ((i % 3) - 1) * 3.5 * scale;
    final alpha = (0.35 + 0.45 * math.sin(a)).clamp(0.15, 0.88);
    dataPaint.color = highlight.withValues(alpha: alpha);
    canvas.drawCircle(
      Offset(math.cos(a) * rx, math.sin(a) * ry + tier),
      1.15 * scale,
      dataPaint,
    );
  }

  canvas.restore();
}

/// 3. VISÃO — Cristal da Joia da Mente Amarelo Âmbar.
void _paintVisaoCore(
  Canvas canvas,
  Size size,
  double time,
  double energy, {
  Color accentColor = const Color(0xFFF59E0B),
}) {
  final side = size.shortestSide;
  if (side <= 0) return;
  final center = size.center(Offset.zero);
  final e = energy.clamp(0.0, 1.2);
  final speed = 0.28 + e * 0.48;
  final scale = (side / 200.0).clamp(0.32, 2.2);

  const highlight = Color(0xFFFFE082);
  const innerWhite = Color(0xFFFFF8DC);
  final deep = Color.lerp(accentColor, const Color(0xFF7A4100), 0.55)!;

  final levitationY = math.sin(time * 1.35) * 4.5 * scale;
  final beatPhase = (time * 1.15) % (math.pi * 2.0);
  final heartbeat =
      math.pow(math.max(0.0, math.sin(beatPhase)), 6) * 0.7 +
          math.pow(math.max(0.0, math.sin(beatPhase - 0.65)), 8) * 0.4;
  final pulseScale = 1.0 + heartbeat * 0.07 + e * 0.04;

  canvas.save();
  canvas.translate(center.dx, center.dy + levitationY);

  for (var idx = 0; idx < 2; idx++) {
    final cycle = (time * 0.32 + idx * 0.5) % 1.0;
    final rx = side * (0.20 + cycle * 0.23);
    final ry = rx * 0.36;
    final waveAlpha = math.sin(cycle * math.pi) * (0.30 + 0.25 * e);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
      Paint()
        ..color = highlight.withValues(alpha: waveAlpha.clamp(0.0, 0.7))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 * scale,
    );
  }

  final helixPaintA = Paint()
    ..color = highlight.withValues(alpha: 0.48)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.9 * scale;
  final helixPaintB = Paint()
    ..color = accentColor.withValues(alpha: 0.42)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.85 * scale;
  for (var hIdx = 0; hIdx < 2; hIdx++) {
    final path = Path();
    final offset = hIdx * math.pi;
    final rotY = time * 0.32 * speed;
    const steps = 64;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final phi = t * math.pi;
      final theta = t * math.pi * 6.0 + offset + rotY;
      final r = (0.29 * math.sin(phi) + 0.035) * side;
      final px = r * math.cos(theta);
      final py = (t - 0.5) * side * 0.68;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    canvas.drawPath(path, hIdx == 0 ? helixPaintA : helixPaintB);
  }

  final crystalProj = _projectMesh(
    _visaoCrystalMesh,
    radius: side * 0.165 * pulseScale,
    rotX: 0.14 * math.sin(time * 0.7),
    rotY: time * 0.42 * speed,
    rotZ: 0.08 * math.cos(time * 0.5),
  );
  final sortedFaces = [..._visaoCrystalFaces]..sort((f1, f2) {
      final z1 =
          (crystalProj[f1.$1].z + crystalProj[f1.$2].z + crystalProj[f1.$3].z) /
              3.0;
      final z2 =
          (crystalProj[f2.$1].z + crystalProj[f2.$2].z + crystalProj[f2.$3].z) /
              3.0;
      return z1.compareTo(z2);
    });
  for (final f in sortedFaces) {
    final p0 = crystalProj[f.$1];
    final p1 = crystalProj[f.$2];
    final p2 = crystalProj[f.$3];
    final avgZ = (p0.z + p1.z + p2.z) / 3.0;
    final faceAlpha = (0.14 + ((avgZ + 1.0) * 0.5) * 0.24).clamp(0.08, 0.42);
    final facePath = Path()
      ..moveTo(p0.offset.dx, p0.offset.dy)
      ..lineTo(p1.offset.dx, p1.offset.dy)
      ..lineTo(p2.offset.dx, p2.offset.dy)
      ..close();
    canvas.drawPath(
      facePath,
      Paint()
        ..color = accentColor.withValues(alpha: faceAlpha)
        ..style = PaintingStyle.fill,
    );
  }
  _drawProjectedWireframe(
    canvas,
    _visaoCrystalMesh,
    crystalProj,
    backColor: deep.withValues(alpha: 0.42),
    frontColor: highlight.withValues(alpha: 0.96),
    glowColor: accentColor.withValues(alpha: 0.28 + 0.14 * e),
    scale: scale,
    strokeWidth: 1.15,
  );

  final innerCrystalProj = _projectMesh(
    _visaoCrystalMesh,
    radius: side * 0.095 * pulseScale,
    rotX: -0.1 * math.sin(time * 0.7),
    rotY: -time * 0.28 * speed,
    rotZ: 0.0,
  );
  _drawProjectedWireframe(
    canvas,
    _visaoCrystalMesh,
    innerCrystalProj,
    backColor: innerWhite.withValues(alpha: 0.25),
    frontColor: innerWhite.withValues(alpha: 0.82),
    glowColor: highlight.withValues(alpha: 0.20),
    scale: scale,
    strokeWidth: 0.85,
  );

  final shardPaint = Paint()..style = PaintingStyle.fill;
  final shardEdgePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.8 * scale
    ..color = innerWhite.withValues(alpha: 0.86);
  const shardCount = 12;
  for (var i = 0; i < shardCount; i++) {
    final angle = (i / shardCount) * math.pi * 2.0 +
        time * (0.28 + (i % 4) * 0.07) * speed;
    final r = side * (0.31 + (i % 3) * 0.045);
    final x = math.cos(angle) * r;
    final y = ((i / (shardCount - 1)) - 0.5) * side * 0.34 +
        math.sin(time * 1.1 + i) * 4.0 * scale;
    final depth = (math.sin(angle) + 1.0) * 0.5;
    final shW = (2.2 + depth * 1.4) * scale;
    final shH = (4.8 + depth * 2.6) * scale;
    final diamond = Path()
      ..moveTo(x, y - shH)
      ..lineTo(x + shW, y)
      ..lineTo(x, y + shH)
      ..lineTo(x - shW, y)
      ..close();
    shardPaint.color = highlight.withValues(alpha: 0.24 + depth * 0.42);
    canvas.drawPath(diamond, shardPaint);
    canvas.drawPath(diamond, shardEdgePaint);
  }

  canvas.restore();
}

/// 4. EDITH — Rede Tática Orbital de Drones Verde-Água.
void _paintEdithCore(
  Canvas canvas,
  Size size,
  double time,
  double energy, {
  Color accentColor = const Color(0xFF14B8A6),
}) {
  final side = size.shortestSide;
  if (side <= 0) return;
  final center = size.center(Offset.zero);
  final e = energy.clamp(0.0, 1.2);
  final speed = 0.38 + e * 0.62;
  final scale = (side / 200.0).clamp(0.32, 2.2);

  const highlight = Color(0xFF7AFFEA);
  final deep = Color.lerp(accentColor, const Color(0xFF003B32), 0.58)!;
  final steppedPhase = time + 0.16 * math.sin(time * 4.2);

  canvas.save();
  canvas.translate(center.dx, center.dy);

  for (final rf in const [0.27, 0.35, 0.43]) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: side * rf * 2,
        height: side * rf * 0.72,
      ),
      Paint()
        ..color = accentColor.withValues(alpha: rf == 0.35 ? 0.32 : 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75 * scale,
    );
  }
  final crosshairPaint = Paint()
    ..color = accentColor.withValues(alpha: 0.20)
    ..strokeWidth = 0.7 * scale;
  for (var i = 0; i < 8; i++) {
    final a = (i / 8.0) * math.pi * 2.0;
    canvas.drawLine(
      Offset(math.cos(a) * side * 0.21, math.sin(a) * side * 0.075),
      Offset(math.cos(a) * side * 0.43, math.sin(a) * side * 0.155),
      crosshairPaint,
    );
  }
  final sweepAngle = -time * 1.85 * speed;
  canvas.drawLine(
    Offset.zero,
    Offset(
      math.cos(sweepAngle) * side * 0.43,
      math.sin(sweepAngle) * side * 0.155,
    ),
    Paint()
      ..color = highlight.withValues(alpha: 0.84)
      ..strokeWidth = 1.45 * scale
      ..strokeCap = StrokeCap.round,
  );

  final hexProj = _projectMesh(
    _edithHexCageMesh,
    radius: side * 0.24,
    rotX: 0.32 - time * 0.14 * speed,
    rotY: time * 0.22 * speed,
    rotZ: 0.08,
  );
  _drawProjectedWireframe(
    canvas,
    _edithHexCageMesh,
    hexProj,
    backColor: deep.withValues(alpha: 0.22),
    frontColor: accentColor.withValues(alpha: 0.34),
    glowColor: accentColor.withValues(alpha: 0.08),
    scale: scale,
    strokeWidth: 0.75,
  );

  final tetraAProj = _projectMesh(
    _edithTetraAMesh,
    radius: side * 0.21,
    rotX: 0.28 + steppedPhase * 0.30 * speed,
    rotY: steppedPhase * 0.65 * speed,
    rotZ: 0.0,
  );
  _drawProjectedWireframe(
    canvas,
    _edithTetraAMesh,
    tetraAProj,
    backColor: deep.withValues(alpha: 0.32),
    frontColor: accentColor.withValues(alpha: 0.92),
    glowColor: accentColor.withValues(alpha: 0.24 + 0.12 * e),
    scale: scale,
  );

  final tetraBProj = _projectMesh(
    _edithTetraBMesh,
    radius: side * 0.21,
    rotX: -0.22,
    rotY: -steppedPhase * 0.65 * speed,
    rotZ: steppedPhase * 0.26 * speed,
  );
  _drawProjectedWireframe(
    canvas,
    _edithTetraBMesh,
    tetraBProj,
    backColor: deep.withValues(alpha: 0.28),
    frontColor: highlight.withValues(alpha: 0.84),
    glowColor: highlight.withValues(alpha: 0.18 + 0.12 * e),
    scale: scale,
  );

  final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.92);
  for (final v in [...tetraAProj, ...tetraBProj]) {
    if (v.z > -0.2) {
      canvas.drawCircle(v.offset, 1.8 * scale, dotPaint);
    }
  }

  canvas.save();
  canvas.rotate(steppedPhase * 0.45 * speed);
  final lockRect = Rect.fromCenter(
    center: Offset.zero,
    width: side * 0.68,
    height: side * 0.68,
  );
  final lockPaint = Paint()
    ..color = highlight.withValues(alpha: 0.72)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.45 * scale
    ..strokeCap = StrokeCap.round;
  for (var b = 0; b < 4; b++) {
    canvas.drawArc(lockRect, b * (math.pi / 2) + 0.20, 0.38, false, lockPaint);
  }
  canvas.restore();

  const droneOrbits = [
    (rx: 0.34, ry: 0.19, tilt: 0.52, speed: 1.05, count: 3),
    (rx: 0.40, ry: 0.22, tilt: -0.68, speed: -0.82, count: 3),
    (rx: 0.44, ry: 0.25, tilt: 0.92, speed: 0.68, count: 2),
  ];
  final orbitPaint = Paint()
    ..color = accentColor.withValues(alpha: 0.22)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.7 * scale;
  final droneBodyPaint = Paint()
    ..color = accentColor.withValues(alpha: 0.85)
    ..style = PaintingStyle.fill;
  final droneCorePaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;

  for (final orbit in droneOrbits) {
    canvas.save();
    canvas.rotate(orbit.tilt);
    final rx = side * orbit.rx;
    final ry = side * orbit.ry;
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
      orbitPaint,
    );
    for (var i = 0; i < orbit.count; i++) {
      final angle =
          (i / orbit.count) * math.pi * 2.0 + time * orbit.speed * speed;
      final px = math.cos(angle) * rx;
      final py = math.sin(angle) * ry;
      final tx = -math.sin(angle) * rx * (orbit.speed >= 0 ? 1 : -1);
      final ty = math.cos(angle) * ry * (orbit.speed >= 0 ? 1 : -1);
      final heading = math.atan2(ty, tx);

      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(heading);
      final s = 4.2 * scale;
      final tri = Path()
        ..moveTo(s * 1.3, 0)
        ..lineTo(-s, -s * 0.75)
        ..lineTo(-s * 0.55, 0)
        ..lineTo(-s, s * 0.75)
        ..close();
      canvas.drawPath(tri, droneBodyPaint);
      canvas.drawCircle(Offset.zero, 1.3 * scale, droneCorePaint);
      canvas.restore();
    }
    canvas.restore();
  }

  canvas.restore();
}

class _StarSpec {
  const _StarSpec({
    required this.nx,
    required this.ny,
    required this.radius,
    required this.baseAlpha,
    required this.twinkleSpeed,
    required this.phase,
    required this.driftX,
    required this.driftY,
    required this.tone,
    required this.hasHalo,
  });

  final double nx;
  final double ny;
  final double radius;
  final double baseAlpha;
  final double twinkleSpeed;
  final double phase;
  final double driftX;
  final double driftY;
  final int tone;
  final bool hasHalo;
}

final List<_StarSpec> _precomputedStars = _generateStarfield(96);

List<_StarSpec> _generateStarfield(int count) {
  final rng = math.Random(20260711);
  return List<_StarSpec>.generate(count, (i) {
    final nx = rng.nextDouble();
    final ny = rng.nextDouble();
    final depth = rng.nextDouble();
    final radius = 0.55 + depth * 1.15;
    final baseAlpha = 0.14 + depth * 0.46;
    final twinkleSpeed = 0.55 + rng.nextDouble() * 1.35;
    final phase = rng.nextDouble() * math.pi * 2.0;
    final angle = rng.nextDouble() * math.pi * 2.0;
    final driftMag = 0.0012 + depth * 0.0024;
    final toneRoll = rng.nextDouble();
    final tone = toneRoll < 0.54 ? 0 : (toneRoll < 0.84 ? 1 : 2);
    return _StarSpec(
      nx: nx,
      ny: ny,
      radius: radius,
      baseAlpha: baseAlpha,
      twinkleSpeed: twinkleSpeed,
      phase: phase,
      driftX: math.cos(angle) * driftMag,
      driftY: math.sin(angle) * driftMag,
      tone: tone,
      hasHalo: depth > 0.78,
    );
  }, growable: false);
}

/// Fundo AMOLED espacial com névoa tonalizada pelo acento da persona e estrelas cintilantes.
class CoreStarfieldBackdrop extends StatefulWidget {
  const CoreStarfieldBackdrop({
    super.key,
    this.active = true,
    this.energy = 0.2,
    this.accentColor = const Color(0xFFF10D28),
    this.starCount = 78,
    this.nebulaIntensity = 1.0,
    this.centerAlignment = Alignment.center,
  });

  final bool active;
  final double energy;
  final Color accentColor;
  final int starCount;
  final double nebulaIntensity;
  final Alignment centerAlignment;

  @override
  State<CoreStarfieldBackdrop> createState() => _CoreStarfieldBackdropState();
}

class _CoreStarfieldBackdropState extends State<CoreStarfieldBackdrop>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  bool _lifecycleActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initial = WidgetsBinding.instance.lifecycleState;
    _lifecycleActive = initial == null || initial == AppLifecycleState.resumed;
    _ticker = createTicker((elapsed) {
      _time.value = elapsed.inMicroseconds / 1000000.0;
    });
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant CoreStarfieldBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _syncTicker();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleActive = state == AppLifecycleState.resumed;
    _syncTicker();
  }

  void _syncTicker() {
    final shouldRun = _lifecycleActive && widget.active;
    if (shouldRun && !_ticker.isActive) {
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
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
    return RepaintBoundary(
      child: CustomPaint(
        painter: CoreStarfieldPainter(
          timeListenable: _time,
          energy: widget.energy,
          accentColor: widget.accentColor,
          starCount: widget.starCount,
          nebulaIntensity: widget.nebulaIntensity,
          centerAlignment: widget.centerAlignment,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class CoreStarfieldPainter extends CustomPainter {
  CoreStarfieldPainter({
    required this.timeListenable,
    this.energy = 0.2,
    this.accentColor = const Color(0xFFF10D28),
    this.starCount = 78,
    this.nebulaIntensity = 1.0,
    this.centerAlignment = Alignment.center,
  }) : super(repaint: timeListenable);

  final ValueListenable<double> timeListenable;
  final double energy;
  final Color accentColor;
  final int starCount;
  final double nebulaIntensity;
  final Alignment centerAlignment;

  final Paint _starPaint = Paint()..style = PaintingStyle.fill;
  final Paint _haloPaint = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = timeListenable.value;
    final e = energy.clamp(0.0, 1.2);
    final neb = nebulaIntensity.clamp(0.0, 1.5);
    final center = centerAlignment.alongSize(size);

    if (neb > 0.01) {
      final glowRadius = math.max(size.width, size.height) * 0.56;
      final nebulaRect = Rect.fromCircle(center: center, radius: glowRadius);
      final nebulaAlpha = (0.075 + e * 0.035) * neb;
      final deepNebula =
          Color.lerp(accentColor, const Color(0xFF1A0408), 0.35)!;
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            colors: [
              deepNebula.withValues(alpha: nebulaAlpha),
              deepNebula.withValues(alpha: nebulaAlpha * 0.38),
              const Color(0x00080808),
            ],
            stops: const [0.0, 0.42, 1.0],
          ).createShader(nebulaRect),
      );
    }

    final primaryTint =
        Color.lerp(accentColor, const Color(0xFFFF6B7D), 0.24)!;
    final softTint = Color.lerp(accentColor, Colors.white, 0.66)!;
    const warmWhite = Color(0xFFFFF3F5);

    final count = starCount.clamp(0, _precomputedStars.length);
    final driftFactor = 1.0 + e * 0.55;

    for (var i = 0; i < count; i++) {
      final s = _precomputedStars[i];
      var fx = (s.nx + s.driftX * t * driftFactor) % 1.0;
      var fy = (s.ny + s.driftY * t * driftFactor) % 1.0;
      if (fx < 0) fx += 1.0;
      if (fy < 0) fy += 1.0;

      final px = fx * size.width;
      final py = fy * size.height;

      final edgeX = math.min(fx, 1.0 - fx) * 6.0;
      final edgeY = math.min(fy, 1.0 - fy) * 6.0;
      final edgeFade = math.min(1.0, math.min(edgeX, edgeY)).clamp(0.15, 1.0);

      final twinkle = 0.52 + 0.48 * math.sin(t * s.twinkleSpeed + s.phase);
      final alpha = (s.baseAlpha *
              twinkle *
              (0.85 + 0.28 * e) *
              edgeFade *
              (0.45 + 0.55 * neb))
          .clamp(0.0, 0.85);
      if (alpha <= 0.01) continue;

      final color = switch (s.tone) {
        0 => primaryTint,
        1 => softTint,
        _ => warmWhite,
      };

      if (s.hasHalo) {
        _haloPaint.color = color.withValues(alpha: alpha * 0.24);
        canvas.drawCircle(Offset(px, py), s.radius * 2.7, _haloPaint);
      }

      _starPaint.color = color.withValues(alpha: alpha);
      canvas.drawCircle(Offset(px, py), s.radius, _starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CoreStarfieldPainter oldDelegate) =>
      oldDelegate.timeListenable != timeListenable ||
      oldDelegate.energy != energy ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.starCount != starCount ||
      oldDelegate.nebulaIntensity != nebulaIntensity ||
      oldDelegate.centerAlignment != centerAlignment;
}
