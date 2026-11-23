# Changelog — U.L.T.R.O.N. Mobile

## [1.5.0+53] — 2026-11-22

### Fase 1 — Obsidian Completo, Desfazer, Agenda e Lembretes
- **Obsidian CRUD Completo**: adicionados `OBSIDIAN_LIST` (`/obsidian_notas`), `OBSIDIAN_READ` (`/obsidian_ler`) com proteção estrita contra path traversal, `OBSIDIAN_APPEND` (`/obsidian_anexar`), `OBSIDIAN_TASKS` (`/obsidian_tarefas`) e `OBSIDIAN_STATUS` (`/obsidian_status`).
- **Pilha de Desfazer (`UNDO`)**: snapshots reversíveis para operações mutáveis recentes no cofre (`[ACTION:UNDO]` / `/desfazer`).
- **Agenda e Lembretes Persistentes**: remoção de eventos no `CalendarContract` (`CANCEL_EVENT` / `/cancelar_evento`) e novo `ReminderService` em SQLite com alarmes nativos via `AlarmManager` (`REMINDER_CREATE`, `REMINDER_LIST`, `REMINDER_CANCEL`).

### Fase 2 — Informação Atual & Skills/Fluxos Dinâmicos
- **Consultas Web sem chave de API (`WebInfoService`)**: `[ACTION:WEATHER:cidade]` (`/clima`), `[ACTION:NEWS:tema]` via feeds RSS públicos (`/noticias`) e `[ACTION:WEB_SEARCH:query]` para resumo textual no chat (`/pesquisar_web`).
- **Skills Dinâmicas**: criação e remoção de skills procedurais (`SKILL_CREATE` e `SKILL_DELETE` em `Skills/*.md`) protegidas pelo `ActionGate`.
- **Fluxos Agendados (`WorkflowSchedulerService`)**: encadeamento e agendamento de ações/skills (`FLOW_CREATE`, `FLOW_LIST`, `FLOW_RUN`, `FLOW_SCHEDULE`, `FLOW_DELETE`) com execução via `AlarmManager` respeitando o `AuthGate`.

### Fase 3 — Integração Spotify Web API (OAuth 2.0 PKCE)
- **Autenticação PKCE Configurável (`SpotifyService`)**: fluxo OAuth 2.0 PKCE sem `client_secret` embutido no APK, deep-link `ultron://spotify-callback` e armazenamento seguro no `FlutterSecureStorage`.
- **5 Ferramentas Spotify**: `SPOTIFY_SEARCH` (`spotify_buscar`), `SPOTIFY_STATE` (`spotify_estado`), `SPOTIFY_PLAY` (`spotify_tocar`), `SPOTIFY_PLAYLISTS` (`spotify_listar_playlists`) e `SPOTIFY_ADD_PLAYLIST` (`spotify_adicionar_playlist`).

### Fase 4 — Expansão da Ponte LAN (Mobile → Desktop v3.0.0)
- **8 Novos Comandos LAN (Nível Soberano / Biometria)**: `PC_THERMAL`, `PC_POWER_PLAN`, `PC_APP_VOLUME`, `PC_KILL_FROZEN`, `PC_BACKUP`, `PC_CLEAN_DISK`, `PC_EJECT_USB` e `PC_EXEC_TOOL` (com confirmação explícita para risco `ALTO`/`CRITICO`).
- **Assinatura Criptográfica e Degradação Graciosa**: chamadas assinadas com `HMAC-SHA256` + `timestamp` + `nonce` anti-replay e tratamento gracioso de HTTP `404`/`501`.

### Fase 5 — Wake-Word Multi-Perfil & Orbe Flutuante Android
- **Wake-Word Multi-Perfil (`Ultron`, `Jarvis`, `Edith`, `Visão`)**: suporte a múltiplos perfis com mapa de aliases fonéticos pt-BR, tolerância Levenshtein ≤ 1 e hot-swap do stream KWS no `sherpa-onnx` sem reiniciar o `UltronAudioService`.
- **Orbe Flutuante Nativo (`FloatingOrbService`)**: bolha arrastável via `WindowManager` (`SYSTEM_ALERT_WINDOW`) com estados `ocioso`, `ouvindo`, `processando` e `falando`, integrada ao `AuthGate`.

### Fase 6 — Utilitários Leves de Arquivos (SAF / Downloads)
- **`limpar_duplicados` (`CLEAN_DUPLICATES`)**: varredura por hash `SHA-256` com confirmação obrigatória no `ActionGate` antes da exclusão.
- **`converter_imagens` (`CONVERT_IMAGES`)**: conversão de `.webp`/`.heic` para `.jpg`/`.png` preservando o arquivo original e garantindo destino seguro sem sobrescrita.
- **`organizar_pdf_downloads` (`ORGANIZE_PDFS`)**: renomeação assistida de PDFs para o formato padronizado `AAAA-MM-DD - Assunto.pdf`.
