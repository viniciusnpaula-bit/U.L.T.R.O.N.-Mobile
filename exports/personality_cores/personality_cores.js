/**
 * U.L.T.R.O.N. Personality Cores — Standalone HTML5 Canvas 2D / ES Module Port
 * Fidelity 1:1 with `lib/ui/widgets/core_orb.dart` & `lib/models/assistant_persona.dart`.
 * Zero external dependencies. Ready for Electron, PyWebView, React/Vite, or Browser.
 */

export const PERSONA_CORES = Object.freeze({
  ultron: Object.freeze({
    id: 'ultron',
    displayName: 'U.L.T.R.O.N.',
    tagline: 'Tático, objetivo e preciso',
    themeName: 'Vermelho Carmesim',
    accentColor: '#F10D28',
    accentDark: '#2A0C12',
    accentBorder: '#4A1822',
    highlightColor: '#FF8A99',
    defaultStyle: 'direto',
    promptDirective:
      'Identidade ativa: U.L.T.R.O.N. Tom confiante, tático, conciso e altamente competente.',
    geometry: 'icosahedron_geodesic_singularity',
  }),
  jarvis: Object.freeze({
    id: 'jarvis',
    displayName: 'J.A.R.V.I.S.',
    tagline: 'Refinado, analítico e cortês',
    themeName: 'Azul Cobalto',
    accentColor: '#2563EB',
    accentDark: '#0C1A36',
    accentBorder: '#1D3F80',
    highlightColor: '#6EC1FF',
    defaultStyle: 'executivo',
    promptDirective:
      'Identidade ativa: J.A.R.V.I.S. Tom cortês, analítico, organizado e sutilmente espirituoso.',
    geometry: 'dodecahedron_gyroscopic_hud',
  }),
  visao: Object.freeze({
    id: 'visao',
    displayName: 'VISÃO',
    tagline: 'Calmo, ponderado e reflexivo',
    themeName: 'Amarelo Âmbar',
    accentColor: '#F59E0B',
    accentDark: '#2E1E06',
    accentBorder: '#5C3D0E',
    highlightColor: '#FFE082',
    defaultStyle: 'calmo',
    promptDirective:
      'Identidade ativa: VISÃO. Tom calmo, empático, lógico e equilibrado.',
    geometry: 'mind_stone_crystal_helices',
  }),
  edith: Object.freeze({
    id: 'edith',
    displayName: 'E.D.I.T.H.',
    tagline: 'Ágil, técnica e focada em execução',
    themeName: 'Verde-Água',
    accentColor: '#14B8A6',
    accentDark: '#082825',
    accentBorder: '#11524B',
    highlightColor: '#7AFFEA',
    defaultStyle: 'tecnico',
    promptDirective:
      'Identidade ativa: E.D.I.T.H. Tom ágil, claro, orientado a diagnóstico rápido e execução prática.',
    geometry: 'stella_octangula_tactical_drones',
  }),
});

export function normalizePersonaId(raw) {
  const clean = String(raw || '')
    .trim()
    .toLowerCase()
    .replace(/ã/g, 'a')
    .replace(/\./g, '');
  if (clean === 'vision' || clean === 'visao') return 'visao';
  if (clean === 'jarvis' || clean === 'edith' || clean === 'ultron') return clean;
  return 'ultron';
}

function clamp(v, min, max) {
  return Math.max(min, Math.min(max, v));
}

function hexToRgb(hex) {
  const clean = String(hex || '#F10D28').replace('#', '');
  const full =
    clean.length === 3
      ? clean
          .split('')
          .map((c) => c + c)
          .join('')
      : clean.padEnd(6, '0').slice(0, 6);
  const num = parseInt(full, 16);
  return {
    r: (num >> 16) & 255,
    g: (num >> 8) & 255,
    b: num & 255,
  };
}

function lerpRgb(a, b, t) {
  const k = clamp(t, 0, 1);
  return {
    r: Math.round(a.r + (b.r - a.r) * k),
    g: Math.round(a.g + (b.g - a.g) * k),
    b: Math.round(a.b + (b.b - a.b) * k),
  };
}

function rgba(rgb, alpha = 1) {
  return `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${clamp(alpha, 0, 1).toFixed(4)})`;
}

const WHITE_RGB = { r: 255, g: 255, b: 255 };
const AMOLED_RGB = { r: 8, g: 8, b: 8 };

function normalizeVec3(x, y, z) {
  const len = Math.hypot(x, y, z);
  if (len === 0) return [0, 0, 1];
  return [x / len, y / len, z / len];
}

function buildIcosahedronMesh(subdivisions) {
  const t = (1.0 + Math.sqrt(5.0)) / 2.0;
  const baseCoords = [
    [-1, t, 0],
    [1, t, 0],
    [-1, -t, 0],
    [1, -t, 0],
    [0, -1, t],
    [0, 1, t],
    [0, -1, -t],
    [0, 1, -t],
    [t, 0, -1],
    [t, 0, 1],
    [-t, 0, -1],
    [-t, 0, 1],
  ];
  const verts = baseCoords.map(([x, y, z]) => normalizeVec3(x, y, z));
  let faces = [
    [0, 11, 5],
    [0, 5, 1],
    [0, 1, 7],
    [0, 7, 10],
    [0, 10, 11],
    [1, 5, 9],
    [5, 11, 4],
    [11, 10, 2],
    [10, 7, 6],
    [7, 1, 8],
    [3, 9, 4],
    [3, 4, 2],
    [3, 2, 6],
    [3, 6, 8],
    [3, 8, 9],
    [4, 9, 5],
    [2, 4, 11],
    [6, 2, 10],
    [8, 6, 7],
    [9, 8, 1],
  ];

  for (let s = 0; s < subdivisions; s++) {
    const midpointCache = new Map();
    const getMidpoint = (i1, i2) => {
      const a = Math.min(i1, i2);
      const b = Math.max(i1, i2);
      const key = `${a}_${b}`;
      if (midpointCache.has(key)) return midpointCache.get(key);
      const v1 = verts[a];
      const v2 = verts[b];
      const mid = normalizeVec3(
        (v1[0] + v2[0]) * 0.5,
        (v1[1] + v2[1]) * 0.5,
        (v1[2] + v2[2]) * 0.5
      );
      const idx = verts.length;
      verts.push(mid);
      midpointCache.set(key, idx);
      return idx;
    };

    const nextFaces = [];
    for (const [f0, f1, f2] of faces) {
      const a = getMidpoint(f0, f1);
      const b = getMidpoint(f1, f2);
      const c = getMidpoint(f2, f0);
      nextFaces.push([f0, a, c], [f1, b, a], [f2, c, b], [a, b, c]);
    }
    faces = nextFaces;
  }

  const edgeSet = new Set();
  const edges = [];
  const addEdge = (i1, i2) => {
    const a = Math.min(i1, i2);
    const b = Math.max(i1, i2);
    const key = `${a}_${b}`;
    if (!edgeSet.has(key)) {
      edgeSet.add(key);
      edges.push([a, b]);
    }
  };
  for (const [f0, f1, f2] of faces) {
    addEdge(f0, f1);
    addEdge(f1, f2);
    addEdge(f2, f0);
  }
  return { vertices: verts, edges };
}

