# 🔴 U.L.T.R.O.N. 2.0 — Mobile (`v0.6.0`)

Nó autônomo Android desenvolvido em **Flutter / Dart + Kotlin Nativo**, projetado para operar com estética tática **AMOLED Carmesim**, segurança **Fail-Closed**, controle direto sobre o hardware do celular e integração nativa com múltiplos provedores de IA.

> **Alvo de Referência**: Dispositivos Android `arm64-v8a` (ex.: Samsung Galaxy A34 5G — Dimensity 1080, Mali-G68, 6–8 GB RAM), sem pesos de LLM locais para preservar bateria, memória e temperatura.

---

## ⚡ O que o U.L.T.R.O.N. Mobile faz atualmente

### 1. 📱 Controle Nativo do Celular e Hardware Android (`MethodChannel`)
Comandos executados instantaneamente (mesmo offline), pela aba **CELULAR** (`/device`) ou pedindo em linguagem natural para a IA:
- **Lanterna / Flash LED**: Liga, desliga ou alterna o flash traseiro (`/lanterna`, `"ligar lanterna"`, `"apagar luz"`).
- **Volume e Áudio do Sistema**: Ajusta o volume de mídia de `0%` a `100%`, aumenta, diminui ou silencia (`"volume 80"`, `"aumentar volume"`, `"silenciar"`).
- **Lançador de Aplicativos**: Abre apps conhecidos (WhatsApp, YouTube, Instagram, Chrome, Spotify, Gmail, Maps, Telegram, Calculadora, Galeria, Play Store, Netflix, TikTok) ou **qualquer aplicativo instalado** buscando pelo nome no Android (`"abrir whatsapp"`, `"abrir câmera"`).
- **Painéis do Sistema Android**: Abre diretamente as configurações nativas de **Wi-Fi**, **Bluetooth**, **Brilho/Tela**, **Som**, **Bateria**, **GPS/Localização**, **Segurança** e **Aplicativos** (`"abrir wifi"`, `"configurar bluetooth"`).
- **Alarmes e Temporizadores (Timers)**: Cria despertadores e contagens regressivas direto no Relógio do sistema (`"alarme 07:30"`, `"timer 10 minutos"`).
- **Telemetria Real de Hardware**: Lê em tempo real **nível e temperatura da bateria (`°C`)**, **status de carregamento**, **memória RAM usada/total/livre (`MB`)**, **modelo do aparelho**, **versão do Android** e **status de rede** (`"status da bateria"`, `"memória ram"`).
- **Discador, Vibração e Web**: Abre o discador com número preenchido (`"ligar para ..."`), aciona o motor háptico (`"vibrar"`) e realiza buscas na web (`"pesquisar ..."`).

### 2. 🧠 IA Multi-Provedor com Failover e Auto-Discovery
- **Modelos Atualizados de Fábrica**:
  - **Groq (`openai/gpt-oss-120b` e `qwen/qwen3-32b`)**
  - **Google Gemini (`gemini-2.5-flash`)**
  - **OpenAI (`gpt-4.1-mini`)**
  - **API Customizada** (OpenRouter, DeepSeek, Ollama, etc.)
- **Auto-Discovery (`/models`) e Migração Automática**: Se um modelo antigo (como Llama depreciado) estiver salvo ou sair do ar, o U.L.T.R.O.N. migra automaticamente e consulta a lista `/models` ativa da API para continuar respondendo sem falhar.
- **Failover em Cadeia**: Alterna automaticamente para o próximo provedor configurado em caso de erro de rede ou limite de cota.
- **Tags de Ação (`[ACTION:...]`)**: A IA executa ações físicas no aparelho enquanto conversa com o operador.

### 3. 📓 Obsidian "Quick Captures" e Skills Locais (`.md`)
- **Quick Captures no Diário (`Diario/AAAA-MM-DD.md`)**:
  - Registra notas rápidas com timestamp ISO-8601 no cofre local (`ULTRON-Vault/Diario/`).
  - Comandos: `/note <texto>`, `"Ultron, anote: revisar sensores"` ou pelo campo rápido na aba **CELULAR**.
- **Skills Procedurais Mobile (`Skills/*.md`)**:
  - Executa rotinas em Markdown que combinam múltiplos comandos do Android. Inclui 3 skills de fábrica:
    - `modo_estudo.md`: Silencia mídia e inicia Pomodoro de 25 minutos.
    - `foco_noturno.md`: Apaga lanterna e reduz volume para 15%.
    - `alerta_tatico.md`: Aciona lanterna traseira no máximo e dispara vibração de alerta.
  - Comandos: `/skills`, `/skill modo_estudo`, `"ativar modo estudo"` ou pelos botões rápidos na aba **CELULAR**.

### 4. 🧭 Sensores de Contexto e Gestos Físicos
- **Flip-to-Shush (Virar para Calar)**: Virar o celular com a tela para baixo na mesa interrompe imediatamente a fala do assistente (usa o acelerômetro apenas com a tela ativa, zero drenagem em segundo plano).
- **Modo Foco Noturno**: Ao carregar entre 22h e 06h (ou pelo botão **NOTURNO**), reduz o brilho do núcleo para `35%` e ativa o **Modo Sussurro** no TTS.
- **Vigilância de Bateria Crítica (`< 15%`)**: Pausa automaticamente o renderizador orbital de 60 FPS (`CoreStage.hidden`) para economizar GPU quando a bateria entra em nível crítico fora do carregador.

