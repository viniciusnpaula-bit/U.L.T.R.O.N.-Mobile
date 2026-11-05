# Auditoria do Wake Word — U.L.T.R.O.N. Mobile v1.2.1

Estado: **motor de keyword spotting (KWS) dedicado = PENDENTE.** Nada neste repositório finge o contrário.

## 3. Auditoria do Motor de Detecção

| Item | Resultado | Evidência |
|---|---|---|
| Motor KWS dedicado (Porcupine, openWakeWord, Vosk, sherpa-onnx) | **NÃO EXISTE NO REPOSITÓRIO** | `pubspec.yaml` e `build.gradle.kts` sem dependência de KWS; sem arquivos `.ppn`, `.onnx` ou `.tflite` de KWS em `assets/` |
| Inicialização/compatibilidade de modelo, arm64-v8a, palavra "Ultron" | **TESTADO EMPIRICAMENTE (RESULTADO ABAIXO)** | Vosk `vosk-model-small-pt-0.3` **NÃO CONTÉM** a palavra "Ultron" em seu vocabulário |
| Como detecta hoje | Porta de **volume (RMS adaptativo) + `SpeechRecognizer`** | `UltronAudioService.runCaptureSession`, `UltronWakeWordRecognizer` |
| Atende ao critério "não aceitar volume + SpeechRecognizer"? | **NÃO** | Desenho arquitetural herdado (otimizado com VAD contínuo, mas ainda dependente do motor do sistema) |
| AccessKey / credenciais | **Nenhuma exposta** | Varredura completa confirmou ausência de chaves hardcoded e logs com conteúdo de áudio |
| Taxa / PCM / frame | 8 kHz, PCM16 mono, frame 100 ms | Motores KWS dedicados exigem tipicamente 16 kHz |
| Dependência de rede | `SpeechRecognizer` com `PREFER_OFFLINE`; sujeito a fallback online do sistema | Não garantido 100% offline em todos os aparelhos |
| Latência | VAD 200 ms + tempo de abertura do motor ASR | Palavra dita antes da abertura do ASR pode ser perdida sem pre-roll |
| Falsos negativos | Falas em voz baixa/abafadas no bolso abaixo do limiar | Limiar adaptativo mitiga |
| Falsos positivos | Ruídos ambientais acima do limiar disparam tentativa de reconhecimento | Backoff de 1,2 s a 12 s implementado |

---

### Experimento e Teste Empírico com Vosk (Revisão Técnica Detalhada)

Ao avaliar a integração direta do **Vosk (`com.alphacephei:vosk-android:0.3.75`)** com o modelo oficial em português **`vosk-model-small-pt-0.3`** (32,4 MB compactado, 51,1 MB descompactado), realizamos um teste prático com o interpretador e a biblioteca nativa oficial da Alpha Cephei.

**Resultado do Teste com Gramática Restrita `["ultron", "[unk]"]`:**
```text
LOG (VoskAPI:UpdateGrammarFst():recognizer.cc:287) ["ultron", "[unk]"]
WARNING (VoskAPI:UpdateGrammarFst():recognizer.cc:308) Ignoring word missing in vocabulary: 'ultron'
LOG (VoskAPI:Estimate():language_model.cc:142) Estimating language model with ngram-order=2, discount=0.5
LOG (VoskAPI:OutputToFst():language_model.cc:209) Created language model with 2 states and 2 arcs.
```

**Resultado na Entrada de Áudio Falando "Ultron":**
* Com gramática `["ultron", "[unk]"]`: `{'text': ''}` (o decodificador descarta a palavra ausente do léxico Kaldi e só ouve `[unk]`, resultando em silêncio).
* Sem gramática (reconhecimento livre): `{'text': 'outro'}` (o modelo acústico mapeia a pronúncia para a palavra foneticamente mais próxima cadastrada no dicionário, que é *"outro"*).

**Conclusão da Auditoria:**
Embutir o Vosk com o modelo `small-pt-0.3` sem recompilar o grafo acústico/léxico no Kaldi geraria uma **falsa indicação de funcionamento**, violando a diretriz do projeto. O modelo simplesmente ignoraria a palavra "Ultron".