function buildDodecahedronMesh() {
  const phi = (1.0 + Math.sqrt(5.0)) / 2.0;
  const inv = 1.0 / phi;
  const verts = [];
  for (const x of [-1.0, 1.0]) {
    for (const y of [-1.0, 1.0]) {
      for (const z of [-1.0, 1.0]) verts.push(normalizeVec3(x, y, z));
    }
  }
  for (const y of [-inv, inv]) {
    for (const z of [-phi, phi]) verts.push(normalizeVec3(0, y, z));
  }
  for (const x of [-inv, inv]) {
    for (const y of [-phi, phi]) verts.push(normalizeVec3(x, y, 0));
  }
  for (const x of [-phi, phi]) {
    for (const z of [-inv, inv]) verts.push(normalizeVec3(x, 0, z));
  }
  const edges = [];
  for (let i = 0; i < verts.length; i++) {
    for (let j = i + 1; j < verts.length; j++) {
      const dx = verts[i][0] - verts[j][0];
      const dy = verts[i][1] - verts[j][1];
      const dz = verts[i][2] - verts[j][2];
      if (dx * dx + dy * dy + dz * dz < 0.65) edges.push([i, j]);
    }
  }
  return { vertices: verts, edges };
}

function buildLatLonWireMesh() {
  const verts = [];
  const edges = [];
  const rings = 4;
  const segs = 10;
  for (let r = 1; r <= rings; r++) {
    const phi = (Math.PI * r) / (rings + 1);
    const sp = Math.sin(phi);
    const cp = Math.cos(phi);
    const base = verts.length;
    for (let s = 0; s < segs; s++) {
      const th = (s / segs) * Math.PI * 2.0;
      verts.push([sp * Math.cos(th), cp, sp * Math.sin(th)]);
      edges.push([base + s, base + ((s + 1) % segs)]);
      if (r > 1) edges.push([base - segs + s, base + s]);
    }
  }
  return { vertices: verts, edges };
}

function buildMindStoneCrystalMesh() {
  return {
    vertices: [
      [0, 1.42, 0],
      [0, -1.42, 0],
      [0.66, 0, 0],
      [-0.66, 0, 0],
      [0, 0, 0.66],
      [0, 0, -0.66],
    ],
    edges: [
      [0, 2],
      [0, 3],
      [0, 4],
      [0, 5],
      [1, 2],
      [1, 3],
      [1, 4],
      [1, 5],
      [2, 4],
      [4, 3],
      [3, 5],
      [5, 2],
    ],
  };
}

function buildTetrahedronMesh(inverted) {
  const sign = inverted ? -1.0 : 1.0;
  const raw = inverted
    ? [
        normalizeVec3(-1 * sign, 1, 1),
        normalizeVec3(-1 * sign, -1, -1),
        normalizeVec3(1 * sign, 1, -1),
        normalizeVec3(1 * sign, -1, 1),
      ]
    : [
        normalizeVec3(1, 1, 1),
        normalizeVec3(1, -1, -1),
        normalizeVec3(-1, 1, -1),
        normalizeVec3(-1, -1, 1),
      ];
  const vertices = inverted ? raw.map(([x, y, z]) => [z, -y, -x]) : raw;
  return {
    vertices,
    edges: [
      [0, 1],
      [0, 2],
      [0, 3],
      [1, 2],
      [1, 3],
      [2, 3],
    ],
  };
}

function buildHexPrismMesh() {
  const vertices = [];
  const edges = [];
  for (let i = 0; i < 6; i++) {
    const a = (i / 6.0) * Math.PI * 2.0;
    const x = Math.cos(a) * 0.92;
    const z = Math.sin(a) * 0.92;
    vertices.push([x, 0.56, z], [x, -0.56, z]);
  }
  for (let i = 0; i < 6; i++) {
    const next = (i + 1) % 6;
    edges.push([i * 2, next * 2], [i * 2 + 1, next * 2 + 1], [i * 2, i * 2 + 1]);
  }
  return { vertices, edges };
}

const outerIcoMesh = buildIcosahedronMesh(0);
const innerGeodesicMesh = buildIcosahedronMesh(1);
const jarvisDodecaMesh = buildDodecahedronMesh();
const jarvisSphereMesh = buildLatLonWireMesh();
const visaoCrystalMesh = buildMindStoneCrystalMesh();
const visaoCrystalFaces = [
  [0, 2, 4],
  [0, 4, 3],
  [0, 3, 5],
  [0, 5, 2],
  [1, 4, 2],
  [1, 3, 4],
  [1, 5, 3],
  [1, 2, 5],
];
const edithTetraAMesh = buildTetrahedronMesh(false);
const edithTetraBMesh = buildTetrahedronMesh(true);
const edithHexCageMesh = buildHexPrismMesh();

function projectMesh(mesh, { radius, rotX, rotY, rotZ }) {
  const cx = Math.cos(rotX);
  const sx = Math.sin(rotX);
  const cy = Math.cos(rotY);
  const sy = Math.sin(rotY);
  const cz = Math.cos(rotZ);
  const sz = Math.sin(rotZ);
  const focal = 3.4;

  return mesh.vertices.map(([vx, vy, vz]) => {
    const x1 = vx * cy + vz * sy;
    const y1 = vy;
    const z1 = -vx * sy + vz * cy;
    const x2 = x1;
    const y2 = y1 * cx - z1 * sx;
    const z2 = y1 * sx + z1 * cx;
    const x3 = x2 * cz - y2 * sz;
    const y3 = x2 * sz + y2 * cz;
    const z3 = z2;
    const perspective = focal / (focal - z3);
    return {
      x: x3 * radius * perspective,
      y: y3 * radius * perspective,
      z: z3,
    };
  });
}

