# U.L.T.R.O.N. 2.0 — Mobile (`v1.5.0`)

Nó autônomo Android desenvolvido em **Flutter / Dart + Kotlin Nativo**, projetado com **Núcleo Geodésico 3D (`CoreOrb` + GLSL Shader)**, interface limpa **AMOLED Carmesim contido** com **Navegação Lateral responsiva (10 seções)**, **Auto-VAD Adaptativo**, **Continuidade de Resposta/TTS em Segundo Plano**, **Triagem Inteligente de Notificações em Tempo Real + Obsidian**, **Camada Cognitiva & Guardrails Anti-Alucinação**, **Modos Táticos Isolados (`/modo`)**, **Segundo Cérebro Obsidian (`Inventario/`, `Pessoas/`, RAG FTS5/BM25)**, **Projetista Elétrico Industrial (`/eletrica` NBR 5410 + Ponte CADe_SIMU)**, **ETL em Lote (`/etl`)**, **Recibos Epistemológicos (SHA-256) + Checkpoints de Fluxo**, **Segurança Fail-Closed (SQLCipher + Auth Composta Biometria/NFC NDEF)**, **Sentinela de Voz não-Google (`AudioRecord` + `sherpa-onnx` KWS)** e **Bridge Bidirecional Desktop LAN / Tailscale (incl. Mini-Apps Sandboxed)**.

> **Alvo de Referência**: Dispositivos Android `arm64-v8a` (validado em **Samsung Galaxy A34 5G — `SM_A346M`**), mantendo inferência pesada na nuvem gratuita (9 provedores) ou no PC Desktop via LAN para preservar bateria, RAM e temperatura.

---

## Novidades Recentes (`v1.5.x`)
- **Nova Interface Limpa + Núcleo Geodésico 3D (`CoreOrb`)**: Superfícies AMOLED neutras (`#080808` / `#111114` / `#18181D`) com carmesim `#F10D28` contido, malha icosaédrica 3D subdividida sempre visível na tela do chat, apenas 3 atalhos essenciais (`Voz`, `Visão`, `Dispositivos`), telemetria compacta no rodapé e gaveta lateral com 10 seções (barra fixa em tablets).
- **Auto-VAD Adaptativo (Primeiro e Segundo Plano)**: Remoção de offset DC (`dcRemovedRmsInt16`), piso de ruído ambiente com EMA assimétrico, histerese dupla para não cortar finais de fala, filtro de cliques/batidas no início, 3 perfis configuráveis (`Silencioso`, `Balanceado`, `Ruidoso`) e pausa ajustável em **Configurações**, além de `AcousticEchoCanceler` + `NoiseSuppressor` no `BackgroundVoiceResponder.kt`.
- **Continuidade em Segundo Plano (`ResponseContinuityService`)**: Respostas longas da IA e síntese de voz (TTS) continuam executando e falando mesmo ao sair do app ou bloquear a tela, com notificação de controle **Parar fala** e entrega de notificação expansível caso o áudio esteja no mudo.
- **Triagem Inteligente de Notificações em Tempo Real (`UltronNotificationService` + `SmartNotificationTriageService`)**: Monitoramento orientado a eventos (zero polling) para WhatsApp, Telegram e E-mail, com score composto offline (palavras-chave PT-BR, contatos VIP, detecção de rajada 3+ msgs/60s, anti-loop, deduplicação SHA-256, filtro de promoções/OTP e Foco Noturno), alertas acionáveis (*Ouvir* / *Silenciar*) e registro automático em `Inbox/Urgencias_AAAA-MM-DD.md` no Obsidian.

---

## ⚡ Principais Recursos do U.L.T.R.O.N. Mobile

### 1. 📱 Controle Nativo do Celular, Hardware & Mídia Proativa (`MethodChannel`)
Comandos executados instantaneamente (mesmo offline), pela aba **CELULAR** (`/device`), pelos **Quick Settings Tiles**, **Orbe Flutuante Android** ou por voz/texto:
- **Controle Universal de Mídia Proativo e Verificado**: Integração com `MediaSessionManager` + `AudioManager.isMusicActive`. Quando você pede *"continuar a música no Spotify"* com o aplicativo fechado, o U.L.T.R.O.N. **abre o Spotify automaticamente**, tenta retomar a reprodução e **só confirma se o áudio realmente iniciar** (caso contrário, informa honestamente que abriu o app e aguarda o play).
- **Lanterna / Flash LED, Volume, Alarmes, Timers, Discador e Vibração**: Controle nativo imediato.
- **Lançador Universal de Apps & Painéis Android**: Busca apps no `PackageManager` e abre painéis nativos (**Wi-Fi**, **Bluetooth**, **Tela**, **Som**, **Bateria**, **Localização**, **Segurança**, **Apps**).
- **Telemetria Real de Hardware**: Bateria, temperatura (`°C`), RAM usada/total/livre (`MB`), Wi-Fi, Dados Móveis e **Bluetooth**.