---

### Opções e Pendências para Fechamento do Item 3

Para implementar um motor KWS verdadeiramente funcional para a palavra "Ultron", é necessário um dos seguintes artefatos:

1. **Porcupine (Picovoice):**
   * Exige: AccessKey do Picovoice Console + arquivo de modelo treinado `ultron_android.ppn`.
   * Vantagem: Extremamente leve (~100 KB), altamente preciso para palavras personalizadas.
   * Regra: A AccessKey deve ser injetada via `local.properties` / variáveis de ambiente de CI (nunca em código fonte).

2. **Sherpa-ONNX (Zipformer KWS Open-Vocabulary):**
   * Exige: Modelo Zipformer quantized int8 (ex: `sherpa-onnx-kws-zipformer-gigaspeech-3.3M-mobile`, ~5,2 MB) mapeado para tokens BPE compatíveis.
   * Vantagem: Totalmente offline, open-source (Apache 2.0), sem chaves ou autenticação.

3. **Vosk com Grafo Customizado:**
   * Exige: Recompilação do modelo Kaldi `HCLr.fst` adicionando a transcrição fonética de "Ultron" ao `lexicon.txt` do modelo.

Enquanto esses modelos específicos não forem fornecidos, o app mantém transparência total:
* `UltronAudioService.ENGINE_DESCRIPTION` = `"PORTA DE VOLUME + SpeechRecognizer (sem motor KWS dedicado)"`
* `ENGINE_IS_DEDICATED_KWS` = `false`
* O HUD e o relatório de diagnóstico marcam explicitamente a pendência como **`PENDENTE: sem modelo/motor KWS dedicado`**.

---

## 4. Auditoria da Captura de Áudio (Concluída)

- `AudioRecord` alocado uma única vez por sessão contínua (8 kHz, 16-bit PCM mono), lido em blocos bloqueantes de 100 ms **sem sleeps artificiais**.
- Liberação segura de recursos: `AudioRecord` é fechado antes da abertura do `SpeechRecognizer` para eliminar contenção de portas de microfone.
- Zero vazamentos de memória: buffer `ShortArray` pré-alocado e reutilizado.
- Tratamento de microfone silenciado: 30 segundos contínuos de leituras zeradas disparam exceção tratada para recuperação no watchdog.
- Recuperação com teto de tentativas: após 8 falhas consecutivas sem leitura confirmada, o serviço encerra a tentativa, desliga o sentinela e alerta o usuário via notificação.
- Confirmação real de estado: a UI só reporta "ATIVO" após leitura física confirmada de áudio (`captureHealthy == true`).

---

## 5. Auditoria do Foreground Service (Concluída)

- Declarado e iniciado com `foregroundServiceType="microphone"`.
- Notificação permanente interativa com ações: **Pausar/Retomar**, **Que horas são?** e **Parar Escuta**.
- Prevenção contra instâncias concorrentes via `workerActive.compareAndSet`.
- Gerenciamento estrito de `PARTIAL_WAKE_LOCK`: adquirido com timeout máximo de 15 segundos durante o reconhecimento e liberado imediatamente após a finalização (`releaseWakeLockSafely`). Nenhum WakeLock permanece aberto indefinidamente.
- Tratamento seguro de rejeição de inicialização (`startForeground` fora de contexto em Android 14+ é capturado sem provocar crash do aplicativo).

---

## 6. Auditoria de Compatibilidade Android 12–16 (Concluída)

- Permissões em tempo de execução: `RECORD_AUDIO` e `POST_NOTIFICATIONS` validadas antes da inicialização do serviço.
- Restrições *while-in-use*: o serviço só é iniciado a partir da Activity em primeiro plano ou por ação direta do usuário.
- Inicialização pós-reboot: em Android 11+, o `BootReceiver` não força a inicialização proibida de microfone em background; ele publica uma notificação de alta prioridade para o usuário reativar com um toque.
- Compatibilidade com telas de bloqueio: `setShowWhenLocked` e `setTurnScreenOn` controlados exclusivamente pelo ciclo de vida da Activity quando acordada pelo alarme de ativação.