function drawProjectedWireframe(
  ctx,
  mesh,
  projected,
  { backColor, frontColor, glowColor, scale, strokeWidth = 1.0 }
) {
  ctx.save();
  ctx.lineWidth = 0.72 * strokeWidth * scale;
  ctx.strokeStyle = backColor;
  ctx.beginPath();
  for (const [i1, i2] of mesh.edges) {
    const p1 = projected[i1];
    const p2 = projected[i2];
    if ((p1.z + p2.z) * 0.5 < 0.0) {
      ctx.moveTo(p1.x, p1.y);
      ctx.lineTo(p2.x, p2.y);
    }
  }
  ctx.stroke();

  ctx.lineCap = 'round';
  ctx.lineWidth = 2.5 * strokeWidth * scale;
  ctx.strokeStyle = glowColor;
  ctx.beginPath();
  for (const [i1, i2] of mesh.edges) {
    const p1 = projected[i1];
    const p2 = projected[i2];
    if ((p1.z + p2.z) * 0.5 >= 0.0) {
      ctx.moveTo(p1.x, p1.y);
      ctx.lineTo(p2.x, p2.y);
    }
  }
  ctx.stroke();

  ctx.lineWidth = 1.05 * strokeWidth * scale;
  ctx.strokeStyle = frontColor;
  ctx.stroke();
  ctx.restore();
}

function drawOval(ctx, cx, cy, width, height) {
  ctx.beginPath();
  ctx.ellipse(cx, cy, Math.max(0, width * 0.5), Math.max(0, height * 0.5), 0, 0, Math.PI * 2);
  ctx.stroke();
}

function paintOrbitalRings(ctx, side, time, speed, energy, scale, midRgb, softRgb) {
  ctx.save();
  ctx.strokeStyle = rgba(midRgb, 0.15);
  ctx.lineWidth = 0.7 * scale;
  ctx.beginPath();
  ctx.arc(0, 0, side * 0.445, 0, Math.PI * 2);
  ctx.stroke();

  ctx.save();
  ctx.rotate(-0.42 + time * 0.12 * speed);
  const t1 = clamp(energy * 0.55, 0.0, 1.0);
  const ring1Rgb = lerpRgb(midRgb, softRgb, t1);
  ctx.strokeStyle = rgba(ring1Rgb, 0.55 + (0.85 - 0.55) * t1);
  ctx.lineWidth = 1.15 * scale;
  drawOval(ctx, 0, 0, side * 0.82, side * 0.69);
  ctx.restore();

  ctx.save();
  ctx.rotate(0.58 - time * 0.09 * speed);
  ctx.strokeStyle = rgba(midRgb, 0.30);
  ctx.lineWidth = 0.85 * scale;
  drawOval(ctx, 0, 0, side * 0.76, side * 0.63);
  ctx.restore();

  ctx.save();
  ctx.rotate(0.78 + Math.sin(time * 0.18 * speed) * 0.04);
  const t2 = clamp(energy * 0.5, 0.0, 1.0);
  const diagRgb = lerpRgb(midRgb, softRgb, t2);
  ctx.strokeStyle = rgba(diagRgb, 0.42 + (0.74 - 0.42) * t2);
  ctx.lineWidth = 0.9 * scale;
  drawOval(ctx, 0, 0, side * 0.94, side * 0.032);
  ctx.restore();

  ctx.restore();
}

function paintGeodesicCore(ctx, width, height, time, energy, accentRgb) {
  const side = Math.min(width, height);
  if (side <= 0) return;
  const cx = width * 0.5;
  const cy = height * 0.5;
  const e = clamp(energy, 0.0, 1.2);
  const speed = 0.28 + e * 0.55;
  const scale = clamp(side / 200.0, 0.32, 2.2);
  const breathe = 1.0 + 0.022 * (0.4 + e) * Math.sin(time * 2.8);
  const softRgb = lerpRgb(accentRgb, WHITE_RGB, 0.58);
  const midRgb = lerpRgb(accentRgb, WHITE_RGB, 0.26);
  const deepRgb = lerpRgb(accentRgb, AMOLED_RGB, 0.42);

  ctx.save();
  ctx.translate(cx, cy);

  for (let i = 0; i < 16; i++) {
    const seed = i * 1.61803398875;
    const angle = seed * 6.2831 + time * (0.04 + (i % 3) * 0.015);
    const dist = side * (0.37 + (i % 5) * 0.026);
    const alpha = clamp(0.18 + 0.25 * (0.5 + 0.5 * Math.sin(time * 1.4 + i)), 0.0, 0.55);
    ctx.fillStyle = rgba(softRgb, alpha);
    ctx.beginPath();
    ctx.arc(
      Math.cos(angle) * dist,
      Math.sin(angle) * dist,
      (i % 3 === 0 ? 1.15 : 0.75) * scale,
      0,
      Math.PI * 2
    );
    ctx.fill();
  }

  paintOrbitalRings(ctx, side, time, speed, e, scale, midRgb, softRgb);

  ctx.save();
  ctx.rotate(0.27 + 0.04 * Math.sin(time * 0.8));
  const axisHalf = side * 0.40;
  const axisGrad = ctx.createLinearGradient(0, -axisHalf, 0, axisHalf);
  axisGrad.addColorStop(0.0, rgba(softRgb, 0.0));
  axisGrad.addColorStop(0.34, rgba(softRgb, 0.72));
  axisGrad.addColorStop(0.50, 'rgba(255, 255, 255, 0.92)');
  axisGrad.addColorStop(0.66, rgba(softRgb, 0.72));
  axisGrad.addColorStop(1.0, rgba(softRgb, 0.0));
  ctx.strokeStyle = axisGrad;
  ctx.lineWidth = 1.6 * scale;
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(0, -axisHalf);
  ctx.lineTo(0, axisHalf);
  ctx.stroke();
  ctx.restore();

  const outerProjected = projectMesh(outerIcoMesh, {
    radius: side * 0.315 * breathe,
    rotX: -0.32 - time * 0.14 * speed,
    rotY: -time * 0.22 * speed,
    rotZ: 0.18,
  });
  ctx.lineWidth = 0.65 * scale;
  for (const [i1, i2] of outerIcoMesh.edges) {
    const p1 = outerProjected[i1];
    const p2 = outerProjected[i2];
    const avgZ = (p1.z + p2.z) * 0.5;
    const depthT = clamp((avgZ + 1.0) * 0.5, 0.0, 1.0);
    ctx.strokeStyle = rgba(deepRgb, 0.08 + depthT * (0.18 + 0.08 * e));
    ctx.beginPath();
    ctx.moveTo(p1.x, p1.y);
    ctx.lineTo(p2.x, p2.y);
    ctx.stroke();
  }

  const innerProjected = projectMesh(innerGeodesicMesh, {
    radius: side * 0.222 * breathe,
    rotX: 0.28 + Math.sin(time * 0.35 * speed) * 0.18,
    rotY: time * 0.42 * speed,
    rotZ: -0.14 + time * 0.09 * speed,
  });

  ctx.lineWidth = 0.7 * scale;
  for (const [i1, i2] of innerGeodesicMesh.edges) {
    const p1 = innerProjected[i1];
    const p2 = innerProjected[i2];
    const avgZ = (p1.z + p2.z) * 0.5;
    if (avgZ >= 0.0) continue;
    const depthT = clamp(avgZ + 1.0, 0.0, 1.0);
    ctx.strokeStyle = rgba(deepRgb, 0.14 + depthT * 0.24);
    ctx.beginPath();
    ctx.moveTo(p1.x, p1.y);
    ctx.lineTo(p2.x, p2.y);
    ctx.stroke();
  }

  ctx.lineCap = 'round';
  for (const [i1, i2] of innerGeodesicMesh.edges) {
    const p1 = innerProjected[i1];
    const p2 = innerProjected[i2];
    const avgZ = (p1.z + p2.z) * 0.5;
    if (avgZ < 0.0) continue;
    const depthT = clamp(avgZ, 0.0, 1.0);

    ctx.lineWidth = 2.4 * scale;
    ctx.strokeStyle = rgba(accentRgb, 0.10 + depthT * (0.18 + 0.12 * e));
    ctx.beginPath();
    ctx.moveTo(p1.x, p1.y);
    ctx.lineTo(p2.x, p2.y);
    ctx.stroke();

    ctx.lineWidth = 0.95 * scale;
    const edgeRgb = lerpRgb(midRgb, softRgb, clamp(depthT * 0.85 + e * 0.15, 0.0, 1.0));
    ctx.strokeStyle = rgba(edgeRgb, 0.52 + depthT * 0.44);
    ctx.stroke();
  }

  for (const p of innerProjected) {
    if (p.z < -0.15) {
      ctx.fillStyle = rgba(midRgb, 0.33);
      ctx.beginPath();
      ctx.arc(p.x, p.y, 0.85 * scale, 0, Math.PI * 2);
      ctx.fill();
      continue;
    }
    const depthT = clamp((p.z + 0.15) / 1.15, 0.0, 1.0);
    ctx.fillStyle = rgba(midRgb, 0.16 + depthT * (0.32 + 0.16 * e));
    ctx.beginPath();
    ctx.arc(p.x, p.y, (2.2 + depthT * 1.8) * scale, 0, Math.PI * 2);
    ctx.fill();

    const nodeRgb = lerpRgb(softRgb, WHITE_RGB, depthT);
    ctx.fillStyle = rgba(nodeRgb, 0.55 + depthT * 0.45);
    ctx.beginPath();
    ctx.arc(p.x, p.y, (0.9 + depthT * 0.85) * scale, 0, Math.PI * 2);
    ctx.fill();
  }

  ctx.restore();
}