### 2. 📊 Telemetria Tática no Cockpit & Central de IA Gratuita (9 Provedores)
- **Barra de Telemetria ao Vivo (`core_screen.dart`)**: Faixa AMOLED Carmesim exibindo `MODO` ativo (clicável), `BRAIN` (com badge **`FAILOVER`** quando o fallback assume), `LAT` (ms), `TOK` (`↑/↓` reais da API ou estimados `~` + turnos), `LAN`, `BT` e `VOZ`.
- **Zero-Key Out-of-the-Box + 9 Provedores Gratuitos**: **Pollinations AI** (sem chave), Groq Cloud, Google Gemini, OpenRouter (`:free`), Cerebras, GitHub Models, Mistral, SambaNova e HuggingFace com circuit breaker e auto-discovery (`/models`).
- **Visão Multimodal + Memória Visual de Sessão (`/visao`, `/ocr`)**: Captura via câmera/galeria com compressão JPEG em memória e contexto visual persistente durante a sessão para perguntas encadeadas (*"qual o valor desse resistor?"*, *"isso é compatível com 220V?"*) sem reabrir a câmera.

### 3. 🧠 Camada Cognitiva Determinística & Guardrails (`CognicaoService`)
- **Pré-processador Local (Zero Custo de Tokens)**: Detecta urgência/comandos diretos (reduz janela de histórico para economizar tokens) e temas sensíveis (zera sarcasmo/humor e ajusta tom do TTS).
- **Isolamento OCR/Visão Anti-Prompt-Injection**: Encapsula textos extraídos de imagens em `<UNTRUSTED_VISUAL_DATA>` e neutraliza tags `[ACTION:...]` ou instruções embutidas em fotos.
- **Pós-processador Anti-Alucinação**: Cruza a fala do LLM com as ferramentas efetivamente confirmadas no turno e bloqueia o TTS de anunciar ações que falharam ou não foram executadas.

### 4. 🎯 Modos Táticos Isolados ("Helpers" — `/modo`)
- 5 perfis pré-configurados: **`geral`**, **`engenharia`**, **`estudos`**, **`treino`** e **`dev`**.
- Cada modo especialista:
  - Consulta apenas sua subpasta do cofre Obsidian no RAG FTS5 (ex.: `Memoria/Engenharia/` vs `Memoria/Treino/`).
  - Isola o histórico em `ConversationHistory` (`conversationId` próprio).
  - Monta um system prompt enxuto com apenas as categorias de ferramentas relevantes (preservando núcleo mínimo global como notas, lembretes, timer e volume).

### 5. 📓 Segundo Cérebro Obsidian, Arquivo de Vida (`Inventario/` & `Pessoas/`) e RAG FTS5
- **Estrutura Padronizada**: `Diario/`, `Memoria/`, `Inbox/`, **`Inventario/`**, **`Pessoas/`** e `Skills/*.md`, com CRUD completo e pilha **Undo** (`/desfazer`).
- **Arquivo de Vida & Garantias (`Skills/garantias.md`)**: Fluxo integrando `/visao`/`/ocr` → extração estruturada (`Produto`, `Data de Compra`, `Prazo de Garantia`, `Procedimento de Reset`) → nota YAML/Markdown em `Inventario/` → lembrete automático 15 dias antes do vencimento.
- **Persistência de Lembretes Pós-Reboot**: `ReminderService` + `ReminderAlarmReceiver` + `BootReceiver` restauram automaticamente todos os alarmes `PENDING` futuros após reinicialização (`BOOT_COMPLETED`) ou atualização do APK (`MY_PACKAGE_REPLACED`).
- **Fichas em `Pessoas/` + Filtro de Privacidade**: `ObsidianService.sanitizeForExternalAi()` remove linhas privadas e redige telefones, e-mails, endereços e CPFs antes de enviar qualquer contexto do cofre a APIs externas.

