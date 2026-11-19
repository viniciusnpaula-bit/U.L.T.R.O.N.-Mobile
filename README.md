# 🔴 U.L.T.R.O.N. 2.0 — Mobile (`v1.4.2`)

Nó autônomo Android desenvolvido em **Flutter / Dart + Kotlin Nativo**, projetado com **Núcleo Holográfico Shader (`CoreOrb`)**, estética tática **AMOLED Carmesim**, banco local criptografado **SQLCipher**, segurança **Fail-Closed**, **Action Gate tático**, **25 Slash Commands determinísticos**, **RAG Lexical FTS5 (Obsidian)**, **Visão Multimodal (VLM)**, **Agenda Android (`CalendarContract`) + Briefing Matinal Unificado**, **Log Imutável de Auditoria (SHA-256) + Bridge HTTP IoT em `Skills/*.md`**, **Sentinela de Voz não-Google (`AudioRecord` + Eco-VAD + `sherpa-onnx` KWS)** e **Bridge Bidirecional Desktop LAN**.

> **Alvo de Referência**: Dispositivos Android `arm64-v8a` (ex.: Samsung Galaxy A34 5G — Dimensity 1080, Mali-G68, 6–8 GB RAM), sem pesos de LLM locais para preservar bateria, memória e temperatura.

---

## ⚡ O que o U.L.T.R.O.N. Mobile faz atualmente

### 1. 📱 Controle Nativo do Celular, Hardware e Mídia (`MethodChannel`)
Comandos executados instantaneamente (mesmo offline), pela aba **CELULAR** (`/device`), pelos **Quick Settings Tiles** ou pedindo em linguagem natural para a IA:
- **Lanterna / Flash LED**: Liga, desliga ou alterna o flash traseiro (`/lanterna`, `"ligar lanterna"`, `"apagar luz"`).
- **Volume, Áudio e Controle Universal de Mídia**: Ajusta volume de mídia de `0%` a `100%` e envia comandos universais de `play`, `pause`, `play_pause`, `next`, `previous` e `stop` via `AudioManager` (`KEYCODE_MEDIA_*`) para Spotify, YouTube Music e outros players.
- **Lançador Universal de Apps & Painéis Android**: Abre apps conhecidos ou qualquer app instalado buscando no `PackageManager`, além de painéis nativos (**Wi-Fi**, **Bluetooth**, **Tela**, **Som**, **Bateria**, **Localização**, **Segurança**, **Apps**).
- **Alarmes, Timers, Discador, Vibração e Web**: Cria despertadores e timers no Relógio nativo, abre o discador, aciona motor háptico e abre buscas na web.
- **Telemetria Real de Hardware**: Lê nível e temperatura da bateria (`°C`), carregamento, RAM usada/total/livre (`MB`), modelo, versão Android e status de rede.

### 1B. 📨 Sentinela de Mensagens & Comunicação Autônoma (`NotificationListenerService` + `RemoteInput`)
- **Captura em Tempo Real (WhatsApp, Telegram, Instagram, SMS, Gmail, Discord)**: Lê em voz alta (`/mensagens`, `"ler mensagens"`) e gera **Resumo Tático por IA** filtrando ruídos.
- **Resposta Silenciosa em 2º Plano (`RemoteInput`) e Envio Ativo (`ContactsContract`)**: Responde notificações sem abrir o app (`"responder: ..."`, `/reply`) e resolve contatos da agenda para WhatsApp/SMS — **protegidos pelo `ActionGate` Fail-Closed com confirmação explícita antes do disparo**.

### 1C. 🎙️ Motor de Voz Neural Não-Google, Wake Word (`sherpa-onnx`), Push-to-Talk e Fish Studio TTS
- **Captura PCM Nativa (`AudioRecord` + AEC/NS/AGC) & Eco-VAD 24h (`UltronAudioService`)**: Escuta em primeiro plano e serviço de 2º plano com `AudioCaptureSource` (Zero popup do Google), segmentação VAD (`AudioVadBuffer`) e `GroqWhisperSttService` + fallback nativo.
- **Hotword Offline (`sherpa-onnx` Zipformer KWS + `UltronWakeWordRecognizer`)**: Reconhece `"Ei Ultron"` / `"Ultron"` com suporte a ativação sobre a tela de bloqueio e opt-in de reinício pós-boot (`BootReceiver`).
- **Push-to-Talk + Barge-in Seletivo + Fish Studio TTS + TTS Nativo**: Segure 🎤 na barra de comandos para Push-to-Talk, escolha entre **3 perfis de timbre (`GRAVE`, `NATURAL`, `ÁGIL`)**, síntese neural **Fish Studio** ou fallback nativo `pt-BR`, e modo sussurro noturno.
- **Dicionário Fonético & Atalhos (`/memory`)**: Correções PT-BR personalizadas (`VoiceCorrectionsService`) e atalhos de voz com confirmação (`VoiceShortcutsService`).