function paintJarvisCore(ctx, width, height, time, energy, accentRgb) {
  const side = Math.min(width, height);
  if (side <= 0) return;
  const cx = width * 0.5;
  const cy = height * 0.5;
  const e = clamp(energy, 0.0, 1.2);
  const speed = 0.34 + e * 0.55;
  const scale = clamp(side / 200.0, 0.32, 2.2);
  const breath = 1.0 + 0.024 * (0.4 + e) * Math.sin(time * 1.45);
  const highlightRgb = { r: 0x6e, g: 0xc1, b: 0xff };
  const deepRgb = lerpRgb(accentRgb, { r: 0x00, g: 0x1c, b: 0x52 }, 0.55);

  ctx.save();
  ctx.translate(cx, cy);

  ctx.save();
  ctx.rotate(time * 0.06 * speed);
  ctx.strokeStyle = rgba(accentRgb, 0.16);
  ctx.lineWidth = 0.7 * scale;
  for (const rf of [0.22, 0.31, 0.40]) {
    drawOval(ctx, 0, 0, side * rf * 2.0, side * rf * 0.72);
  }
  ctx.strokeStyle = rgba(highlightRgb, 0.13);
  ctx.lineWidth = 0.65 * scale;
  ctx.beginPath();
  for (let i = 0; i < 12; i++) {
    const a = (i / 12.0) * Math.PI * 2.0 + time * 0.06 * speed;
    const ca = Math.cos(a);
    const sa = Math.sin(a);
    ctx.moveTo(ca * side * 0.18, sa * side * 0.065);
    ctx.lineTo(ca * side * 0.40, sa * side * 0.145);
  }
  ctx.stroke();
  ctx.restore();

  const innerSphereProj = projectMesh(jarvisSphereMesh, {
    radius: side * 0.115 * breath,
    rotX: 0.25,
    rotY: -time * 0.45 * speed,
    rotZ: 0.0,
  });
  drawProjectedWireframe(ctx, jarvisSphereMesh, innerSphereProj, {
    backColor: rgba(highlightRgb, 0.14),
    frontColor: rgba(highlightRgb, 0.34),
    glowColor: rgba(highlightRgb, 0.08),
    scale,
    strokeWidth: 0.7,
  });

  const dodecaProj = projectMesh(jarvisDodecaMesh, {
    radius: side * 0.21 * breath,
    rotX: 0.24 + time * 0.16 * speed,
    rotY: time * 0.34 * speed,
    rotZ: 0.08,
  });
  drawProjectedWireframe(ctx, jarvisDodecaMesh, dodecaProj, {
    backColor: rgba(deepRgb, 0.30),
    frontColor: rgba(highlightRgb, 0.88),
    glowColor: rgba(accentRgb, 0.22 + 0.12 * e),
    scale,
  });

  for (const v of dodecaProj) {
    const t = clamp((v.z + 1.0) * 0.5, 0.0, 1.0);
    ctx.fillStyle = rgba(highlightRgb, 0.22 + t * 0.70);
    ctx.beginPath();
    ctx.arc(v.x, v.y, (1.0 + t * 1.1) * scale, 0, Math.PI * 2);
    ctx.fill();
  }

  const drawHudGimbal = ({ radiusFactor, rotation, tiltY, segments, ticks, colorRgb, opacity }) => {
    const rx = side * radiusFactor;
    const ry = rx * tiltY;
    ctx.save();
    ctx.rotate(rotation);
    const gap = 0.24;
    const span = (Math.PI * 2.0) / segments - gap;
    ctx.lineCap = 'round';
    for (let s = 0; s < segments; s++) {
      const start = s * ((Math.PI * 2.0) / segments);
      ctx.strokeStyle = rgba(colorRgb, opacity);
      ctx.lineWidth = 1.15 * scale;
      ctx.beginPath();
      ctx.ellipse(0, 0, rx, ry, 0, start, start + span);
      ctx.stroke();

      ctx.strokeStyle = rgba(highlightRgb, opacity * 0.55);
      ctx.lineWidth = 0.65 * scale;
      ctx.beginPath();
      ctx.ellipse(0, 0, rx + 4.5 * scale, ry + 2.2 * scale, 0, start + 0.06, start + span - 0.06);
      ctx.stroke();
    }
    ctx.strokeStyle = rgba(highlightRgb, opacity * 0.72);
    ctx.lineWidth = 0.7 * scale;
    ctx.beginPath();
    for (let i = 0; i < ticks; i++) {
      const a = (i / ticks) * Math.PI * 2.0;
      const major = i % 4 === 0;
      const dIn = major ? 5.0 * scale : 2.3 * scale;
      const dOut = major ? 4.2 * scale : 1.6 * scale;
      const ca = Math.cos(a);
      const sa = Math.sin(a);
      ctx.moveTo((rx - dIn) * ca, (ry - dIn * tiltY) * sa);
      ctx.lineTo((rx + dOut) * ca, (ry + dOut * tiltY) * sa);
    }
    ctx.stroke();
    ctx.restore();
  };

  drawHudGimbal({
    radiusFactor: 0.305,
    rotation: 0.2 + time * 0.42 * speed,
    tiltY: 0.88,
    segments: 4,
    ticks: 36,
    colorRgb: highlightRgb,
    opacity: 0.76,
  });
  drawHudGimbal({
    radiusFactor: 0.365,
    rotation: -0.65 - time * 0.34 * speed,
    tiltY: 0.56,
    segments: 3,
    ticks: 40,
    colorRgb: accentRgb,
    opacity: 0.66,
  });
  drawHudGimbal({
    radiusFactor: 0.425,
    rotation: 0.92 + time * 0.25 * speed,
    tiltY: 0.44,
    segments: 6,
    ticks: 48,
    colorRgb: lerpRgb(accentRgb, highlightRgb, 0.4),
    opacity: 0.54,
  });

  for (let i = 0; i < 24; i++) {
    const isEven = i % 2 === 0;
    const a = (i / 24.0) * Math.PI * 2.0 + time * 0.52 * speed * (isEven ? 1 : -0.65);
    const rx = side * (isEven ? 0.265 : 0.435);
    const ry = rx * 0.34;
    const tier = ((i % 3) - 1) * 3.5 * scale;
    const alpha = clamp(0.35 + 0.45 * Math.sin(a), 0.15, 0.88);
    ctx.fillStyle = rgba(highlightRgb, alpha);
    ctx.beginPath();
    ctx.arc(Math.cos(a) * rx, Math.sin(a) * ry + tier, 1.15 * scale, 0, Math.PI * 2);
    ctx.fill();
  }

  ctx.restore();
}

