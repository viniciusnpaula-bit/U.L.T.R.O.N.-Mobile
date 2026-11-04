# 🔴 U.L.T.R.O.N. 2.0 — Mobile (`v1.1.0`)

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

### 1B. 📨 Sentinela de Mensagens & Comunicação Autônoma (`NotificationListenerService` + `RemoteInput`)
- **Leitura Real de Mensagens (WhatsApp, Telegram, Instagram, SMS, Gmail, Discord)**:
  - Captura notificações em tempo real e lê em voz alta (`pt-BR`) com `"ler mensagens"`, `/mensagens` ou pelo botão **🔊 LER EM VOZ ALTA** na aba **CELULAR**.
- **Resumo Tático por IA**:
  - Botão **🧠 RESUMO TÁTICO IA** que analisa todas as mensagens recentes, filtra ruído de grupos triviais, destaca o que é urgente e sugere respostas.
- **Resposta Instantânea em 2º Plano (`RemoteInput` Nativo — Sem Abrir o App)**:
  - Diga ou digite `"responder: Chego em 10 minutos"`, `"responder para João: Já estou indo"` ou `/responder <texto>` e o U.L.T.R.O.N. injeta a resposta direto na notificação do WhatsApp/Telegram/SMS em segundo plano, sem precisar abrir o aplicativo!
- **Envio Ativo de WhatsApp e SMS com Busca na Agenda (`ContactsContract`)**:
  - Diga `"mandar whatsapp para Mãe: Já cheguei"` ou `"enviar sms para Carlos: Reunião às 15h"`. O U.L.T.R.O.N. busca o telefone do contato na agenda do Android e dispara a mensagem (ou usa o painel rápido de envio na aba **CELULAR**).

### 1C. 🎙️ Motor de Voz Neural Limpo & Reconhecimento Ao Vivo (`v1.0.0`)
- **Reconhecimento de Voz In-App em Tempo Real (`SpeechRecognizer` + Fallback Automático)**:
  - Transcrição parcial ao vivo direto na barra de comando do HUD enquanto você fala (`onSpeechPartial`), sem abrir popups brancos bloqueantes do sistema.
  - Reação visual a 60 FPS do Núcleo Carmesim sincronizada com a amplitude da sua voz (`onSpeechRms`).
  - Tolerância estendida de pausa (`1.8s`) para não cortar frases no meio e botão **🎤 CONCLUIR FALA** para enviar imediatamente.
- **Hotword Fonético Tolerante a Ruído (`WakeWord` + `UltronWakeWordRecognizer`)**:
  - Reconhece `"Ultron"`, `"Ei Ultron"`, `"Oi Ultron"` e variações fonéticas do STT em português (`"Outron"`, `"Uoltron"`, `"Ultrom"`, `"Ultrão"`) com extração direta de comando inline (ex.: `"Ei Ultron ligar lanterna"` executa direto em 1 passo).
- **Fala Neural Limpa (`SpeechText` + `VoiceService` + Perfis de Timbre)**:
  - Sanitizador inteligente que remove Markdown (`**`, `` ` ``, `#`), blocos de código, URLs, emojis e tags `[ACTION:...]` antes de falar, além de pronunciar `"Ultron"` naturalmente em vez de soletrar `"U ponto L ponto..."`.
  - Divisão automática de respostas longas em sentenças naturais (`<= 220` caracteres) com interrupção instantânea (`CALAR VOZ` ou Flip-to-Shush).
  - **3 Perfis de Timbre (`GRAVE` `0.80`, `NATURAL` `1.00`, `ÁGIL` `0.88`)** e seleção automática da melhor voz neural offline `pt-BR` instalada no Android, com **Bloqueio Anti-Eco Half-Duplex** para que o microfone nunca capte a própria voz do Ultron.

### 2. 🧠 Central de IA 100% Gratuita (9 Provedores + Zero-Key Sem Cadastro)
- **IA Grátis Sem Chave (Zero-Key Out-of-the-Box)**:
  - **Pollinations AI (`openai`, `mistral`, `qwen-coder`, `deepseek-reasoning`)**: Já vem pré-configurado de fábrica para responder **100% de graça sem precisar criar conta nem chave de API**.
- **Catálogo Visual de 9 Provedores Gratuitos (com botão 1-toque para gerar chave grátis)**:
  1. **Pollinations AI (Zero-Key / Sem Chave)** — `openai`, `mistral`, `qwen-coder`
  2. **Groq Cloud (Free Tier Ultra-Rápido)** — `openai/gpt-oss-120b`, `openai/gpt-oss-20b`, `qwen/qwen3-32b`, `moonshotai/kimi-k2-instruct`
  3. **Google Gemini AI Studio (Free Tier)** — `gemini-2.5-flash`, `gemini-2.5-pro`, `gemini-2.0-flash`
  4. **OpenRouter (Modelos `:free` 100% Gratuitos)** — `deepseek/deepseek-r1:free`, `deepseek/deepseek-chat-v3-0324:free`, `qwen/qwen3-235b-a22b:free`
  5. **Cerebras Inference (Free Tier 2000+ tok/s)** — `llama-3.3-70b`, `qwen-3-32b`
  6. **GitHub Models (Grátis com conta GitHub)** — `gpt-4o-mini`, `gpt-4o`, `DeepSeek-R1`
  7. **Mistral La Plateforme (Experiment Plan Grátis)** — `mistral-small-latest`, `codestral-latest`
  8. **SambaNova Cloud (Free Tier)** — `Meta-Llama-3.3-70B-Instruct`, `DeepSeek-R1`
  9. **HuggingFace Inference Router (Free Tier)** — `Qwen/Qwen2.5-72B-Instruct`, `deepseek-ai/DeepSeek-R1`
- **Auto-Discovery (`/models`) e Failover em Cadeia**: Consulta modelos ativos ao vivo e alterna automaticamente entre provedores/modelos caso um atinja limite.
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

### 6. 🎛️ Interface Tática, Comando por Voz (STT + TTS) e Atualizador OTA
- **Escuta por Voz Nativa (`RecognizerIntent` Speech-to-Text `pt-BR`)**: Botão de microfone (`🎤`) na barra `EI, ULTRON ›`, botão rápido `FALAR POR VOZ` abaixo do núcleo e comando `/voz` para falar diretamente com o U.L.T.R.O.N. sem digitar.
- **Voz Sintetizada Nativa (`flutter_tts`)**: Timbre grave (`pitch: 0.55`) em `pt-BR` + Modo Sussurro noturno.
- **Núcleo Orbital 60 FPS (`CorePainter`)**: Alterna entre **Modo Centro**, **Modo Palco** (relatórios isolados com núcleo no canto) e **Modo Tela Cheia** (GPU desligada).
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
