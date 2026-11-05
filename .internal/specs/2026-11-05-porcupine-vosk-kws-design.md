# Design — Motor KWS (Porcupine) + pré-roll (Vosk) + medição de bateria

Data: 2026-11-05
Base: v1.2.1, branch `feature/phase2-wakeword-audit` (HEAD `1336995`)
Status: aprovado em brainstorming, pendente de plano de implementação

## 1. Contexto

A auditoria da Fase 2 provou que a detecção da palavra "Ultron" não é KWS: é um gate de
volume RMS em 8 kHz que, ao passar do limiar, libera o microfone e abre o
`SpeechRecognizer`. Consequências medidas em código:

- cada ruído acima do limiar paga `WakeLock` de 15 s + ASR do sistema (rede, quando não há
  pacote offline) e frequentemente termina em `ERROR_NO_MATCH`;
- o microfone é exclusivo, então o comando falado em seguida perde o início durante o
  handoff (`~200 ms` do gate + abertura do ASR);
- a UI só pode afirmar "capturando" enquanto o `AudioRecord` lê; durante o ASR a captura
  real é do sistema, o que já foi corrigido com `captureHealthy = false`.

Este design substitui a detecção por um motor dedicado (Porcupine) e captura o comando com
pré-roll (Vosk), mantendo o `SpeechRecognizer` apenas no botão de voz manual.

## 2. Decisões

| # | Decisão | Alternativas descartadas |
|---|---|---|
| D1 | **Porcupine (Picovoice)** para o KWS | sherpa-onnx (sem modelo pt para "Ultron"), Vosk com gramática (palavra ausente no vocabulário do small pt) |
| D2 | **Vosk offline** como transcritor do comando, alimentado pelo anel de pré-roll | manter `SpeechRecognizer` (impossível injetar PCM, pré-roll não existe) |
| D3 | **Modelo Vosk embarcado no APK** (asset baixado no CI, não versionado) | download sob demanda (exige hospedagem e trata offline) |
| D4 | **AccessKey via GitHub Secret**; `.ppn` versionado | key no repositório (segredo em histórico público) |
| D5 | **Vosk descarrega após 2 min** de inatividade | manter residente (≈100 MB de RAM 24/7) |
| D6 | **Frase sempre começa com "ultron"** (prefixo nativo quando necessário) | confiar no ASR (transcrição de "Ultron" varia e quebra `WakeWord.extractCommand`) |

## 3. Arquitetura de áudio

Um único `AudioRecord`, aberto e mantido pelo serviço no caminho de wake:

```
AudioRecord(16 kHz, CHANNEL_IN_MONO, ENCODING_PCM_16BIT)
  frame de 512 amostras (32 ms)
    ├─ PorcupineKeywordSpotter.process(frame)  → gatilho
    └─ AudioRingBuffer.write(frame)            → 1,5 s de histórico
```

Ao detectar:

```
VoskCommandTranscriber.transcribe(anel.snapshot() + áudio ao vivo)
  até fim de fala (endpoint do Vosk) ou 5 s
    → WakePhraseComposer.ensurePhrase(texto)
      → MainActivity.notifyWakeWord(frase)   (caminho existente, inalterado)
```

O microfone **não é liberado** entre a palavra e o comando: não há handoff, então o início
do comando está no anel. `captureHealthy` permanece verdadeiro enquanto os frames chegam.

### 3.1 Modos que continuam pausando o microfone (inalterados)

- `userPaused`, chamada/VoIP (`AudioManager.mode != MODE_NORMAL`), `isFaceDownGlobal`
  (Flip-to-Shush): libera o `AudioRecord` e dorme.
- Half-duplex: TTS falando ou reconhecedor em primeiro plano ativo → libera o microfone
  (o Porcupine não pode ouvir o próprio Ultron).
- Bateria crítica (<15% sem carregador): modo economia, microfone liberado.

### 3.2 Watchdog (inalterado no comportamento)

Leitura `0`/`-1` ou 30 s de frames zerados continuam sendo falha real: `captureHealthy = false`,
`Stats.micSilencedEvents++`, backoff e limite de 8 falhas consecutivas.

## 4. Componentes e contratos

### 4.1 `PorcupineKeywordSpotter.kt`