function paintVisaoCore(ctx, width, height, time, energy, accentRgb) {
  const side = Math.min(width, height);
  if (side <= 0) return;
  const cx = width * 0.5;
  const cy = height * 0.5;
  const e = clamp(energy, 0.0, 1.2);
  const speed = 0.28 + e * 0.48;
  const scale = clamp(side / 200.0, 0.32, 2.2);

  const highlightRgb = { r: 0xff, g: 0xe0, b: 0x82 };
  const innerWhiteRgb = { r: 0xff, g: 0xf8, b: 0xdc };
  const deepRgb = lerpRgb(accentRgb, { r: 0x7a, g: 0x41, b: 0x00 }, 0.55);

  const levitationY = Math.sin(time * 1.35) * 4.5 * scale;
  const beatPhase = (time * 1.15) % (Math.PI * 2.0);
  const heartbeat =
    Math.pow(Math.max(0.0, Math.sin(beatPhase)), 6) * 0.7 +
    Math.pow(Math.max(0.0, Math.sin(beatPhase - 0.65)), 8) * 0.4;
  const pulseScale = 1.0 + heartbeat * 0.07 + e * 0.04;

  ctx.save();
  ctx.translate(cx, cy + levitationY);

  for (let idx = 0; idx < 2; idx++) {
    const cycle = (time * 0.32 + idx * 0.5) % 1.0;
    const rx = side * (0.20 + cycle * 0.23);
    const ry = rx * 0.36;
    const waveAlpha = clamp(Math.sin(cycle * Math.PI) * (0.30 + 0.25 * e), 0.0, 0.7);
    ctx.strokeStyle = rgba(highlightRgb, waveAlpha);
    ctx.lineWidth = 1.0 * scale;
    drawOval(ctx, 0, 0, rx * 2, ry * 2);
  }

  for (let hIdx = 0; hIdx < 2; hIdx++) {
    const offset = hIdx * Math.PI;
    const rotY = time * 0.32 * speed;
    const steps = 64;
    ctx.beginPath();
    for (let i = 0; i <= steps; i++) {
      const t = i / steps;
      const phi = t * Math.PI;
      const theta = t * Math.PI * 6.0 + offset + rotY;
      const r = (0.29 * Math.sin(phi) + 0.035) * side;
      const px = r * Math.cos(theta);
      const py = (t - 0.5) * side * 0.68;
      if (i === 0) ctx.moveTo(px, py);
      else ctx.lineTo(px, py);
    }
    ctx.strokeStyle = hIdx === 0 ? rgba(highlightRgb, 0.48) : rgba(accentRgb, 0.42);
    ctx.lineWidth = (hIdx === 0 ? 0.9 : 0.85) * scale;
    ctx.stroke();
  }

  const crystalProj = projectMesh(visaoCrystalMesh, {
    radius: side * 0.165 * pulseScale,
    rotX: 0.14 * Math.sin(time * 0.7),
    rotY: time * 0.42 * speed,
    rotZ: 0.08 * Math.cos(time * 0.5),
  });
  const sortedFaces = [...visaoCrystalFaces].sort((f1, f2) => {
    const z1 = (crystalProj[f1[0]].z + crystalProj[f1[1]].z + crystalProj[f1[2]].z) / 3.0;
    const z2 = (crystalProj[f2[0]].z + crystalProj[f2[1]].z + crystalProj[f2[2]].z) / 3.0;
    return z1 - z2;
  });
  for (const [f0, f1, f2] of sortedFaces) {
    const p0 = crystalProj[f0];
    const p1 = crystalProj[f1];
    const p2 = crystalProj[f2];
    const avgZ = (p0.z + p1.z + p2.z) / 3.0;
    const faceAlpha = clamp(0.14 + (avgZ + 1.0) * 0.5 * 0.24, 0.08, 0.42);
    ctx.fillStyle = rgba(accentRgb, faceAlpha);
    ctx.beginPath();
    ctx.moveTo(p0.x, p0.y);
    ctx.lineTo(p1.x, p1.y);
    ctx.lineTo(p2.x, p2.y);
    ctx.closePath();
    ctx.fill();
  }
  drawProjectedWireframe(ctx, visaoCrystalMesh, crystalProj, {
    backColor: rgba(deepRgb, 0.42),
    frontColor: rgba(highlightRgb, 0.96),
    glowColor: rgba(accentRgb, 0.28 + 0.14 * e),
    scale,
    strokeWidth: 1.15,
  });

  const innerCrystalProj = projectMesh(visaoCrystalMesh, {
    radius: side * 0.095 * pulseScale,
    rotX: -0.1 * Math.sin(time * 0.7),
    rotY: -time * 0.28 * speed,
    rotZ: 0.0,
  });
  drawProjectedWireframe(ctx, visaoCrystalMesh, innerCrystalProj, {
    backColor: rgba(innerWhiteRgb, 0.25),
    frontColor: rgba(innerWhiteRgb, 0.82),
    glowColor: rgba(highlightRgb, 0.20),
    scale,
    strokeWidth: 0.85,
  });

  const shardCount = 12;
  ctx.strokeStyle = rgba(innerWhiteRgb, 0.86);
  ctx.lineWidth = 0.8 * scale;
  for (let i = 0; i < shardCount; i++) {
    const angle = (i / shardCount) * Math.PI * 2.0 + time * (0.28 + (i % 4) * 0.07) * speed;
    const r = side * (0.31 + (i % 3) * 0.045);
    const x = Math.cos(angle) * r;
    const y = ((i / (shardCount - 1)) - 0.5) * side * 0.34 + Math.sin(time * 1.1 + i) * 4.0 * scale;
    const depth = (Math.sin(angle) + 1.0) * 0.5;
    const shW = (2.2 + depth * 1.4) * scale;
    const shH = (4.8 + depth * 2.6) * scale;
    ctx.fillStyle = rgba(highlightRgb, 0.24 + depth * 0.42);
    ctx.beginPath();
    ctx.moveTo(x, y - shH);
    ctx.lineTo(x + shW, y);
    ctx.lineTo(x, y + shH);
    ctx.lineTo(x - shW, y);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
  }

  ctx.restore();
}