### 2. 🧠 Central de IA 100% Gratuita (9 Provedores) + Visão Multimodal VLM (P2)
- **Zero-Key Out-of-the-Box + 9 Provedores Gratuitos**: **Pollinations AI** (sem chave), Groq Cloud (`openai/gpt-oss-120b`, `meta-llama/llama-4-scout-17b-16e-instruct`), Google Gemini (`gemini-2.5-flash`), OpenRouter (`:free` + `qwen/qwen2.5-vl-72b-instruct:free`), Cerebras, GitHub Models, Mistral, SambaNova e HuggingFace.
- **Auto-Discovery (`/models`) e Failover Inteligente (`AiFailover`)**: Prioriza automaticamente modelos multimodais quando uma imagem é anexada (`requiresVision`).
- **Visão Multimodal Nativa (`P2` — Câmera & Galeria -> VLM)**:
  - Botão 📷 ao lado da barra de comandos e comando `/visao` (`/visao`, `/visao galeria`, `/ocr`).
  - Captura via `FileProvider` + `ACTION_IMAGE_CAPTURE` ou galeria (`ACTION_GET_CONTENT`), corrige rotação EXIF, redimensiona para `<= 1024px`, comprime JPEG Base64 em memória e envia direto para o VLM com pré-visualização inline.

### 3. 📓 Segundo Cérebro Obsidian, RAG Lexical FTS5 (P1) e Skills Locais (`.md`)
- **Quick Captures no Diário (`Diario/AAAA-MM-DD.md`), Inbox e Memória (`/note`, `/vault`, `[ACTION:REMEMBER]`)**.
- **Busca & RAG Lexical Local (`P1` — `VaultSearchService` via SQLite FTS5/FTS4/BM25)**:
  - Indexa incrementalmente todo o cofre Markdown (`ULTRON-Vault`) em SQLite (< 5 MB de RAM) e injeta trechos relevantes no contexto da IA automaticamente durante a conversa.
  - Consulta direta com `/buscar <termo>` (`/search`, `/rag`) ou `"buscar nas notas: <termo>"`.
- **Skills Procedurais Mobile (`Skills/*.md`)**: Rotinas executáveis com `[ACTION:...]` (`modo_estudo.md`, `foco_noturno.md`, `alerta_tatico.md`) via `/skills` e `/skill <nome>`.

### 4. 🧭 Sensores de Contexto e Núcleo Holográfico Shader 60 FPS
- **Núcleo Holográfico GLSL (`shaders/crimson_core.frag` + `CoreOrb`)**: Anéis energéticos reativos à voz (`speechRms`), estados **Centro**, **Palco** e **Tela Cheia** (GPU desligada).
- **Flip-to-Shush, Modo Foco Noturno (22h–06h) e Vigilância de Bateria (`< 15%`)**.

### 5. 🛡️ Segurança *Fail-Closed*, SQLCipher, Duress PIN, Action Gate & Bridge Desktop LAN (P3)
- **Biometria (`local_auth`) + PIN (`PBKDF2-HMAC-SHA256`, 120.000 iterações) + PIN de Coação (*Duress PIN*)**.
- **Banco Criptografado SQLCipher v2 (`DatabaseKeyVault` + `ConversationHistory`)**: Chave de 256 bits no Keystore e migração automática; `/clear` expurga tanto RAM quanto SQLCipher.
- **Action Gate Tático**: Classifica ações (`safe`, `sensitive`, `critical`) e exige confirmação explícita do Operador para ações sensíveis (`WHATSAPP`, `SMS`, `REPLY_MESSAGE`, `DIAL`, `PC_OPEN_APP`, `PC_MEDIA`, `PC_CLIPBOARD_*`, `PC_RUN_SKILL`) e críticas (`KILL_SWITCH`, `CLEAR_HISTORY`).
- **Bridge Bidirecional Desktop LAN & Kill Switch (`P3` — `/desktop`, `/pc`, `/killswitch`)**:
  - Pareamento LAN assinado com **HMAC-SHA256 + Timestamp + Nonce + verificação de assinatura na resposta (`X-Ultron-Signature`)**.
  - Kill Switch Fail-Closed que exige chave HMAC explícita configurável em `/security` (**FIXAR IP** / **CHAVE** / **GERAR**).
  - Subcomandos diretos via `/pc`: `/pc status`, `/pc abrir <app>`, `/pc midia <acao>`, `/pc copiar <texto>`, `/pc colar` e `/pc skill <nome>`.

