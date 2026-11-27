# Núcleos de Personalidade — U.L.T.R.O.N. (Export Desktop)

Pacote isolado e autossuficiente contendo **exclusivamente os 4 núcleos 3D das personalidades** do U.L.T.R.O.N. Mobile, sem dependências de STT, Obsidian ou serviços mobile.

## Os 4 Núcleos Incluídos

| ID | Nome | Cor Principal | Geometria 3D |
| --- | --- | --- | --- |
| `ultron` | **U.L.T.R.O.N.** | `#F10D28` (Vermelho Carmesim) | Icosaedro externo + esfera geodésica subdividida (42 vértices / 120 arestas) + anéis orbitais + feixe diagonal + shader GLSL |
| `jarvis` | **J.A.R.V.I.S.** | `#2563EB` (Azul Cobalto) | Dodecaedro 3D (20 vértices / 30 arestas) + esfera lat/lon interna + 3 gimbals HUD segmentados + grade polar e nós de dados |
| `visao` | **VISÃO** | `#F59E0B` (Amarelo Âmbar) | Cristal octaedro alongado da Joia da Mente (faces translúcidas ordenadas por profundidade) + dupla hélice + fragmentos + levitação e batimento |
| `edith` | **E.D.I.T.H.** | `#14B8A6` (Verde-Água) | *Stella Octangula* (2 tetraedros em contrarrotação) + prisma hexagonal + radar com varredura + arcos *lock-on* + enxame de micro-drones |

---

## Arquivos Exportados

- `personality_cores.js` — Port 1:1 em **JavaScript ES Module** (Canvas 2D puro, zero dependências). Inclui `paintPersonaCore`, `paintStarfield`, `mountPersonaCore` e `PERSONA_CORES`.
- `personality_cores.d.ts` — Tipagens **TypeScript** completas para `personality_cores.js`.
- `PersonaCore.tsx` — Componente **React/TSX** pronto para Electron / Vite / Tauri (`<PersonaCore persona="ultron" energy={0.25} size={240} showStarfield />`).
- `personality_cores.dart` — Extração autossuficiente em **Flutter/Dart** (`CoreOrb`, `CorePainter`, `CoreStarfieldBackdrop`, `PersonaCoreSpec`, `PersonaCoreId`), caso o Desktop também use Flutter.
- `crimson_core.frag` — Shader **GLSL** original da singularidade carmesim do núcleo U.L.T.R.O.N.
- `personas_cores.json` — Paletas, títulos, taglines, estilos e diretivas de prompt em JSON para consumo direto no backend Python/Node.
- `preview.html` — Página de visualização local com seletor dos 4 núcleos, modo grade 4-em-1 e controle de energia.

---

## Como usar no U.L.T.R.O.N. Desktop

### 1. HTML / PyWebView / Electron (JS puro)
```html
<canvas id="core" style="width: 260px; height: 260px;"></canvas>
<script type="module">
  import { mountPersonaCore } from './personality_cores.js';

  const core = mountPersonaCore(document.getElementById('core'), {
    persona: 'ultron', // 'ultron' | 'jarvis' | 'visao' | 'edith'
    energy: 0.25,      // 0.0 (idle) a 1.2 (falando/ativo)
    showStarfield: true,
  });

  // Trocar personalidade ou reatividade de áudio dinamicamente:
  core.setPersona('jarvis');
  core.setEnergy(0.85);
</script>
```

### 2. React / TypeScript (Electron / Vite)
```tsx
import { PersonaCore } from './PersonaCore';

<PersonaCore persona="edith" energy={audioLevel} size={260} showStarfield />
```

### 3. Python (PyWebView / backend Desktop)
Carregue `personas_cores.json` para sincronizar cores, `promptDirective` e `defaultStyle`, e sirva `personality_cores.js` na WebView do Desktop.

### 4. Testar localmente no navegador
Como `preview.html` usa ES Modules, abra via qualquer servidor estático local:
```bash
python -m http.server 8080
# Acesse: http://localhost:8080/preview.html
```