### 5. 🛡️ Segurança *Fail-Closed*, Modo Coação (*Duress PIN*) e Kill Switch
- **Biometria Nativa (`local_auth`) + Cofre de PIN (`PBKDF2-HMAC-SHA256`, 120.000 iterações)**:
  - Armazenado no Android Keystore via `flutter_secure_storage`, com bloqueio exponencial contra força bruta (30s até 15 min após 5 falhas).
- **PIN de Coação (*Duress PIN* / Modo Camuflado)**:
  - Configurável em `/security`. Se digitado na tela de desbloqueio sob coação, o app **apaga silenciosamente o histórico de conversas** e abre um aplicativo falso de **"Bloco de Notas Pessoal"** (`AccessLevel.guarded`).
- **Kill Switch Remoto do PC (LAN / Webhook)**:
  - Envia um pacote JSON assinado com `HMAC-SHA256` para o endpoint do computador na rede local para travar/suspender a estação de trabalho e bloqueia a sessão mobile (`/killswitch`, `"travar pc"` ou botão de emergência em `/security`).

### 6. 🎛️ Interface Tática, Voz e Atualizador OTA
- **Núcleo Orbital 60 FPS (`CorePainter`)**: Alterna entre **Modo Centro**, **Modo Palco** (relatórios isolados com núcleo no canto) e **Modo Tela Cheia** (GPU desligada).
- **Voz Sintetizada Nativa (`flutter_tts`)**: Timbre grave (`pitch: 0.55`) em `pt-BR`.
- **Histórico Local em SQLite (`/history`)**: Busca instantânea por mensagens e limpeza rápida, excluído de backups em nuvem (`allowBackup=false`).
- **Atualizador GitHub OTA**: Verifica novas releases no GitHub, valida a integridade `SHA-256` do APK e dispara a instalação local.

---

## 💬 Comandos Rápidos (Slash Commands & Voz)

| Comando / Voz | Função |
| :--- | :--- |
| `/help` | Abre o guia de sintaxe e comandos disponíveis |
| `/device` ou `/celular` | Abre o painel de controle de hardware, notas e skills |
| `/lanterna` ou `"ligar lanterna"` | Liga ou desliga o flash LED traseiro |
| `/note <texto>` ou `"anote: <texto>"` | Salva uma nota rápida em `Diario/AAAA-MM-DD.md` |
| `/skills` ou `/skill <nome>` | Lista ou executa uma skill local em `Skills/*.md` |
| `/security` ou `/security lock` | Abre o Painel de Segurança (Duress PIN / Kill Switch) ou trava a sessão |
| `/killswitch` ou `"travar pc"` | Dispara o pacote de bloqueio remoto para o PC e trava o celular |
| `/settings` | Configura provedores de IA, chaves de API e modelos ativos |
| `/history` | Abre o histórico de conversas salvo no SQLite |
| `"palco"` / `"tela cheia"` | Alterna o estágio visual do núcleo orbital |

---

## 🏗️ Arquitetura do Projeto

```text
lib/
├── core/security/
│   ├── auth_gate.dart              # Máquina de estados (locked, guarded/duress, session)
│   └── pin_vault.dart              # Verificador PBKDF2-HMAC-SHA256 (PIN normal + Duress PIN)
├── models/
│   └── chat_message.dart           # Modelo de mensagens persistidas no SQLite
├── services/
│   ├── ai_provider_service.dart    # Cliente OpenAI-compatible, failover, presets e auto-discovery
│   ├── app_update_service.dart     # Atualizador OTA via GitHub Releases com validação SHA-256
│   ├── conversation_history.dart   # Persistência SQLite local
│   ├── device_control_service.dart # Ponte MethodChannel Android + parser natural + Kill Switch
│   ├── obsidian_service.dart       # Cofre Markdown local (Diario/ e Skills/*.md)
│   ├── slash_command_parser.dart   # Parser determinístico de comandos /slash
│   └── voice_service.dart          # TTS nativo pt-BR + Modo Sussurro
└── ui/screens/
    ├── auth_screen.dart            # HUD de desbloqueio biométrico e teclado PIN tático
    ├── core_screen.dart            # Tela principal, núcleo 60 FPS, painéis e modo camuflado
    ├── ai_settings_screen.dart     # Gerenciador de provedores, modelos e atualizador
    ├── conversation_history_screen.dart
    └── update_screen.dart
android/
└── app/src/main/
    ├── kotlin/.../MainActivity.kt  # Ponte nativa Android (CameraManager, AudioManager, SensorManager, Intents)
    └── res/                        # Adaptive Icon vetorial + ícones U.L.T.R.O.N. em todas as densidades
```

---

## 🛠️ Como Compilar e Publicar Releases

### Pré-requisitos Locais
1. Instale o **Flutter SDK (stable)** e o **Android SDK**.
2. Execute:
   ```bash
   flutter pub get
   flutter analyze
   flutter test
   flutter build apk --release --target-platform android-arm64
   ```
   O APK será gerado em `build/app/outputs/flutter-apk/app-release.apk`.

### Esteira CI/CD e Releases Automáticos (GitHub Actions)
- **Flutter CI (`.github/workflows/flutter-ci.yml`)**: Executado a cada push ou PR na `main` (roda `flutter analyze`, `flutter test`, compila o APK de debug e valida permissões e `applicationId`).
- **Android Release (`.github/workflows/android-release.yml`)**: Ao enviar uma tag no formato `vX.Y.Z` (ex.: `git tag v0.6.0 && git push origin v0.6.0`), o GitHub Actions compila o APK `arm64` assinado com os segredos do repositório (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`), verifica a assinatura com `apksigner` e publica automaticamente na aba **Releases** do GitHub.