function paintEdithCore(ctx, width, height, time, energy, accentRgb) {
  const side = Math.min(width, height);
  if (side <= 0) return;
  const cx = width * 0.5;
  const cy = height * 0.5;
  const e = clamp(energy, 0.0, 1.2);
  const speed = 0.38 + e * 0.62;
  const scale = clamp(side / 200.0, 0.32, 2.2);

  const highlightRgb = { r: 0x7a, g: 0xff, b: 0xea };
  const deepRgb = lerpRgb(accentRgb, { r: 0x00, g: 0x3b, b: 0x32 }, 0.58);
  const steppedPhase = time + 0.16 * Math.sin(time * 4.2);

  ctx.save();
  ctx.translate(cx, cy);

  for (const rf of [0.27, 0.35, 0.43]) {
    ctx.strokeStyle = rgba(accentRgb, rf === 0.35 ? 0.32 : 0.16);
    ctx.lineWidth = 0.75 * scale;
    drawOval(ctx, 0, 0, side * rf * 2, side * rf * 0.72);
  }
  ctx.strokeStyle = rgba(accentRgb, 0.20);
  ctx.lineWidth = 0.7 * scale;
  ctx.beginPath();
  for (let i = 0; i < 8; i++) {
    const a = (i / 8.0) * Math.PI * 2.0;
    ctx.moveTo(Math.cos(a) * side * 0.21, Math.sin(a) * side * 0.075);
    ctx.lineTo(Math.cos(a) * side * 0.43, Math.sin(a) * side * 0.155);
  }
  ctx.stroke();

  const sweepAngle = -time * 1.85 * speed;
  ctx.strokeStyle = rgba(highlightRgb, 0.84);
  ctx.lineWidth = 1.45 * scale;
  ctx.lineCap = 'round';
  ctx.beginPath();
  ctx.moveTo(0, 0);
  ctx.lineTo(Math.cos(sweepAngle) * side * 0.43, Math.sin(sweepAngle) * side * 0.155);
  ctx.stroke();

  const hexProj = projectMesh(edithHexCageMesh, {
    radius: side * 0.24,
    rotX: 0.32 - time * 0.14 * speed,
    rotY: time * 0.22 * speed,
    rotZ: 0.08,
  });
  drawProjectedWireframe(ctx, edithHexCageMesh, hexProj, {
    backColor: rgba(deepRgb, 0.22),
    frontColor: rgba(accentRgb, 0.34),
    glowColor: rgba(accentRgb, 0.08),
    scale,
    strokeWidth: 0.75,
  });

  const tetraAProj = projectMesh(edithTetraAMesh, {
    radius: side * 0.21,
    rotX: 0.28 + steppedPhase * 0.30 * speed,
    rotY: steppedPhase * 0.65 * speed,
    rotZ: 0.0,
  });
  drawProjectedWireframe(ctx, edithTetraAMesh, tetraAProj, {
    backColor: rgba(deepRgb, 0.32),
    frontColor: rgba(accentRgb, 0.92),
    glowColor: rgba(accentRgb, 0.24 + 0.12 * e),
    scale,
  });

  const tetraBProj = projectMesh(edithTetraBMesh, {
    radius: side * 0.21,
    rotX: -0.22,
    rotY: -steppedPhase * 0.65 * speed,
    rotZ: steppedPhase * 0.26 * speed,
  });
  drawProjectedWireframe(ctx, edithTetraBMesh, tetraBProj, {
    backColor: rgba(deepRgb, 0.28),
    frontColor: rgba(highlightRgb, 0.84),
    glowColor: rgba(highlightRgb, 0.18 + 0.12 * e),
    scale,
  });

  ctx.fillStyle = 'rgba(255, 255, 255, 0.92)';
  for (const v of [...tetraAProj, ...tetraBProj]) {
    if (v.z > -0.2) {
      ctx.beginPath();
      ctx.arc(v.x, v.y, 1.8 * scale, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  ctx.save();
  ctx.rotate(steppedPhase * 0.45 * speed);
  ctx.strokeStyle = rgba(highlightRgb, 0.72);
  ctx.lineWidth = 1.45 * scale;
  ctx.lineCap = 'round';
  const lockR = side * 0.34;
  for (let b = 0; b < 4; b++) {
    const start = b * (Math.PI / 2) + 0.20;
    ctx.beginPath();
    ctx.arc(0, 0, lockR, start, start + 0.38);
    ctx.stroke();
  }
  ctx.restore();

  const droneOrbits = [
    { rx: 0.34, ry: 0.19, tilt: 0.52, speed: 1.05, count: 3 },
    { rx: 0.40, ry: 0.22, tilt: -0.68, speed: -0.82, count: 3 },
    { rx: 0.44, ry: 0.25, tilt: 0.92, speed: 0.68, count: 2 },
  ];

  for (const orbit of droneOrbits) {
    ctx.save();
    ctx.rotate(orbit.tilt);
    const rx = side * orbit.rx;
    const ry = side * orbit.ry;
    ctx.strokeStyle = rgba(accentRgb, 0.22);
    ctx.lineWidth = 0.7 * scale;
    drawOval(ctx, 0, 0, rx * 2, ry * 2);

    for (let i = 0; i < orbit.count; i++) {
      const angle = (i / orbit.count) * Math.PI * 2.0 + time * orbit.speed * speed;
      const px = Math.cos(angle) * rx;
      const py = Math.sin(angle) * ry;
      const tx = -Math.sin(angle) * rx * (orbit.speed >= 0 ? 1 : -1);
      const ty = Math.cos(angle) * ry * (orbit.speed >= 0 ? 1 : -1);
      const heading = Math.atan2(ty, tx);

      ctx.save();
      ctx.translate(px, py);
      ctx.rotate(heading);
      const s = 4.2 * scale;
      ctx.fillStyle = rgba(accentRgb, 0.85);
      ctx.beginPath();
      ctx.moveTo(s * 1.3, 0);
      ctx.lineTo(-s, -s * 0.75);
      ctx.lineTo(-s * 0.55, 0);
      ctx.lineTo(-s, s * 0.75);
      ctx.closePath();
      ctx.fill();

      ctx.fillStyle = '#FFFFFF';
      ctx.beginPath();
      ctx.arc(0, 0, 1.3 * scale, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }
    ctx.restore();
  }

  ctx.restore();
}

// Seeded PRNG (mulberry32) for deterministic starfield matching CoreStarfieldBackdrop
function createStarfield(count = 96) {
  let state = 20260711;
  const rand = () => {
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const stars = [];
  for (let i = 0; i < count; i++) {
    const nx = rand();
    const ny = rand();
    const depth = rand();
    const radius = 0.55 + depth * 1.15;
    const baseAlpha = 0.14 + depth * 0.46;
    const twinkleSpeed = 0.55 + rand() * 1.35;
    const phase = rand() * Math.PI * 2.0;
    const angle = rand() * Math.PI * 2.0;
    const driftMag = 0.0012 + depth * 0.0024;
    const toneRoll = rand();
    const tone = toneRoll < 0.54 ? 0 : toneRoll < 0.84 ? 1 : 2;
    stars.push({
      nx,
      ny,
      radius,
      baseAlpha,
      twinkleSpeed,
      phase,
      driftX: Math.cos(angle) * driftMag,
      driftY: Math.sin(angle) * driftMag,
      tone,
      hasHalo: depth > 0.78,
    });
  }
  return stars;
}

const PRECOMPUTED_STARS = createStarfield(96);

export function paintStarfield(ctx, width, height, time, options = {}) {
  if (width <= 0 || height <= 0) return;
  const persona = normalizePersonaId(options.persona);
  const spec = PERSONA_CORES[persona];
  const energy = clamp(options.energy ?? 0.2, 0.0, 1.2);
  const starCount = clamp(options.starCount ?? 78, 0, PRECOMPUTED_STARS.length);
  const nebulaIntensity = clamp(options.nebulaIntensity ?? 1.0, 0.0, 1.5);
  const accentRgb = hexToRgb(options.accentColor || spec.accentColor);
  const cx = width * (options.centerX ?? 0.5);
  const cy = height * (options.centerY ?? 0.5);

  if (nebulaIntensity > 0.01) {
    const glowRadius = Math.max(width, height) * 0.56;
    const nebulaAlpha = (0.075 + energy * 0.035) * nebulaIntensity;
    const deepNebula = lerpRgb(accentRgb, { r: 0x1a, g: 0x04, b: 0x08 }, 0.35);
    const grad = ctx.createRadialGradient(cx, cy, 0, cx, cy, glowRadius);
    grad.addColorStop(0.0, rgba(deepNebula, nebulaAlpha));
    grad.addColorStop(0.42, rgba(deepNebula, nebulaAlpha * 0.38));
    grad.addColorStop(1.0, 'rgba(8, 8, 8, 0)');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, width, height);
  }

  const primaryTint = lerpRgb(accentRgb, { r: 0xff, g: 0x6b, b: 0x7d }, 0.24);
  const softTint = lerpRgb(accentRgb, WHITE_RGB, 0.66);
  const warmWhite = { r: 0xff, g: 0xf3, b: 0xf5 };
  const driftFactor = 1.0 + energy * 0.55;

  for (let i = 0; i < starCount; i++) {
    const s = PRECOMPUTED_STARS[i];
    let fx = (s.nx + s.driftX * time * driftFactor) % 1.0;
    let fy = (s.ny + s.driftY * time * driftFactor) % 1.0;
    if (fx < 0) fx += 1.0;
    if (fy < 0) fy += 1.0;
    const px = fx * width;
    const py = fy * height;

    const edgeX = Math.min(fx, 1.0 - fx) * 6.0;
    const edgeY = Math.min(fy, 1.0 - fy) * 6.0;
    const edgeFade = clamp(Math.min(1.0, Math.min(edgeX, edgeY)), 0.15, 1.0);
    const twinkle = 0.52 + 0.48 * Math.sin(time * s.twinkleSpeed + s.phase);
    const alpha = clamp(
      s.baseAlpha * twinkle * (0.85 + 0.28 * energy) * edgeFade * (0.45 + 0.55 * nebulaIntensity),
      0.0,
      0.85
    );
    if (alpha <= 0.01) continue;

    const rgb = s.tone === 0 ? primaryTint : s.tone === 1 ? softTint : warmWhite;
    if (s.hasHalo) {
      ctx.fillStyle = rgba(rgb, alpha * 0.24);
      ctx.beginPath();
      ctx.arc(px, py, s.radius * 2.7, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.fillStyle = rgba(rgb, alpha);
    ctx.beginPath();
    ctx.arc(px, py, s.radius, 0, Math.PI * 2);
    ctx.fill();
  }
}

export function paintPersonaCore(ctx, width, height, time, options = {}) {
  const side = Math.min(width, height);
  if (side <= 0) return;

  const persona = normalizePersonaId(options.persona);
  const spec = PERSONA_CORES[persona];
  const energy = clamp(options.energy ?? 0.2, 0.0, 1.2);
  const accentRgb = hexToRgb(options.accentColor || spec.accentColor);
  const cx = width * 0.5;
  const cy = height * 0.5;

  let pulse;
  if (persona === 'visao') {
    pulse =
      1.0 +
      0.036 *
        (0.4 + energy) *
        (Math.pow(Math.max(0.0, Math.sin(time * 1.3)), 6) * 0.8 + 0.2);
  } else if (persona === 'jarvis') {
    pulse = 1.0 + 0.018 * (0.35 + energy) * Math.sin(time * 1.4);
  } else {
    pulse = 1.0 + 0.025 * (0.35 + energy) * Math.sin(time * 2.8);
  }

  const softRgb = lerpRgb(accentRgb, WHITE_RGB, 0.45);
  const deepRgb = lerpRgb(accentRgb, AMOLED_RGB, 0.72);
  const auraRadius = side * 0.44 * pulse;

  const auraGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, auraRadius);
  auraGrad.addColorStop(0.0, 'rgba(255, 253, 249, 0.933)');
  auraGrad.addColorStop(0.14, rgba(softRgb, 0.74));
  auraGrad.addColorStop(0.36, rgba(accentRgb, 0.36));
  auraGrad.addColorStop(0.68, rgba(deepRgb, 0.16));
  auraGrad.addColorStop(1.0, 'rgba(8, 8, 8, 0.0)');
  ctx.fillStyle = auraGrad;
  ctx.beginPath();
  ctx.arc(cx, cy, auraRadius, 0, Math.PI * 2);
  ctx.fill();

  const scanR = side * 0.28;
  ctx.strokeStyle = rgba(softRgb, 0.08);
  ctx.lineWidth = 0.7;
  ctx.beginPath();
  for (let dy = -scanR; dy <= scanR; dy += 4.2) {
    const chord = Math.sqrt(Math.max(0.0, scanR * scanR - dy * dy));
    ctx.moveTo(cx - chord, cy + dy);
    ctx.lineTo(cx + chord, cy + dy);
  }
  ctx.stroke();

  if (persona === 'jarvis') {
    paintJarvisCore(ctx, width, height, time, energy, accentRgb);
  } else if (persona === 'visao') {
    paintVisaoCore(ctx, width, height, time, energy, accentRgb);
  } else if (persona === 'edith') {
    paintEdithCore(ctx, width, height, time, energy, accentRgb);
  } else {
    paintGeodesicCore(ctx, width, height, time, energy, accentRgb);
  }
}

export function mountPersonaCore(canvas, initialOptions = {}) {
  const ctx = canvas.getContext('2d');
  if (!ctx) {
    throw new Error('Could not acquire 2D context for PersonaCore canvas.');
  }

  let persona = normalizePersonaId(initialOptions.persona);
  let energy = initialOptions.energy ?? 0.2;
  let accentColor = initialOptions.accentColor ?? null;
  let active = initialOptions.active ?? true;
  let showStarfield = initialOptions.showStarfield ?? false;
  let starCount = initialOptions.starCount ?? 78;
  let nebulaIntensity = initialOptions.nebulaIntensity ?? 1.0;

  let rafId = null;
  let startMs = null;
  let destroyed = false;

  const renderFrame = (nowMs) => {
    if (destroyed) return;
    if (startMs === null) startMs = nowMs;
    const elapsedSec = (nowMs - startMs) / 1000.0;

    const dpr = window.devicePixelRatio || 1;
    const cssWidth = canvas.clientWidth || canvas.width || 240;
    const cssHeight = canvas.clientHeight || canvas.height || 240;
    const targetW = Math.max(1, Math.round(cssWidth * dpr));
    const targetH = Math.max(1, Math.round(cssHeight * dpr));

    if (canvas.width !== targetW || canvas.height !== targetH) {
      canvas.width = targetW;
      canvas.height = targetH;
    }

    ctx.save();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, cssWidth, cssHeight);

    if (showStarfield) {
      paintStarfield(ctx, cssWidth, cssHeight, elapsedSec, {
        persona,
        energy,
        accentColor,
        starCount,
        nebulaIntensity,
      });
    }

    paintPersonaCore(ctx, cssWidth, cssHeight, elapsedSec, {
      persona,
      energy,
      accentColor,
    });
    ctx.restore();

    if (active && !document.hidden) {
      rafId = window.requestAnimationFrame(renderFrame);
    } else {
      rafId = null;
    }
  };

  const syncLoop = () => {
    if (destroyed) return;
    const shouldRun = active && !document.hidden;
    if (shouldRun && rafId === null) {
      rafId = window.requestAnimationFrame(renderFrame);
    } else if (!shouldRun && rafId !== null) {
      window.cancelAnimationFrame(rafId);
      rafId = null;
    }
  };

  const onVisibility = () => syncLoop();
  document.addEventListener('visibilitychange', onVisibility);
  syncLoop();

  return {
    setPersona(next) {
      persona = normalizePersonaId(next);
    },
    setEnergy(next) {
      energy = clamp(Number(next) || 0, 0.0, 1.2);
    },
    setAccentColor(next) {
      accentColor = next || null;
    },
    setActive(next) {
      active = Boolean(next);
      syncLoop();
    },
    setShowStarfield(next) {
      showStarfield = Boolean(next);
    },
    destroy() {
      destroyed = true;
      if (rafId !== null) {
        window.cancelAnimationFrame(rafId);
        rafId = null;
      }
      document.removeEventListener('visibilitychange', onVisibility);
    },
  };
}