### 6. 📅 Agenda Android (`CalendarContract`) & Briefing Matinal Unificado (P4)
- **Leitura e Escrita Nativa de Agenda (`/agenda`, `/calendar`, `"minha agenda"`, `"agendar ..."`)**:
  - Consulta eventos e recorrências reais no Android via `CalendarContract.Instances` (`/agenda hoje`, `/agenda semana`, `/agenda amanha`).
  - Agenda compromissos direto no calendário primário (ou fallback `ACTION_INSERT`) via `/agenda criar <detalhes>` ou `[ACTION:CREATE_EVENT:...]`, sempre protegido por confirmação explícita do **Action Gate**.
- **Briefing Executivo Matinal (`/briefing`, `"bom dia"`, `"briefing matinal"`)**:
  - `BriefingService` cruza em paralelo **Clima atual (sem chave de API)**, **Compromissos do dia (`CalendarContract`)**, **Mensagens recentes da Sentinela** e **Telemetria do dispositivo**, gerando relatório tático + leitura em voz alta. Permite fixar cidade com `/briefing cidade <nome>`.

### 7. 📜 Log Imutável de Auditoria (SHA-256) & Bridge HTTP em `Skills/*.md` (P5)
- **Trilha de Auditoria Encadeada por SHA-256 (`AuditLogService` + `/audit`)**:
  - Registro local *append-only* (`ultron_audit.db`) em que cada entrada inclui o hash da anterior, permitindo detectar qualquer adulteração via `/audit` ou na aba **SEGURANÇA**.
  - Registra automaticamente Kill Switches, `/pc`, `/clear`, envios de WhatsApp/SMS/Reply, criação de eventos e disparos HTTP.
- **Bridge HTTP / Webhooks IoT em `Skills/*.md` (`[HTTP:METHOD:URL|JSON]`)**:
  - Permite acionar *Home Assistant*, *ESPHome*, *Node-RED* e webhooks locais diretamente dentro das skills Markdown (ex.: `[HTTP:POST:http://192.168.1.50:8123/api/webhook/luz|{"estado":"on"}]`), protegidos pelo **Action Gate**.

### 8. 🌐 Atualizador OTA (`SHA-256`) e Histórico Criptografado (`/history`)
- **Atualizador GitHub OTA**: Verifica releases no GitHub, valida integridade `SHA-256` do APK e inicia instalação local (`REQUEST_INSTALL_PACKAGES`).

---

## 💬 Comandos Rápidos (25 Slash Commands & Voz)

| Comando / Voz | Função |
| :--- | :--- |
| `/help` | Lista todos os 25 Slash Commands disponíveis |
| `/audit` ou `/auditoria` | Verifica cadeia SHA-256 do log imutável de auditoria (**P5**) |
| `/briefing [cidade]` ou `"bom dia"` | Briefing executivo (Agenda + Sentinela + Clima + Telemetria) (**P4**) |
| `/agenda [hoje\|semana\|criar ...]` | Lê compromissos ou agenda novos eventos via `CalendarContract` (**P4**) |
| `/device` ou `/celular` | Painel de hardware, sentinela de mensagens e skills |
| `/buscar <termo>` ou `"buscar nas notas: ..."` | Busca léxica SQLite FTS5/BM25 no cofre Obsidian (**P1**) |
| `/visao [camera\|galeria] [pergunta]` ou `/ocr` | Anexa foto/print comprimido para análise VLM (**P2**) |
| `/desktop` | Tela de pareamento LAN e testes HMAC com o PC |
| `/pc <status\|abrir\|midia\|copiar\|colar\|skill>` | Envia comandos assinados HMAC bidirecionais ao PC (**P3**) |
| `/memory` ou `/memoria` | Correções fonéticas PT-BR, preferências e atalhos por voz |
| `/lanterna` ou `"ligar lanterna"` | Liga/desliga o flash LED traseiro |
| `/note <texto>` / `/vault [ideia]` | Salva nota no Diário ou Inbox do Obsidian |
| `/skills` ou `/skill <nome>` | Lista ou executa skills Markdown em `Skills/*.md` |
| `/mensagens` / `/reply <texto>` | Lê mensagens capturadas ou responde em 2º plano |
| `/models` | Lista modelos ativos ao vivo (Auto-Discovery) |
| `/security` / `/killswitch` / `/lock` | Segurança, Duress PIN, chave HMAC LAN e Kill Switch |
| `/settings` / `/history` / `/clear` | Provedores de IA, histórico SQLCipher e expurgo seguro |
| `/voice` / `/status` | Ativa captura de voz ou exibe telemetria rápida |