### 6. ⚡ Projetista Elétrico Industrial Offline & Ponte CADe_SIMU (`/eletrica`)
- **Motor Offline (`EletricaEngine`)**: Tabelas de ampacidade **NBR 5410 (Método B1)**, dimensionamento de cabos, disjuntores, contatores e relés térmicos com memória de cálculo.
- **Parametrização de Inversores**: Referência rápida para **WEG CFW500** (`P0100..P0404`) e **Altus AD600M**.
- **Topologias & Auditoria Estrutural**: Gera *Partida Direta*, *Reversão*, *Estrela-Triângulo* e *Sequência de Motores* auditando curto na fonte (`SHORT_CIRCUIT`), bobina aberta (`OPEN_COIL`), falta de proteção (`MISSING_PROTECTION`) e falta de intertravamento (`MISSING_INTERLOCK`).
- **Exportação Netlist + Diagrama SVG IEC**: Salva em `Memoria/Engenharia/` no Obsidian e envia opcionalmente a Netlist ao clipboard do Desktop via Ponte LAN (`PC_CLIPBOARD_PUSH`) para apoio ao CADe_SIMU *(nota transparente: não gera `.cad` binário proprietário nem executa simulação SPICE no celular)*.

### 7. 🗂️ Utilitários de Arquivos (SAF) & ETL em Lote (`/arquivos`, `/etl`)
- **Limpeza de Duplicados SHA-256** (`/limpar_duplicados`), **Conversão de Imagens** `.webp`/`.heic` → `.jpg`/`.png` (`/converter_imagens`) e **Padronização de PDFs** `AAAA-MM-DD - Assunto.pdf` (`/organizar_pdf_downloads`).
- **ETL em Lote (`/etl [saf|pasta]`)**: Seleção múltipla via SAF (`ACTION_OPEN_DOCUMENT` + `EXTRA_ALLOW_MULTIPLE`), consolidação offline de `.txt`/`.md`/`.csv` e delegação híbrida de PDFs ao Desktop LAN (`PC_EXEC_TOOL:batch_pdf_etl`), salvando tabela Markdown diretamente em `Inbox/ETL_*.md`.

### 8. 🎙️ Motor de Voz Não-Google, Wake Word (`sherpa-onnx`) & Diagnóstico Acústico
- **Regra Permanente Non-Google**: Captura exclusivamente via `AudioRecord` nativo (AEC/NS/AGC), Eco-VAD 24h (`UltronAudioService`), KWS multi-perfil offline `sherpa-onnx` (`Ultron`/`Jarvis`/`Edith`/`Visão`) e STT `GroqWhisperSttService` / endpoint compatível — **zero uso de `SpeechRecognizer`/`RecognizerIntent` do Google**.
- **Diagnóstico Acústico em Campo (`ai_settings_screen.dart`)**: Medidor de ruído ambiente em dBFS (`-60..0 dB`), pré-roll VAD (`600 ms`), latência média medida do Whisper/Groq e contagem de falsos positivos KWS PT-BR.
- **Fish Studio TTS + TTS Nativo pt-BR**, Push-to-Talk, Barge-in seletivo e dicionário fonético (`/memory`).

### 9. 🛡️ Segurança Fail-Closed, Auth Composta, Recibos & Checkpoints
- **SQLCipher v2 (`DatabaseKeyVault`)** + **PIN (`PBKDF2-HMAC-SHA256`)** + **Duress PIN (Coação)** + **NFC** + **Biometria**.
- **Auth Composta (`SovereignAuthPolicy.biometricPlusNfcNdef`)**: Suporte a elevação soberana exigindo **Biometria + Tag NFC com payload NDEF assinado** (rejeitando UID simples clonável).
- **Recibos Epistemológicos em Cadeia SHA-256 (`AuditLogService` / `/audit`)**: Classifica execuções em `CONFIRMED`, `UNCERTAIN` (Intents externos Android) e `FAILED`, com verificação de integridade.
- **Fluxos Agendados com Checkpoints (`/fluxo`, `WorkflowSchedulerService`)**: `runFlowWithCheckpoints()` pausa automaticamente quando uma etapa retorna `UNCERTAIN` e retoma da etapa seguinte sem reexecutar ações já disparadas.

### 10. 💻 Bridge Bidirecional Desktop LAN / Tailscale & Mini-Apps Sandboxed (`/pc`, `/desktop`)
- Comunicação assinada com **HMAC-SHA256 + Timestamp + Nonce + verificação da assinatura de resposta**, aceitando redes privadas LAN e **Tailscale (`100.64.0.0/10` e `.ts.net`)**.
- **Self-Evolving Mini-Apps (`/pc miniapp <título> | <especificação>`)**: Contrato seguro `PC_EXEC_TOOL` (`create_mini_app`) classificado como `RiskLevel.critical` com confirmação obrigatória no `ActionGate`, validação de URL LAN/Tailscale + token de sessão + TTL (especificação e handler Python em [docs/DESKTOP_MINI_APP_CONTRACT.md](docs/DESKTOP_MINI_APP_CONTRACT.md)).
- Controle Spotify Web API (OAuth 2.0 PKCE), Agenda Android (`CalendarContract`), Briefing Matinal (`/briefing`), Sentinela WhatsApp/Notificações (`RemoteInput`) e Atualizador OTA (`SHA-256`).