```kotlin
class PorcupineKeywordSpotter(context: Context, accessKey: String, keywordAsset: String) {
    val isConfigured: Boolean
    val unavailableReason: String?      // "sem AccessKey", "keyword .ppn ausente", "falha: ..."
    fun process(frame: ShortArray): Boolean   // true = palavra detectada
    fun close()
}
```

- Frame obrigatório de 512 amostras a 16 kHz (contrato do Porcupine).
- Erro de licença/key/modelo **não derruba o serviço**: `isConfigured = false`, motivo
  exposto no status, notificação mostra "KWS não configurado".
- `close()` é idempotente.

### 4.2 `AudioRingBuffer.kt`

```kotlin
class AudioRingBuffer(capacitySamples: Int) {
    fun write(frame: ShortArray, count: Int)
    fun snapshot(): ShortArray   // ordem cronológica, só o que já foi escrito
    fun clear()
}
```

- 24.000 amostras = 1,5 s a 16 kHz (48 KB).
- `snapshot()` aloca uma vez por gatilho (nunca por frame).
- Testável em JVM puro.

### 4.3 `VoskCommandTranscriber.kt`

```kotlin
class VoskCommandTranscriber(context: Context) {
    fun ensureLoaded(): Boolean            // descompacta 1x, carrega o Model
    fun transcribe(preroll: ShortArray, liveSource: () -> ShortArray?): String
    fun unloadAfterIdle(nowMs: Long)
    fun close()
}
```

- Modelo em `filesDir/vosk/<versao>/`, marcador de versão evita descompactar de novo.
- `transcribe` alimenta o anel primeiro, depois lê do `AudioRecord` até `AcceptWaveform`
  sinalizar fim de fala ou estourar 5 s.
- Texto vazio (silêncio/ruído) é resultado válido: o serviço conta como miss, não como
  detecção.
- `unloadAfterIdle` libera modelo após 120 s; `ensureLoaded` recarrega no próximo comando.

### 4.4 `WakePhraseComposer.kt`

```kotlin
object WakePhraseComposer {
    fun ensurePhrase(transcript: String): String
}
```

Regra: se o hotword aparece (Levenshtein ≤1, mesma normalização do `WakeWordMatcher`)
entre as 4 primeiras palavras, devolve o texto; caso contrário prefixa `"ultron "`.
Garante que `WakeWord.extractCommand` (Dart) sempre encontre o comando.

## 5. Mudanças no serviço e na ponte

`UltronAudioService.kt`
- `SAMPLE_RATE_HZ = 16000`, `FRAME_SAMPLES = 512`; remove `WINDOW_MS` e o gate RMS, mas
  mantém o cálculo de RMS **apenas como telemetria** (`noiseFloor`/`threshold` continuam no
  contrato do `DeviceStatus` do Dart, sem bloquear nada) — custo de 512 multiplicações por
  frame é desprezível e evita quebrar a UI.
- Loop: pausas → abre record → lê frame → half-duplex → Porcupine + anel → gatilho.
- `onVoiceWakeTriggered()` passa a: adquirir WakeLock, transcrever com Vosk, compor frase,
  soltar WakeLock. Sem `SpeechRecognizer`, sem `CountDownLatch` de 10 s.
- `Stats`: novos contadores (seção 7). `diagnostics()` passa a calcular `engine` e
  `dedicatedKws` em tempo de execução: `"Porcupine pt-BR + Vosk"` / `true` só com o motor
  realmente carregado; sem key ou sem `.ppn`, `dedicatedKws = false` e
  `kwsUnavailableReason` explica o motivo. As constantes `const val` atuais saem.
- `onDestroy` fecha spotter e transcritor.

`MainActivity.kt`
- Sem mudança de contrato: `notifyWakeWord(frase)` continua igual (gating por foreground,
  retry com TTL, `pendingSpeechResult`).
- O reconhecedor em primeiro plano (`inlineRecognizer`) continua como está — é outro
  componente, usado pela voz manual.

`UltronWakeWordRecognizer.kt`
- **Deletado.** Só era usado pelo caminho de wake do serviço, que deixa de existir.
  O reconhecedor em primeiro plano da Activity tem implementação própria.

`AndroidManifest.xml`
- Sem nova permissão: `RECORD_AUDIO` e o FGS de microfone já existem.