---

## 🏗️ Arquitetura do Projeto

```text
lib/
├── core/security/
│   ├── action_gate.dart              # Simulação de risco + fail-closed HMAC-SHA256
│   ├── auth_gate.dart              # Máquina de estados (locked, guarded/duress, session)
│   ├── database_key_vault.dart       # Chave SQLCipher 256-bit no Keystore
│   └── pin_vault.dart              # PBKDF2-HMAC-SHA256 (PIN normal + Duress PIN)
├── models/
│   └── chat_message.dart
├── services/
│   ├── ai_provider_service.dart      # 9 provedores, failover inteligente e suporte VLM
│   ├── android_actions_service.dart  # Ponte de ações protegida pelo AuthGate
│   ├── app_update_service.dart       # Atualizador OTA GitHub com SHA-256
│   ├── audio_capture_service.dart    # AudioRecord PCM + VAD (não-Google)
│   ├── audit_log_service.dart        # Log append-only encadeado com SHA-256 (P5)
│   ├── briefing_service.dart         # Clima + Agenda + Sentinela + Telemetria (P4)
│   ├── conversation_history.dart     # Persistência SQLCipher v2 com migração
│   ├── desktop_pairing_service.dart  # Bridge LAN HMAC-SHA256 bidirecional + nonce
│   ├── device_control_service.dart   # MethodChannel, Vision, RAG, Agenda, HTTP Bridge e Kill Switch
│   ├── obsidian_service.dart         # Cofre Markdown (Diario/, Inbox, Skills/*.md)
│   ├── slash_command_parser.dart     # Parser determinístico de 25 /commands
│   ├── vault_search_service.dart     # Motor de busca/RAG FTS5/FTS4/BM25 local
│   ├── voice_pipeline_controller.dart# Pipeline de voz contínua, PTT e barge-in
│   └── voice_service.dart            # Fish Studio TTS + TTS nativo pt-BR
└── ui/
    ├── screens/                      # Auth, Core (CoreOrb shader), DesktopPairing, Memory, AI Settings, History, Update
    └── widgets/                      # CoreOrb, ActionConfirmationDialog, VoiceSelectorSheet
android/
└── app/src/main/
    ├── kotlin/.../MainActivity.kt    # Ponte nativa (Hardware, MediaSession, NotificationSentinel, CalendarContract, AudioRecord, FileProvider Vision)
    ├── res/xml/file_paths.xml        # FileProvider seguro para capturas temporárias de Visão
    └── assets/                       # Modelo sherpa-onnx Zipformer KWS (offline Wake Word)
shaders/
└── crimson_core.frag                 # Fragment shader GLSL do Núcleo Holográfico
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
- **Android Release (`.github/workflows/android-release.yml`)**: Ao enviar uma tag no formato `vX.Y.Z` (ex.: `git tag v0.6.0 && git push origin v0.6.0`), o GitHub Actions compila o APK `arm64` assinado com os segredos do repositório (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`), verifica a assinatura com `apksigner` e publica automaticamente na aba **Releases** do GitHub. Consulte [docs/release-checklist.md](docs/release-checklist.md) para o checklist de validação no Galaxy A34 5G.

### 7. 🔒 Pipeline de Áudio, Memória SQLCipher e Pareamento Desktop LAN
- **Banco Criptografado SQLCipher v2 (`DatabaseKeyVault` + `ConversationHistory`)**: Chave aleatória de 256 bits no `flutter_secure_storage` com migração atômica do SQLite legado (`ultron_conversations.db`).
- **Pipeline Whisper STT + VAD (`AudioCaptureSource`, `VadSegmenter`, `GroqWhisperSttService`, `VoicePipelineController`)**: Captura PCM em memória com AEC/NS/AGC nativo, detecção de fala/silêncio, filtros anti-alucinação Whisper, Push-to-Talk e modo contínuo com barge-in seletivo.
- **Memória, Correções PT-BR e Atalhos (`/memory`)**: Correções fonéticas persistidas (`VoiceCorrectionsService`), preferências e atalhos por voz com confirmação explícita em `MemorySettingsScreen`.
- **Desktop LAN & Quick Settings Tile (`/desktop`)**: Pareamento LAN assinado com HMAC-SHA256 (`DesktopPairingService`) e atalho rápido na barra do Android (`UltronTileService`) sempre protegido pelo `AuthGate`.