---

## 💬 Comandos Rápidos (Slash Commands & Voz)

| Comando / Voz | Função |
| :--- | :--- |
| `/help` | Lista todos os Slash Commands disponíveis |
| `/modo [geral\|engenharia\|estudos\|treino\|dev]` | Alterna Modos Táticos isolados (cofre, histórico e ferramentas filtradas) |
| `/eletrica [direta\|reversao\|estrela\|sequencia] [X cv] [220v\|380v] [cfw500\|ad600m] [pc]` | Projetista Elétrico NBR 5410 + Auditoria + Netlist/SVG + Ponte CADe_SIMU |
| `/etl [saf\|pasta]` ou `/arquivos [duplicados\|converter\|pdfs\|lote]` | ETL em lote para `Inbox/` + limpeza SHA-256, conversão e organização de PDFs |
| `/visao [camera\|galeria]` ou `/ocr` | Análise visual VLM + contexto visual persistente na sessão |
| `/buscar <termo>` ou `/rag <termo>` | Busca léxica local SQLite FTS5/BM25 no cofre Obsidian |
| `/note <texto>` / `/vault` / `/desfazer` | CRUD no cofre Obsidian (`Diario/`, `Inbox/`, `Inventario/`, `Pessoas/`) com Undo |
| `/skills` / `/skill <nome>` | Lista ou executa skills em `Skills/*.md` (incl. `garantias.md`) |
| `/lembrete <data/tempo:título>` / `/lembretes` | Lembretes persistentes em SQLite com reagendamento automático pós-reboot |
| `/fluxo [listar\|criar\|rodar\|agendar\|excluir]` | Fluxos encadeados com AuthGate e checkpoints pausáveis |
| `/audit` ou `/auditoria` | Verifica integridade SHA-256 e resumo de recibos (`CONFIRMED`/`UNCERTAIN`/`FAILED`) |
| `/briefing [cidade]` ou `"bom dia"` | Briefing matinal (Clima + Agenda + Sentinela + Telemetria) |
| `/agenda [hoje\|semana\|criar ...]` | Leitura e criação de eventos via `CalendarContract` |
| `/spotify [estado\|buscar\|tocar\|playlists]` | Controle Spotify Web API (OAuth 2.0 PKCE) |
| `/desktop` / `/pc <status\|abrir\|midia\|copiar\|colar\|skill\|miniapp\|...>` | Ponte Desktop LAN / Tailscale assinada HMAC-SHA256 |
| `/device` / `/lanterna` / `/mensagens` / `/reply` | Hardware nativo, controle de mídia proativo e Sentinela de notificações |
| `/settings` / `/models` / `/memory` / `/security` / `/killswitch` / `/history` / `/clear` | Provedores IA, diagnóstico acústico, segurança, Duress PIN e SQLCipher |

---

## 🏗️ Arquitetura do Projeto