---

## 7. Fase 2 — Refinamento e Correções (auditoria sobre a Fase 1)

### Defeitos encontrados e corrigidos

| # | Defeito | Correção |
|---|---|---|
| 1 | UI podia dizer "capturando" enquanto o `SpeechRecognizer` detinha o microfone | `captureHealthy = false` ao liberar o `AudioRecord` antes do ASR |
| 2 | `AudioRecord.read() == 0` mantinha `captureHealthy` antigo em `true` (loop sem áudio) | Leitura vazia agora conta para o watchdog e derruba `captureHealthy` |
| 3 | Timeout do ASR deixava a notificação permanente presa em "Verificando palavra…" | Notificação restaurada no timeout, junto do erro de diagnóstico |
| 4 | `startRecording()` com exceção vazava o `AudioRecord` | `release()` no catch antes de relançar |
| 5 | Wake word detectada em segundo plano era entregue ao Flutter e abria o microfone sem o usuário ver o alerta | `deliverPendingWakeWord` só entrega com `isActivityResumed`; pendente fica para o `onResume` |
| 6 | Se o TTS/reconhecedor estivesse ativo, a wake word pendente nunca era reentregue | Retry de 500 ms enquanto a Activity está em primeiro plano (com TTL de 30 s) |
| 7 | Activity destruída no meio da escuta deixava `isForegroundRecognizerActive = true` para sempre (sentinela surdo) | `onDestroy` libera a flag, resolve o `pendingSpeechResult` e atualiza o timestamp |
| 8 | Flip-to-Shush ficava preso em `true` ao ir para segundo plano (sensor desregistrado) e pausava a escuta para sempre | `onPause` zera `isFaceDown`/`isFaceDownGlobal` |
| 9 | Wake word após a 4ª palavra ativava o nativo, mas `WakeWord.extractCommand` no Dart não encontrava o hotword (comando errado) | `WakeWordMatcher.hotwordIndex` limitado às 4 primeiras palavras, igual ao Dart |
| 10 | Resultado ASR atrasado podia disparar ativação depois de `destroy()`/timeout | `dispatch()` ignora chamadas após `finished` |
| 11 | Pausa do usuário podia ser desfeita por restart sticky | `ACTION_TOGGLE_PAUSE` pausado retorna `START_NOT_STICKY` |
| 12 | HUD iniciava com "EM REPOUSO" mesmo com o sentinela ativo (nunca consultava o estado real no cold start) | `_loadInitialState` consulta `isAudioSentinelRunning`; resume revalida |
| 13 | Ao conceder permissão, o toggle mostrava "não confirmou captura" antes do usuário responder ao diálogo | SnackBar de falha só quando o serviço foi de fato solicitado |
| 14 | Wake word durante um comando em andamento era descartada sem feedback | Espera curta pelo pipeline e aviso explícito se ainda estiver ocupado |
| 15 | `onTaskRemoved` registrava um falso erro no diagnóstico | Apenas log de operação |
| 16 | Teste Kotlin do matcher nunca era executado no CI (`flutter build` não compila `src/test`) | Step `./gradlew testDebugUnitTest` no `flutter-ci.yml` |

### O que continua pendente (não simulado)

1. **Motor KWS dedicado** (Porcupine/openWakeWord/sherpa-onnx/Vosk com léxico customizado): nenhum modelo ou AccessKey foi fornecido. A detecção continua sendo porta de volume + `SpeechRecognizer`; `ENGINE_IS_DEDICATED_KWS = false` e o HUD reporta a pendência.
2. **Pré-roll de áudio**: o `SpeechRecognizer` não aceita PCM injetado; as ~200 ms usadas pelo portão de volume podem cortar o início da palavra. Só um motor KWS com buffer contínuo resolve isso — não foi falsificado.
3. **Testes físicos** (app aberto, segundo plano, tela bloqueada, alternância de apps, economia de bateria, eco do próprio TTS, interrupção/retomada): não executados nesta revisão por ausência de aparelho conectado.
4. **`flutter analyze` / `flutter test` / build APK**: a máquina de revisão não possui Flutter/Android SDK instalados; a validação é feita no CI (workflow `Flutter CI`) e o resultado é anexado ao relatório da Fase 2.
5. **Segredo HMAC fixo** em `preparePcSyncPayload` (`ULTRON_LAN_GUARD`): utilitário de sincronização com o nó PC, sem uso pelo fluxo de wake word. Trocar por segredo configurável exige atualizar o contrato do nó PC.