## 6. Configuração e build

- `android/app/build.gradle.kts`:
  - `buildConfigField("String", "PORCUPINE_ACCESS_KEY", "\"${...}\"")` lendo
    `-PporcupineAccessKey` ou `PORCUPINE_ACCESS_KEY`; default `""`.
  - `buildFeatures.buildConfig = true`.
  - dependências: `ai.picovoice:porcupine-android` e `com.alphacephei:vosk-android`
    (com JNA transitivo), versões fixadas no plano após confirmação no Maven Central.
  - `assets` já cobre `android/app/src/main/assets/`.
- Assets:
  - `android/app/src/main/assets/porcupine/ultron_pt.ppn` — **versionado** (fornecido pelo usuário).
  - `android/app/src/main/assets/vosk/model-pt.zip` — **não versionado**; baixado no CI por
    script com SHA-256 fixo e cacheado.
- `.gitignore`: ignorar `android/app/src/main/assets/vosk/`.
- Sem a key ou sem o `.ppn`: build compila, app reporta "KWS não configurado".

## 7. Bateria

Ganho estrutural esperado (a medir, não estimado):
- fim das ativações falsas que abriam ASR + WakeLock;
- WakeLock só durante comando/TTS;
- uma passada de frames no caminho de wake (sem RMS).

Instrumentação (`Stats`, exposta pelo canal de status existente):
`porcupineFrames`, `wakeDetections`, `voskCommands`, `voskLoadMs`, `lastCommandMs`,
`voskResident`, `kwsConfigured`, `kwsUnavailableReason`.

Ferramentas entregues para execução no aparelho:
- `scripts/battery-test.ps1` — reinicia `batterystats`, mantém 1 h com tela apagada, coleta
  `dumpsys batterystats`/`dumpsys power`, calcula %/h e mAh.
- `scripts/perfetto-ultron.cfg` — trace de 5 min em standby (CPU, frequência, wakeups).

## 8. Testes

JVM (CI, sem aparelho):
- `AudioRingBufferTest`: ordem cronológica, wrap-around, buffer parcial, `clear`.
- `WakePhraseComposerTest`: hotword na 1ª–4ª posição, hotword na 5ª (prefixa), texto vazio,
  transcrição ruidosa com Levenshtein 1.
- `WakeWordMatcherTest` (existente) continua.

Físico (execução do usuário, `docs/PHYSICAL_TEST_PROTOCOL.md`), 12 cenários com critério de
aceite: app aberto; background; tela bloqueada; swipe dos recentes; chamada em curso;
flip-to-shush; TTS falando; bateria <15%; reboot; headset Bluetooth; ruído de TV;
comando na mesma respiração. Apoio: `scripts/physical-test.ps1`.

CI (`flutter-ci.yml`):
- build sem secrets continua verde;
- com `PORCUPINE_ACCESS_KEY`, injeta a key e valida que `BuildConfig` recebeu valor;
- baixa e verifica o modelo Vosk por SHA-256;
- roda `:app:testDebugUnitTest` (novos testes incluídos).

## 9. Riscos e limites declarados

1. **Licença Picovoice**: tier gratuito é para uso pessoal/não comercial. Distribuição
   comercial exige licença paga.
2. **Idioma**: "Ultron" em pt-BR precisa ser confirmado no Picovoice Console; se não houver
   modelo pt, cai para pronúncia inglesa e a taxa de acerto muda.
3. **Precisão do Vosk small pt** para comandos com nomes próprios é inferior à do Google.
   Mitigação: botão de voz manual continua no `SpeechRecognizer`; transcrição vazia = miss
   explícito.
4. **Sem o `.ppn`/key** não é possível provar detecção real; só compilar e testar as partes
   puras.
5. **APK** cresce de ~54 MB para ~100 MB.
6. **Consumo real** depende de medição no aparelho; o design reduz trabalho por frame, mas
   não há número antes do protocolo rodar.

## 10. Fora de escopo

- Redesenho de autenticação, auto-lock e do segredo HMAC do `ULTRON_LAN_GUARD`.
- Treinar modelo KWS próprio.
- Substituir o `SpeechRecognizer` do botão manual.
- UI nova além de expor o estado real do motor.