```text
lib/
├── core/security/
│   ├── action_gate.dart              # Simulação de risco, confirmação crítica (incl. create_mini_app) e HMAC
│   ├── auth_gate.dart              # PIN, NFC, Biometria e política composta Biometria + NFC NDEF
│   ├── database_key_vault.dart       # Chave SQLCipher 256-bit no Keystore
│   └── pin_vault.dart              # PBKDF2-HMAC-SHA256 (PIN normal + Duress PIN + tags NFC)
├── models/
│   ├── chat_message.dart
│   └── tactical_mode.dart            # Modos Táticos isolados (Geral, Engenharia, Estudos, Treino, Dev)
├── services/
│   ├── ai_provider_service.dart      # 9 provedores, failover, usage/estimativa de tokens e SessionTelemetry
│   ├── audio_capture_service.dart    # AudioRecord PCM (não-Google)
│   ├── audio_vad_buffer.dart         # VAD pré-roll, medidor dBFS e AcousticDiagnosticsTracker
│   ├── audit_log_service.dart        # Log imutável SHA-256 com recibos CONFIRMED/UNCERTAIN/FAILED
│   ├── briefing_service.dart         # Clima + Agenda + Sentinela + Telemetria
│   ├── cognicao_service.dart         # Pré-processador, isolamento visual anti-injection e pós-auditoria
│   ├── conversation_history.dart     # Persistência SQLCipher v2 isolada por conversationId
│   ├── desktop_command_listener.dart # Listener bidirecional Desktop LAN
│   ├── desktop_pairing_service.dart  # Bridge LAN/Tailscale HMAC-SHA256 + contrato MiniAppLaunch
│   ├── device_control_service.dart   # MethodChannel, mídia proativa, RAG filtrado, ETL, /eletrica, PC Bridge
│   ├── eletrica_engine.dart          # Motor NBR 5410, CFW500/AD600M, topologias IEC, auditoria, Netlist & SVG
│   ├── file_utilities_service.dart   # SAF duplicados SHA-256, conversão imagens, PDFs e ETL em lote
│   ├── obsidian_service.dart         # Cofre Markdown (Diario, Memoria, Inbox, Inventario, Pessoas, Skills) + Privacidade
│   ├── reminder_service.dart         # Lembretes SQLite + reagendamento AlarmManager
│   ├── slash_command_parser.dart     # Parser determinístico de Slash Commands
│   ├── spotify_service.dart          # Spotify Web API OAuth 2.0 PKCE
│   ├── vault_search_service.dart     # Busca/RAG FTS5/FTS4/BM25 com filtro opcional por pathPrefix
│   ├── voice_pipeline_controller.dart# Pipeline de voz contínua, PTT e barge-in
│   ├── voice_service.dart            # Fish Studio TTS + TTS nativo pt-BR
│   └── workflow_scheduler_service.dart# Fluxos agendados + checkpoints persistentes pausáveis
└── ui/
    ├── screens/                      # Auth, Core (CoreOrb + Telemetria), DesktopPairing, Memory, AI Settings (Diag. Acústico), History, Update
    └── widgets/                      # CoreOrb, ActionConfirmationDialog, VoiceSelectorSheet
android/
└── app/src/main/
    ├── kotlin/.../MainActivity.kt           # Ponte nativa (Hardware, MediaSession, SAF multi-arquivo, Vision, NFC)
    ├── kotlin/.../DeviceHardwareHelper.kt   # Hardware, mídia verificada/proativa, Bluetooth, lançador universal
    ├── kotlin/.../ReminderAlarmReceiver.kt  # AlarmManager + restauração de lembretes persistidos no SQLite
    ├── kotlin/.../BootReceiver.kt           # Reagendamento de lembretes (BOOT_COMPLETED / MY_PACKAGE_REPLACED) + Sentinela
    ├── kotlin/.../BackgroundVoiceResponder.kt# Respostas autônomas 2º plano com mídia proativa/honesta
    ├── kotlin/.../UltronAudioService.kt     # Sentinela de voz 24h non-Google (AudioRecord + sherpa-onnx)
    ├── kotlin/.../FloatingOrbService.kt     # Orbe Flutuante Android
    └── assets/                              # Modelo sherpa-onnx Zipformer KWS (offline Wake Word)
docs/
└── DESKTOP_MINI_APP_CONTRACT.md             # Contrato seguro e handler Python para Mini-Apps LAN/Tailscale
shaders/
└── crimson_core.frag                        # Fragment shader GLSL do Núcleo Holográfico
```

---

## 🛠️ Como Testar e Compilar Localmente

### Pré-requisitos
1. **Flutter SDK (stable)**, **Android SDK** e **JDK 17+**.
2. No Windows (caso o disco `C:` esteja cheio ou o caminho do workspace contenha acentos), redirecione `TEMP`/`TMP` para `D:\downloads\tmp` e use um drive ASCII (`subst U:`) para builds AOT `release`:

```powershell
# Análise estática e suíte completa de testes (208 testes)
$env:TEMP='D:\downloads\tmp'
$env:TMP='D:\downloads\tmp'
$env:ANDROID_HOME='D:\downloads\android-sdk'
$env:ANDROID_SDK_ROOT='D:\downloads\android-sdk'

dart analyze lib test
flutter test

# Build release arm64 (via drive ASCII quando o caminho tem acento)
flutter build apk --release --target-platform android-arm64
```

### Esteira CI/CD (GitHub Actions)
- **Flutter CI (`.github/workflows/flutter-ci.yml`)**: Roda `flutter analyze`, `flutter test` e valida o build Android em cada push/PR.
- **Android Release (`.github/workflows/android-release.yml`)**: Compila e assina o APK `arm64` a partir de tags `vX.Y.Z` com verificação via `apksigner` e publicação em Releases.