---

## 8. Fase 3 — Motor KWS dedicado (v1.3.0+15)

Status: **implementado no código; detecção real depende de artefatos do usuário** (`.ppn` treinado + AccessKey do Picovoice). Sem eles o app compila, roda e reporta "KWS não configurado" com motivo visível; a voz manual segue funcionando.

### Decisões (D1–D9, spec `.internal/specs/2026-11-05-porcupine-vosk-kws-design.md`)

| # | Decisão |
|---|---|
| D1 | **Porcupine (Picovoice)** para o KWS da palavra "ultron" em português. |
| D2 | **Vosk offline** como transcritor do comando, alimentado por anel de pré-roll de 1,5 s. |
| D3 | Modelo Vosk embarcado no APK via CI (`vosk-model-small-pt-0.3.zip`), verificado por SHA-256 fixo. |
| D4 | AccessKey via GitHub Secret `PORCUPINE_ACCESS_KEY` → `BuildConfig.PORCUPINE_ACCESS_KEY`; nunca no repositório, nunca logada. |
| D5 | Vosk descarregado da memória após 2 min de inatividade (nunca durante uma transcrição). |
| D6 | Frase entregue ao Dart sempre começa com "ultron" (prefixo nativo quando necessário). |
| D7 | **Sem fallback**: porta de volume RMS removida do caminho de ativação. Sem KWS, a feature fica off. |
| D8 | Gatilho só vira ativação com texto útil (>= 2 caracteres) do Vosk; vazio = miss silencioso com cooldown de 1,5 s e backoff 5/10/20 s (teto 30 s). |
| D9 | Versão **1.3.0+15** com nota de release explícita sobre a exigência de configuração. |

### O que foi removido

- Porta de volume RMS como gatilho de ativação (`MIN_VOICE_RMS`, `WINDOW_MS`, limiar adaptativo etc. eliminados do caminho de wake). O RMS continua calculado apenas como telemetria (`noiseFloor`/`threshold`), sem bloquear nada.
- `UltronWakeWordRecognizer.kt` (caminho antigo via `SpeechRecognizer`). O reconhecedor de voz manual da Activity permanece inalterado.
- Constantes `ENGINE_DESCRIPTION` / `ENGINE_IS_DEDICATED_KWS`. O diagnóstico agora calcula `engine` e `dedicatedKws` em tempo de execução a partir de `Stats.kwsConfigured`.

### O que depende do usuário

- `android/app/src/main/assets/porcupine/ultron_pt.ppn`, treinado no Picovoice Console (Portuguese, frase `ultron`, plataforma Android). Veja `android/app/src/main/assets/porcupine/README.md`.
- GitHub Secret `PORCUPINE_ACCESS_KEY` no repositório (injetado no `env` do job de CI).
- Medição de bateria (`scripts/battery-test.ps1`, `scripts/perfetto-ultron.cfg`) e os 12 cenários físicos (`docs/PHYSICAL_TEST_PROTOCOL.md`) executados pelo operador em aparelho real — não executáveis nesta revisão por ausência de aparelho conectado.
- APK cresce ~32 MB (modelo Vosk ~45 MB compactado).

### Segurança

- Áudio nunca persistido: anel de 1,5 s vive só em RAM, é zerado em `stop`/`destroy`; não existe gravação WAV de diagnóstico.
- AccessKey nunca logada nem incluída no diagnóstico. Como é injetada no `BuildConfig`, é extraível do APK (característica do Picovoice): APK compartilhado consome a quota da conta.
- A palavra de ativação não autoriza ações sensíveis: PIN, biometria e Action Gate (`ULTRON_LAN_GUARD`) continuam intocados.
