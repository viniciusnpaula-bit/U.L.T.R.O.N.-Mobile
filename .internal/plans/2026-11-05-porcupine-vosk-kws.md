# Motor KWS Porcupine + Pré-roll Vosk — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use beads-superpowers:subagent-driven-development (recommended) or beads-superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Neste repositório não existe banco de beads** (`bd prime` falha), então a referência de tarefa é o número desta seção ("Task N"), e cada commit cita esse número.
>
> **Sem SDK local:** esta máquina não tem Flutter, Dart nem Android SDK. Toda verificação de build/teste é feita pelo workflow `Flutter CI` no GitHub, via push em `feature/**` e `gh run watch`. Os comandos de verificação abaixo já estão nesse formato.

**Goal:** Substituir a detecção por porta de volume RMS pelo motor Porcupine (KWS dedicado) e capturar o comando com pré-roll de 1,5 s alimentando o Vosk, com instrumentação de bateria e protocolo de testes físicos.

**Architecture:** Um único `AudioRecord` de 16 kHz lê frames de 512 amostras; cada frame vai para o Porcupine e para um anel circular de 1,5 s. Ao detectar a palavra, o anel + áudio ao vivo são transcritos pelo Vosk no mesmo thread, sem handoff de microfone. A frase resultante entra no caminho existente `notifyWakeWord` → Dart, sem alterar autenticação. Componentes puros (anel, compositor de frase, backoff) são testados em JVM.

**Tech Stack:** Kotlin/Android (AGP do projeto, JDK 17), `ai.picovoice:porcupine-android:3.0.1`, `com.alphacephei:vosk-android:0.3.47` + `net.java.dev.jna:jna:5.13.0@aar`, Flutter 3.47.9 no CI, GitHub Actions.

## Global Constraints

- Versão do app: **1.3.0+15** (só na Task 13; demais tasks não mexem no `pubspec.yaml`).
- Dependências novas permitidas: **apenas** as três acima. Nenhuma dependência Flutter nova.
- `minSdk`/`compileSdk`/`targetSdk` continuam vindo de `flutter.*`; não fixar valores.
- Sample rate do caminho de wake: **16000 Hz**, mono, PCM16, frame de **512 amostras**.
- Anel de pré-roll: **24000 amostras** (1,5 s).
- Sensibilidade do Porcupine: **0,5**.
- AccessKey **nunca** é logada, impressa em diagnóstico nem commitada.
- Áudio **nunca** é persistido; o anel vive só em RAM.
- Nenhuma autorização por voz: PIN/biometria/Action Gate continuam intocados.
- SHA-256 do modelo Vosk: `6e1ce909032e1afa7a88e68a3d628ecafff302bdf195befab308826c395e93b7`
  (`vosk-model-small-pt-0.3.zip`, 32453112 bytes).
- URL do modelo: `https://alphacephei.com/vosk/models/vosk-model-small-pt-0.3.zip`
- Comandos de verificação rodam no CI: `git push origin feature/phase2-wakeword-audit` e
  `gh run watch $(gh run list --branch feature/phase2-wakeword-audit --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status`.
- Estilo: seguir os arquivos existentes — pacote plano
  `com.viniciusnpaula.ultron_mobile`, KDoc em português, sem abstrações novas.

---

## Mapa de arquivos

| Arquivo | Responsabilidade | Task |
|---|---|---|
| `android/app/src/main/kotlin/com/viniciusnpaula/ultron_mobile/AudioRingBuffer.kt` | anel circular de PCM16 | 1 |
| `android/app/src/test/kotlin/com/viniciusnpaula/ultron_mobile/AudioRingBufferTest.kt` | testes do anel | 1 |
| `.../WakePhraseComposer.kt` | garante hotword nas 4 primeiras palavras | 2 |
| `.../WakePhraseComposerTest.kt` | testes do compositor | 2 |
| `.../FalseTriggerBackoff.kt` | política de miss/backoff | 3 |
| `.../FalseTriggerBackoffTest.kt` | testes do backoff | 3 |
| `android/app/build.gradle.kts` | deps + `BuildConfig` | 4 |
| `android/app/src/main/assets/porcupine/README.md` | onde colocar o `.ppn` | 4 |
| `.../PorcupineKeywordSpotter.kt` | wrapper do Porcupine | 5 |
| `.../VoskCommandTranscriber.kt` | modelo + transcrição | 6 |
| `.../UltronAudioService.kt` | loop de captura, detecção, stats | 7, 8, 9 |
| `.../UltronWakeWordRecognizer.kt` | **deletado** | 9 |
| `lib/services/device_control_service.dart` | campos novos do status | 8 |
| `lib/ui/screens/core_screen.dart` | linha de diagnóstico do motor | 8 |
| `.github/workflows/flutter-ci.yml` | modelo + secret + assert | 10 |
| `scripts/battery-test.ps1`, `scripts/perfetto-ultron.cfg` | medição de bateria | 11 |
| `docs/PHYSICAL_TEST_PROTOCOL.md`, `scripts/physical-test.ps1` | 12 cenários | 12 |
| `pubspec.yaml`, `CHANGELOG.md`, `docs/WAKE_WORD_AUDIT.md` | versão e notas | 13 |

---

### Task 1: Anel circular de áudio

**Files:**
- Create: `android/app/src/main/kotlin/com/viniciusnpaula/ultron_mobile/AudioRingBuffer.kt`
- Test: `android/app/src/test/kotlin/com/viniciusnpaula/ultron_mobile/AudioRingBufferTest.kt`

**Interfaces:**
- Produces: `class AudioRingBuffer(capacity: Int)` com `write(frame: ShortArray, count: Int = frame.size)`, `snapshot(): ShortArray`, `clear()`.

**Acceptance Criteria:**
- Mantém a ordem cronológica depois do wrap-around.
- `snapshot()` antes de encher devolve só o que foi escrito.
- `count` menor que o frame grava só as primeiras amostras.

- [ ] **Step 1: Write the failing test**

```kotlin
package com.viniciusnpaula.ultron_mobile

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class AudioRingBufferTest {

    @Test
    fun `mantem ordem cronologica apos wrap`() {
        val ring = AudioRingBuffer(4)
        ring.write(shortArrayOf(1, 2, 3, 4))
        ring.write(shortArrayOf(5, 6))
        assertArrayEquals(shortArrayOf(3, 4, 5, 6), ring.snapshot())
    }

    @Test
    fun `snapshot parcial devolve apenas o escrito`() {
        val ring = AudioRingBuffer(8)
        ring.write(shortArrayOf(7, 8, 9))
        assertArrayEquals(shortArrayOf(7, 8, 9), ring.snapshot())
    }

    @Test
    fun `count menor que o frame grava so o inicio`() {
        val ring = AudioRingBuffer(4)
        ring.write(shortArrayOf(1, 2, 3, 4), 2)
        assertEquals(2, ring.snapshot().size)
        assertArrayEquals(shortArrayOf(1, 2), ring.snapshot())
    }

    @Test
    fun `clear zera o conteudo`() {
        val ring = AudioRingBuffer(4)
        ring.write(shortArrayOf(1, 2, 3, 4))
        ring.clear()
        assertEquals(0, ring.snapshot().size)
    }

    @Test
    fun `capacidade invalida falha`() {
        assertThrows(IllegalArgumentException::class.java) { AudioRingBuffer(0) }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Push e observe o CI falhar em `:app:testDebugUnitTest` por `Unresolved reference: AudioRingBuffer`.

- [ ] **Step 3: Write minimal implementation**

```kotlin
package com.viniciusnpaula.ultron_mobile

/**
 * Anel circular de amostras PCM16.
 *
 * Guarda o áudio imediatamente anterior a um gatilho para que o comando falado logo
 * depois da palavra de ativação não perca o início. Vive só em memória.
 */
class AudioRingBuffer(private val capacity: Int) {
    private val data = ShortArray(capacity)
    private var writeIndex = 0
    private var filled = 0

    init {
        require(capacity > 0) { "capacity deve ser > 0" }
    }

    fun write(frame: ShortArray, count: Int = frame.size) {
        require(count <= frame.size) { "count maior que o frame" }
        for (i in 0 until count) {
            data[writeIndex] = frame[i]
            writeIndex = (writeIndex + 1) % capacity
            if (filled < capacity) filled++
        }
    }

    /** Conteúdo em ordem cronológica (mais antigo primeiro). */
    fun snapshot(): ShortArray {
        val out = ShortArray(filled)
        val start = (writeIndex - filled + capacity) % capacity
        for (i in 0 until filled) out[i] = data[(start + i) % capacity]
        return out
    }

    fun clear() {
        writeIndex = 0
        filled = 0
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

`gh run view` deve mostrar `:app:testDebugUnitTest` verde.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/com/viniciusnpaula/ultron_mobile/AudioRingBuffer.kt \
        android/app/src/test/kotlin/com/viniciusnpaula/ultron_mobile/AudioRingBufferTest.kt
git commit -m "feat(kws): anel de pre-roll de 1,5 s (Task 1)"
```

---

### Task 2: Compositor de frase com hotword

**Files:**
- Create: `android/app/src/main/kotlin/com/viniciusnpaula/ultron_mobile/WakePhraseComposer.kt`
- Test: `android/app/src/test/kotlin/com/viniciusnpaula/ultron_mobile/WakePhraseComposerTest.kt`

**Interfaces:**
- Consumes: `WakeWordMatcher.contains(phrase: String): Boolean`
- Produces: `WakePhraseComposer.ensurePhrase(transcript: String): String`

**Acceptance Criteria:**
- Texto com hotword nas 4 primeiras palavras é devolvido sem alteração (trim).
- Texto sem hotword recebe prefixo `"ultron "`.
- Texto vazio devolve `"ultron"`.

- [ ] **Step 1: Write the failing test**

```kotlin
package com.viniciusnpaula.ultron_mobile

import org.junit.Assert.assertEquals
import org.junit.Test

class WakePhraseComposerTest {

    @Test
    fun `hotword na primeira posicao e preservada`() {
        assertEquals("ultron desliga a luz", WakePhraseComposer.ensurePhrase("ultron desliga a luz"))
    }

    @Test
    fun `hotword ate a quarta posicao e preservada`() {
        assertEquals("ei ultron desliga", WakePhraseComposer.ensurePhrase("ei ultron desliga"))
    }

    @Test
    fun `texto sem hotword recebe prefixo`() {
        assertEquals("ultron desliga a luz", WakePhraseComposer.ensurePhrase("desliga a luz"))
    }

    @Test
    fun `hotword depois da quarta palavra recebe prefixo`() {
        assertEquals(
            "ultron um dois tres quatro ultron",
            WakePhraseComposer.ensurePhrase("um dois tres quatro ultron")
        )
    }

    @Test
    fun `texto vazio devolve apenas o hotword`() {
        assertEquals("ultron", WakePhraseComposer.ensurePhrase("   "))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

CI falha com `Unresolved reference: WakePhraseComposer`.

- [ ] **Step 3: Write minimal implementation**

```kotlin
package com.viniciusnpaula.ultron_mobile

/**
 * Garante que a frase entregue ao Flutter comece com o hotword.
 *
 * O Vosk transcreve o anel de pré-roll, que pode ou não conter "Ultron" de forma
 * reconhecível. O Dart (`WakeWord.extractCommand`) só extrai comando se o hotword
 * estiver entre as 4 primeiras palavras, então o nativo normaliza aqui.
 */
object WakePhraseComposer {
    private const val HOTWORD = "ultron"

    fun ensurePhrase(transcript: String): String {
        val clean = transcript.trim()
        if (clean.isEmpty()) return HOTWORD
        return if (WakeWordMatcher.contains(clean)) clean else "$HOTWORD $clean"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

`:app:testDebugUnitTest` verde.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/com/viniciusnpaula/ultron_mobile/WakePhraseComposer.kt \
        android/app/src/test/kotlin/com/viniciusnpaula/ultron_mobile/WakePhraseComposerTest.kt
git commit -m "feat(kws): compositor de frase com hotword (Task 2)"
```

---

### Task 3: Backoff de falso positivo

**Files:**
- Create: `android/app/src/main/kotlin/com/viniciusnpaula/ultron_mobile/FalseTriggerBackoff.kt`
- Test: `android/app/src/test/kotlin/com/viniciusnpaula/ultron_mobile/FalseTriggerBackoffTest.kt`

**Interfaces:**
- Produces: `class FalseTriggerBackoff(baseCooldownMs: Long = 1_500L, quietResetMs: Long = 60_000L, maxBackoffMs: Long = 30_000L)` com `onMiss(nowMs): Long`, `onSuccess(nowMs)`, `onQuiet(nowMs): Boolean`, `misses(): Int`.

**Acceptance Criteria:**
- 1º e 2º miss devolvem `1500`.
- 3º, 4º, 5º devolvem `5000`, `10000`, `20000`; 6º em diante `30000`.
- `onSuccess` zera; `onQuiet` zera depois de 60 s.

- [ ] **Step 1: Write the failing test**

```kotlin
package com.viniciusnpaula.ultron_mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FalseTriggerBackoffTest {

    @Test
    fun `cooldown base nos dois primeiros misses`() {
        val b = FalseTriggerBackoff()
        assertEquals(1_500L, b.onMiss(0))
        assertEquals(1_500L, b.onMiss(1_000))
    }

    @Test
    fun `backoff progressivo a partir do terceiro miss`() {
        val b = FalseTriggerBackoff()
        b.onMiss(0); b.onMiss(1); b.onMiss(2)
        assertEquals(5_000L, b.onMiss(3))
        assertEquals(10_000L, b.onMiss(4))
        assertEquals(20_000L, b.onMiss(5))
        assertEquals(30_000L, b.onMiss(6))
        assertEquals(30_000L, b.onMiss(7))
    }

    @Test
    fun `sucesso zera o contador`() {
        val b = FalseTriggerBackoff()
        b.onMiss(0); b.onMiss(1); b.onMiss(2)
        b.onSuccess(3)
        assertEquals(0, b.misses())
        assertEquals(1_500L, b.onMiss(4))
    }

    @Test
    fun `silencio de 60 s zera o contador`() {
        val b = FalseTriggerBackoff()
        b.onMiss(0)
        assertFalse(b.onQuiet(59_000))
        assertTrue(b.onQuiet(60_000))
        assertEquals(0, b.misses())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

CI falha com `Unresolved reference: FalseTriggerBackoff`.

- [ ] **Step 3: Write minimal implementation**

```kotlin
package com.viniciusnpaula.ultron_mobile

/**
 * Política para gatilhos do Porcupine que não viraram comando.
 *
 * Um falso positivo custa caro (carregar o Vosk e transcrever), então misses
 * consecutivos aumentam a espera antes de aceitar o próximo gatilho.
 */
class FalseTriggerBackoff(
    private val baseCooldownMs: Long = 1_500L,
    private val quietResetMs: Long = 60_000L,
    private val maxBackoffMs: Long = 30_000L,
) {
    private var misses = 0
    private var lastMissMs = 0L

    fun onMiss(nowMs: Long): Long {
        misses++
        lastMissMs = nowMs
        if (misses < 3) return baseCooldownMs
        val step = (misses - 3).coerceAtMost(4)
        return (5_000L shl step).coerceAtMost(maxBackoffMs)
    }

    fun onSuccess(nowMs: Long) {
        misses = 0
        lastMissMs = nowMs
    }

    /** Zera contadores após um período de silêncio; devolve true se zerou. */
    fun onQuiet(nowMs: Long): Boolean {
        if (misses > 0 && nowMs - lastMissMs >= quietResetMs) {
            misses = 0
            return true
        }
        return false
    }

    fun misses(): Int = misses
}
```

- [ ] **Step 4: Run test to verify it passes**

`:app:testDebugUnitTest` verde.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/com/viniciusnpaula/ultron_mobile/FalseTriggerBackoff.kt \
        android/app/src/test/kotlin/com/viniciusnpaula/ultron_mobile/FalseTriggerBackoffTest.kt
git commit -m "feat(kws): backoff de falso positivo (Task 3)"
```

---

### Task 4: Dependências e BuildConfig

**Files:**
- Modify: `android/app/build.gradle.kts`
- Create: `android/app/src/main/assets/porcupine/README.md`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `BuildConfig.PORCUPINE_ACCESS_KEY: String` (vazio quando não configurado) e as classes `ai.picovoice.porcupine.*` / `org.vosk.*` no classpath.

**Acceptance Criteria:**
- Build sem key compila.
- `./gradlew :app:assembleDebug -PporcupineAccessKey=teste` gera `BuildConfig` com o valor.
- `.ppn` e modelo Vosk não são versionados por acidente (modelo ignorado; `.ppn` é versionado).

- [ ] **Step 1: Add dependencies and buildConfig**

Em `android/app/build.gradle.kts`, dentro de `android { }`:

```kotlin
    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        // ...
        buildConfigField(
            "String",
            "PORCUPINE_ACCESS_KEY",
            "\"${(project.findProperty("porcupineAccessKey") as String?) ?: System.getenv("PORCUPINE_ACCESS_KEY") ?: ""}\""
        )
    }
```

E nas dependências:

```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("ai.picovoice:porcupine-android:3.0.1")
    implementation("com.alphacephei:vosk-android:0.3.47@aar")
    implementation("net.java.dev.jna:jna:5.13.0@aar")
    testImplementation("junit:junit:4.13.2")
}
```

- [ ] **Step 2: Document the keyword asset location**

Crie `android/app/src/main/assets/porcupine/README.md`:

```markdown
# Keyword do Porcupine

Coloque aqui `ultron_pt.ppn`, treinado no Picovoice Console:

1. https://console.picovoice.ai/ → Porcupine → Create Wake Word
2. Idioma: Portuguese. Frase: `ultron`.
3. Plataforma: Android. Baixe o `.ppn` e salve com este nome exato:

```
android/app/src/main/assets/porcupine/ultron_pt.ppn
```

Sem este arquivo o app compila e reporta "KWS não configurado"; a palavra de
ativação fica desligada (não há fallback por volume).
```

- [ ] **Step 3: Ignore the Vosk model**

Adicione ao `.gitignore`:

```
android/app/src/main/assets/vosk/
```

- [ ] **Step 5: Verify the build without a key**

Push; o CI deve concluir `Build debug APK` sem erro. O caminho com key é coberto pela
Task 10 (assert no workflow), não aqui.

- [ ] **Step 6: Commit**

```bash
git add android/app/build.gradle.kts .gitignore \
        android/app/src/main/assets/porcupine/README.md
git commit -m "build(kws): dependencias Porcupine/Vosk e BuildConfig da AccessKey (Task 4)"
```

---

### Task 5: Wrapper do Porcupine

**Files:**
- Create: `android/app/src/main/kotlin/com/viniciusnpaula/ultron_mobile/PorcupineKeywordSpotter.kt`

**Interfaces:**
- Consumes: `BuildConfig.PORCUPINE_ACCESS_KEY`
- Produces: `class PorcupineKeywordSpotter(context: Context, accessKey: String, keywordAsset: String = "porcupine/ultron_pt.ppn")` com `init()`, `isConfigured: Boolean`, `unavailableReason: String?`, `frameLength: Int`, `process(frame: ShortArray): Boolean`, `close()`.

**Acceptance Criteria:**
- Sem key ou sem asset: `isConfigured == false` e `unavailableReason` preenchido, sem exceção.
- Com key e asset válidos: `frameLength == 512`.
- `close()` pode ser chamado duas vezes.

- [ ] **Step 1: Write the implementation**

```kotlin
package com.viniciusnpaula.ultron_mobile

import android.content.Context
import ai.picovoice.porcupine.Porcupine
import java.io.File

/**
 * Motor de keyword spotting dedicado (Porcupine).
 *
 * O `.ppn` é treinado no Picovoice Console para a frase "ultron" em português.
 * Ele vive em assets e precisa ser copiado para um arquivo real: a API do
 * Porcupine recebe caminho, não asset.
 */
class PorcupineKeywordSpotter(
    private val context: Context,
    private val accessKey: String,
    private val keywordAsset: String = "porcupine/ultron_pt.ppn",
) {
    private var porcupine: Porcupine? = null
    var unavailableReason: String? = null
        private set

    val isConfigured: Boolean get() = porcupine != null
    val frameLength: Int get() = porcupine?.frameLength ?: FRAME_FALLBACK

    fun init() {
        if (accessKey.isBlank()) {
            unavailableReason = "AccessKey ausente"
            return
        }
        val keywordFile = try {
            copyAsset(keywordAsset)
        } catch (_: Exception) {
            unavailableReason = "keyword .ppn ausente em assets/$keywordAsset"
            return
        }
        try {
            porcupine = Porcupine.Builder()
                .setAccessKey(accessKey)
                .setKeywordPath(keywordFile.absolutePath)
                .setSensitivity(SENSITIVITY)
                .build(context)
            unavailableReason = null
        } catch (e: Exception) {
            // Mensagem do Porcupine é segura (não contém a key). Nunca logar accessKey.
            unavailableReason = "falha ao iniciar Porcupine: ${e.message}"
            porcupine = null
        }
    }

    /** true quando a palavra foi detectada neste frame de [frameLength] amostras. */
    fun process(frame: ShortArray): Boolean {
        val engine = porcupine ?: return false
        return engine.process(frame) == 1
    }

    fun close() {
        try {
            porcupine?.delete()
        } catch (_: Exception) {
        } finally {
            porcupine = null
        }
    }

    private fun copyAsset(assetPath: String): File {
        val dir = File(context.filesDir, "porcupine").apply { mkdirs() }
        val out = File(dir, assetPath.substringAfterLast('/'))
        context.assets.open(assetPath).use { input ->
            out.outputStream().use { output -> input.copyTo(output) }
        }
        return out
    }

    private companion object {
        const val SENSITIVITY = 0.5f
        const val FRAME_FALLBACK = 512
    }
}
```

- [ ] **Step 2: Verify it compiles**

Push; `Native unit tests` e `Build debug APK` verdes (compilação é a verificação; a
detecção real depende do `.ppn`).

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/viniciusnpaula/ultron_mobile/PorcupineKeywordSpotter.kt
git commit -m "feat(kws): wrapper do Porcupine com estado de configuracao honesto (Task 5)"
```

---

### Task 6: Transcritor Vosk com pré-roll

**Files:**
- Create: `android/app/src/main/kotlin/com/viniciusnpaula/ultron_mobile/VoskCommandTranscriber.kt`

**Interfaces:**
- Produces:
  - `class VoskCommandTranscriber(context: Context, modelAsset: String = "vosk/model-pt.zip", modelDirName: String = "vosk-model-small-pt-0.3")`
  - `ensureLoaded(): Boolean`
  - `transcribe(preroll: ShortArray, readMore: (ShortArray) -> Int, maxMs: Long = 5_000L): String`
  - `unloadAfterIdle(nowMs: Long, idleMs: Long = 120_000L)`
  - `isLoaded: Boolean`, `lastError: String?`, `close()`

**Acceptance Criteria:**
- Sem asset de modelo: `ensureLoaded()` devolve `false`, `lastError` explica, sem crash.
- Modelo é descompactado uma vez; segunda chamada não re-descompacta.
- `transcribe` devolve `""` quando não há fala.
- `unloadAfterIdle` não descarrega durante transcrição e respeita `idleMs`.

- [ ] **Step 1: Write the implementation**

```kotlin
package com.viniciusnpaula.ultron_mobile

import android.content.Context
import org.vosk.Model
import org.vosk.Recognizer
import java.io.File
import java.util.zip.ZipInputStream

/**
 * Transcreve o comando usando Vosk offline.
 *
 * Diferente do SpeechRecognizer, o Vosk aceita PCM injetado — é isso que torna o
 * pré-roll possível: o áudio anterior ao gatilho entra antes do áudio ao vivo.
 */
class VoskCommandTranscriber(
    private val context: Context,
    private val modelAsset: String = "vosk/model-pt.zip",
    private val modelDirName: String = "vosk-model-small-pt-0.3",
) {
    private var model: Model? = null
    private var lastUsedMs = 0L
    var lastError: String? = null
        private set

    val isLoaded: Boolean get() = model != null

    fun ensureLoaded(): Boolean {
        model?.let { return true }
        val dir = File(context.filesDir, modelDirName)
        return try {
            if (!dir.exists()) unzipAsset(dir)
            model = Model(dir.absolutePath)
            lastUsedMs = System.currentTimeMillis()
            lastError = null
            true
        } catch (e: Exception) {
            lastError = "modelo Vosk indisponível: ${e.message}"
            model = null
            false
        }
    }

    /**
     * Transcreve [preroll] e depois pede mais áudio a [readMore] até o Vosk sinalizar
     * fim de fala ou [maxMs] estourar. [readMore] devolve amostras lidas; <= 0 encerra.
     */
    fun transcribe(
        preroll: ShortArray,
        readMore: (ShortArray) -> Int,
        maxMs: Long = 5_000L,
    ): String {
        val loaded = model ?: return ""
        val recognizer = try {
            Recognizer(loaded, SAMPLE_RATE.toFloat())
        } catch (e: Exception) {
            lastError = "Recognizer Vosk falhou: ${e.message}"
            return ""
        }
        try {
            if (preroll.isNotEmpty()) recognizer.acceptWaveForm(preroll, preroll.size)
            val buffer = ShortArray(CHUNK_SAMPLES)
            var elapsedMs = 0L
            while (elapsedMs < maxMs) {
                val count = readMore(buffer)
                if (count <= 0) break
                if (recognizer.acceptWaveForm(buffer, count)) break
                elapsedMs += CHUNK_MS
            }
            return recognizer.finalResult
        } catch (e: Exception) {
            lastError = "transcrição falhou: ${e.message}"
            return ""
        } finally {
            lastUsedMs = System.currentTimeMillis()
            try {
                recognizer.close()
            } catch (_: Exception) {
            }
        }
    }

    fun unloadAfterIdle(nowMs: Long, idleMs: Long = 120_000L) {
        val current = model ?: return
        if (nowMs - lastUsedMs < idleMs) return
        try {
            current.close()
        } catch (_: Exception) {
        }
        model = null
    }

    fun close() {
        try {
            model?.close()
        } catch (_: Exception) {
        } finally {
            model = null
        }
    }

    private fun unzipAsset(targetDir: File) {
        val parent = targetDir.parentFile ?: context.filesDir
        val temp = File(parent, "${targetDir.name}.tmp")
        temp.deleteRecursively()
        context.assets.open(modelAsset).use { input ->
            ZipInputStream(input).use { zip ->
                var entry = zip.nextEntry
                while (entry != null) {
                    val out = File(temp, entry.name)
                    if (entry.isDirectory) {
                        out.mkdirs()
                    } else {
                        out.parentFile?.mkdirs()
                        out.outputStream().use { zip.copyTo(it) }
                    }
                    zip.closeEntry()
                    entry = zip.nextEntry
                }
            }
        }
        // O zip carrega a pasta raiz vosk-model-small-pt-0.3/; o destino final já tem esse nome.
        val extractedRoot = File(temp, modelDirName)
        val source = if (extractedRoot.exists()) extractedRoot else temp
        if (!source.renameTo(targetDir)) {
            source.copyRecursively(targetDir, overwrite = true)
            temp.deleteRecursively()
        }
        require(targetDir.exists()) { "modelo não descompactou em ${targetDir.name}" }
    }

    private companion object {
        const val SAMPLE_RATE = 16_000
        const val CHUNK_SAMPLES = 3_200 // 200 ms
        const val CHUNK_MS = 200L
    }
}
```

Nota: `ensureLoaded()` chama `unzipAsset(dir)` e depois `Model(dir.absolutePath)`; se
`dir` não existir após a extração, `require` lança e `lastError` explica — nunca seguir com
modelo inválido.

- [ ] **Step 2: Verify it compiles**

`:app:compileDebugKotlin` verde no CI.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/kotlin/com/viniciusnpaula/ultron_mobile/VoskCommandTranscriber.kt
git commit -m "feat(kws): transcritor Vosk com pre-roll e descarga por inatividade (Task 6)"
```

---

### Task 7: Integração no serviço de captura

**Files:**
- Modify: `android/app/src/main/kotlin/com/viniciusnpaula/ultron_mobile/UltronAudioService.kt`

**Interfaces:**
- Consumes: `AudioRingBuffer`, `PorcupineKeywordSpotter`, `VoskCommandTranscriber`, `WakePhraseComposer`, `FalseTriggerBackoff`
- Produces: `onVoiceWakeTriggered(preroll: ShortArray, transcriber: VoskCommandTranscriber, readMore: (ShortArray) -> Int): String?` (contrato interno)

**Acceptance Criteria:**
- Loop lê 512 amostras a 16 kHz e alimenta Porcupine + anel.
- Microfone não é liberado entre gatilho e transcrição.
- Pausas (usuário, chamada, flip-to-shush, TTS, bateria) continuam liberando o microfone.
- Texto vazio não vira ativação nem notificação.
- `captureHealthy` continua falso quando não há leitura real.
- Sem KWS configurado o loop **encerra** (não lê nem descarta áudio) e a notificação explica.

- [ ] **Step 1: Fail fast when the spotter is not configured**

```kotlin
        Stats.kwsConfigured = spotter.isConfigured
        Stats.kwsUnavailableReason = spotter.unavailableReason ?: ""
        if (!spotter.isConfigured) {
            captureHealthy = false
            Stats.lastError = "KWS indisponível: ${Stats.kwsUnavailableReason}"
            updateNotification("KWS não configurado — ativação por voz indisponível")
            spotter.close()
            return
        }
```

- [ ] **Step 2: Replace the capture loop**

Substitua o corpo de `runCaptureSession()` mantendo as guardas. Estrutura final:

```kotlin
    private fun runCaptureSession() {
        val spotter = PorcupineKeywordSpotter(applicationContext, BuildConfig.PORCUPINE_ACCESS_KEY)
        spotter.init()
        Stats.kwsConfigured = spotter.isConfigured
        Stats.kwsUnavailableReason = spotter.unavailableReason ?: ""
        // Falha rápida: sem motor configurado o loop não pode ler e descartar áudio,
        // nem deixar a UI dizendo "capturando" (mesmo pecado da v1.2.1).
        if (!spotter.isConfigured) {
            captureHealthy = false
            Stats.lastError = "KWS indisponível: ${Stats.kwsUnavailableReason}"
            updateNotification("KWS não configurado — ativação por voz indisponível")
            spotter.close()
            return
        }
        val transcriber = VoskCommandTranscriber(applicationContext)
        val ring = AudioRingBuffer(PREROLL_SAMPLES)
        val backoff = FalseTriggerBackoff()
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        var recorder: AudioRecord? = null
        var silentFrames = 0
        var frame = ShortArray(spotter.frameLength)

        try {
            while (workerActive.get()) {
                if (isBatteryCriticalUnplugged()) { /* igual ao atual */ }
                if (Stats.economyMode) { /* igual ao atual */ }
                if (userPaused || inCall || MainActivity.isFaceDownGlobal) { /* igual */ }
                if (isSpeakerOrRecognizerBusy(audioManager)) { /* igual */ }
                if (recorder == null) {
                    recorder = createRecorder()
                    silentFrames = 0
                }

                // Alocado uma vez: 512 amostras por frame a 32 ms, ~31 alocacoes/s seriam lixo.
                if (frame.size != spotter.frameLength) frame = ShortArray(spotter.frameLength)
                val readCount = recorder.read(frame, 0, frame.size)
                if (readCount < 0) throw IllegalStateException("AudioRecord.read=$readCount")
                if (isSpeakerOrRecognizerBusy(audioManager)) continue
                if (readCount == 0) { /* watchdog igual ao atual, sem conta de RMS */ }

                val rms = computeRms(frame, readCount)
                if (rms == 0.0) { /* watchdog igual ao atual */ } else {
                    captureHealthy = true
                    consecutiveFailures = 0
                    Stats.noiseFloor = rms
                }

                ring.write(frame, readCount)
                val triggered = spotter.isConfigured && spotter.process(frame)
                if (!triggered) {
                    backoff.onQuiet(System.currentTimeMillis())
                    transcriber.unloadAfterIdle(System.currentTimeMillis())
                    continue
                }

                captureHealthy = true
                val activeRecorder = recorder ?: continue
                val phrase = onVoiceWakeTriggered(ring.snapshot(), transcriber) { buffer ->
                    activeRecorder.read(buffer, 0, buffer.size)
                }
                ring.clear()
                if (phrase != null) {
                    backoff.onSuccess(System.currentTimeMillis())
                    MainActivity.notifyWakeWord(phrase)
                } else {
                    Thread.sleep(backoff.onMiss(System.currentTimeMillis()))
                }
            }
        } finally {
            spotter.close()
            transcriber.close()
            releaseRecorder(recorder)
        }
    }
```

- [ ] **Step 3: Replace the wake handler**

```kotlin
    /** Retorna a frase a entregar, ou null quando não houve comando útil. */
    private fun onVoiceWakeTriggered(
        preroll: ShortArray,
        transcriber: VoskCommandTranscriber,
        readMore: (ShortArray) -> Int,
    ): String? {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (isSpeakerOrRecognizerBusy(audioManager)) return null

        val nowStr = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())
        lastTriggerTimestamp = nowStr
        Stats.voiceTriggers++
        Stats.wakeDetections++
        updateNotification("Palavra detectada — ouvindo comando ($nowStr)")

        wakeLock?.acquire(15_000L)
        val startedMs = System.currentTimeMillis()
        val phrase: String? = if (!transcriber.ensureLoaded()) {
            Stats.lastError = transcriber.lastError ?: "Vosk indisponível"
            null // entrega só "ultron": o Dart cai na voz manual
        } else {
            val text = transcriber.transcribe(preroll, readMore).trim()
            if (text.length < 2) null else WakePhraseComposer.ensurePhrase(text)
        }
        Stats.lastCommandMs = System.currentTimeMillis() - startedMs
        releaseWakeLockSafely()
        updateNotification("Escuta contínua ativa — diga \"Ultron\"")

        if (phrase == null) {
            Stats.recognizerMisses++
            // Vosk carregado mas sem fala = miss; Vosk quebrado = comando manual.
            return if (transcriber.isLoaded) null else "ultron"
        }
        Stats.detections++
        Stats.voskCommands++
        Stats.lastPhrase = phrase
        return phrase
    }
```

- [ ] **Step 4: Update constants and Stats**

```kotlin
    private const val SAMPLE_RATE_HZ = 16_000
    private const val PREROLL_SAMPLES = 24_000 // 1,5 s a 16 kHz
```

Adicione os contadores novos em `Stats` (a Task 8 só os expõe):

```kotlin
        @Volatile var wakeDetections = 0
        @Volatile var voskCommands = 0
        @Volatile var voskLoadMs = 0L
        @Volatile var lastCommandMs = 0L
        @Volatile var voskResident = false
        @Volatile var kwsConfigured = false
        @Volatile var kwsUnavailableReason: String = "não inicializado"
```

Remova `WINDOW_MS`, `MIN_VOICE_RMS`, `MAX_VOICE_RMS`, `NOISE_MARGIN`,
`INITIAL_NOISE_FLOOR`, `VOICE_FRAMES_TO_TRIGGER`, `BASE_MISS_COOLDOWN_MS`,
`MAX_MISS_COOLDOWN_MS`, `DETECTED_COOLDOWN_MS`, `RECOGNIZER_WAIT_MS`,
`wakeWordRecognizer` e a criação de `UltronWakeWordRecognizer`.

Ajuste também os inicializadores de `Stats`, que hoje referenciam as constantes removidas:

```kotlin
        @Volatile var noiseFloor = 300.0
        @Volatile var threshold = 0.0 // sem gate; mantido só para não quebrar o contrato do Dart
```

- [ ] **Step 5: Verify compile and tests**

CI verde em `Native unit tests` e `Build debug APK`.

- [ ] **Step 6: Commit (dois commits, mesmo push)**

```bash
git add android/app/src/main/kotlin/com/viniciusnpaula/ultron_mobile/UltronAudioService.kt
git commit -m "feat(kws): captura unica de 16 kHz com Porcupine e pre-roll (Task 7)"
# se o handler ficou em um segundo momento de edicao:
git add android/app/src/main/kotlin/com/viniciusnpaula/ultron_mobile/UltronAudioService.kt
git commit -m "feat(kws): handler de comando por Vosk com backoff (Task 7)"
```

---

### Task 8: Diagnóstico e HUD com o motor real

**Files:**
- Modify: `android/app/src/main/kotlin/com/viniciusnpaula/ultron_mobile/UltronAudioService.kt` (`Stats` e `diagnostics`)
- Modify: `lib/services/device_control_service.dart`
- Modify: `lib/ui/screens/core_screen.dart`

**Interfaces:**
- Produces: campos JSON `engine`, `dedicatedKws`, `kwsUnavailableReason`, `wakeDetections`, `voskCommands`, `voskLoadMs`, `lastCommandMs`, `voskResident`.

**Acceptance Criteria:**
- Com KWS configurado: `dedicatedKws == true` e `engine` cita Porcupine + Vosk.
- Sem configuração: `dedicatedKws == false` e `kwsUnavailableReason` não vazio.
- HUD mostra o motivo, não um texto fixo.

- [ ] **Step 1: Extend Stats and diagnostics**

```kotlin
    object Stats {
        // ... campos existentes (os novos entram na Task 7) ...
    }
```

Em `diagnostics(context)`:

```kotlin
                "engine" to if (Stats.kwsConfigured) "Porcupine pt-BR + Vosk (KWS dedicado)"
                            else "KWS não configurado",
                "dedicatedKws" to Stats.kwsConfigured,
                "kwsUnavailableReason" to Stats.kwsUnavailableReason,
                "wakeDetections" to Stats.wakeDetections,
                "voskCommands" to Stats.voskCommands,
                "voskLoadMs" to Stats.voskLoadMs,
                "lastCommandMs" to Stats.lastCommandMs,
                "voskResident" to Stats.voskResident,
```

Os campos `kwsConfigured`/`kwsUnavailableReason` são preenchidos na Task 7 (fail fast);
aqui só são expostos. `voskLoadMs` pode ser medido em `ensureLoaded()` — se preferir
simplicidade, deixe em 0 e não invente número.

- [ ] **Step 2: Extend the Dart status model**

Em `lib/services/device_control_service.dart`, adicione ao construtor/campos/`fromMap`
(seguindo o padrão existente):

```dart
    this.kwsUnavailableReason = '',
    // ...
    final String kwsUnavailableReason;
    // fromMap:
    kwsUnavailableReason: s('kwsUnavailableReason', ''),
```

E na string de diagnóstico:

```dart
    if (kwsUnavailableReason.isNotEmpty) 'KWS: $kwsUnavailableReason',
```

- [ ] **Step 3: Show it in the HUD**

Em `lib/ui/screens/core_screen.dart`, onde o status do sentinela é renderizado, troque o
texto fixo de pendência por `hwStatus.kwsUnavailableReason` quando não vazio (mantendo o
texto atual como fallback).

- [ ] **Step 4: Verify**

CI verde (`Analyze`, `Test`, `Native unit tests`).

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/com/viniciusnpaula/ultron_mobile/UltronAudioService.kt \
        lib/services/device_control_service.dart lib/ui/screens/core_screen.dart
git commit -m "feat(kws): diagnostico e HUD reportam o motor real (Task 8)"
```

---

### Task 9: Remover o caminho antigo

**Files:**
- Delete: `android/app/src/main/kotlin/com/viniciusnpaula/ultron_mobile/UltronWakeWordRecognizer.kt`
- Modify: `docs/WAKE_WORD_AUDIT.md`

**Acceptance Criteria:**
- Nenhuma referência a `UltronWakeWordRecognizer` no código.
- `ENGINE_DESCRIPTION`/`ENGINE_IS_DEDICATED_KWS` não existem mais como constantes.

- [ ] **Step 1: Confirm no references**

```bash
grep -rn "UltronWakeWordRecognizer\|ENGINE_IS_DEDICATED_KWS\|ENGINE_DESCRIPTION" android/app/src lib
```

Esperado: nenhuma saída depois da remoção.

- [ ] **Step 2: Delete the file and constants**

```bash
git rm android/app/src/main/kotlin/com/viniciusnpaula/ultron_mobile/UltronWakeWordRecognizer.kt
```

- [ ] **Step 3: Update the audit doc**

Acrescente em `docs/WAKE_WORD_AUDIT.md` uma seção "Fase 3 — motor dedicado" com a decisão
(D1–D9 da spec), o que foi removido (porta de volume, `UltronWakeWordRecognizer`) e o que
depende do usuário (`.ppn`, AccessKey).

- [ ] **Step 4: Verify and commit**

```bash
git add -A
git commit -m "refactor(kws): remove o reconhecedor de hotword do caminho de volume (Task 9)"
```

---

### Task 10: CI com modelo Vosk e AccessKey

**Files:**
- Modify: `.github/workflows/flutter-ci.yml`

**Acceptance Criteria:**
- Build sem secret continua verde e registra aviso de "APK sem KWS".
- Com secret, o `BuildConfig` é validado.
- Modelo baixado é verificado pelo SHA-256 fixo; download adulterado falha o build.

- [ ] **Step 1: Add model fetch step**

Depois de `Restore committed files` e de `Free disk space`, antes de `Build debug APK`
(assim vale para debug e release):

```yaml
      - name: Fetch Vosk model
        run: |
          mkdir -p android/app/src/main/assets/vosk
          curl -sSL -o /tmp/vosk-model.zip \
            https://alphacephei.com/vosk/models/vosk-model-small-pt-0.3.zip
          echo "6e1ce909032e1afa7a88e68a3d628ecafff302bdf195befab308826c395e93b7  /tmp/vosk-model.zip" \
            | sha256sum -c -
          mv /tmp/vosk-model.zip android/app/src/main/assets/vosk/model-pt.zip
```

- [ ] **Step 2: Inject the secret into every Gradle invocation**

O `env` do job (topo de `validate:`) propaga para `flutter build apk` **e** para qualquer
`./gradlew`, via a convenção `ORG_GRADLE_PROJECT_`:

```yaml
    env:
      ORG_GRADLE_PROJECT_porcupineAccessKey: ${{ secrets.PORCUPINE_ACCESS_KEY }}
      PORCUPINE_ACCESS_KEY: ${{ secrets.PORCUPINE_ACCESS_KEY }}
```

E no passo de build:

```yaml
      - name: Build debug APK
        run: |
          if [ -z "$PORCUPINE_ACCESS_KEY" ]; then
            echo "::warning::PORCUPINE_ACCESS_KEY ausente — APK sai sem palavra de ativacao"
          fi
          flutter build apk --debug
```

- [ ] **Step 3: Assert the generated BuildConfig after the build**

```yaml
      - name: Assert Porcupine key when configured
        if: env.PORCUPINE_ACCESS_KEY != ''
        run: |
          GREP_FILE=$(find android/app/build/generated/source/buildConfig -name BuildConfig.java | head -1)
          grep -q 'PORCUPINE_ACCESS_KEY' "$GREP_FILE"
          ! grep -q 'PORCUPINE_ACCESS_KEY = ""' "$GREP_FILE"
```

- [ ] **Step 4: Verify both paths**

Verde sem secret (push normal). Para o caminho com secret, registre no PR que o teste real
depende de o secret existir no repositório — não invente um valor.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/flutter-ci.yml
git commit -m "ci(kws): modelo Vosk verificado por hash e assert da AccessKey (Task 10)"
```

---

### Task 11: Medição de bateria

**Files:**
- Create: `scripts/battery-test.ps1`
- Create: `scripts/perfetto-ultron.cfg`

**Acceptance Criteria:**
- Script recusa rodar sem dispositivo e sem app instalado.
- Reinicia `batterystats`, espera 60 min, calcula %/h e mAh.
- Config do Perfetto é válida para `perfetto --config`.

- [ ] **Step 1: Write the scripts**

`scripts/battery-test.ps1`:

```powershell
param(
    [int]$Minutes = 60,
    [string]$Package = "com.viniciusnpaula.ultron_mobile"
)
$ErrorActionPreference = "Stop"
$devices = (adb devices | Select-String "device$")
if (-not $devices) { throw "Nenhum dispositivo adb conectado." }
if (-not (adb shell pm list packages $Package)) { throw "App nao instalado: $Package" }

adb shell dumpsys batterystats --reset | Out-Null
$start = Get-Date
adb shell dumpsys battery | Select-String "level"
Write-Host "Aguardando $Minutes min com a tela apagada..."
Start-Sleep -Seconds ($Minutes * 60)
adb shell dumpsys battery | Select-String "level"
$report = Join-Path $PSScriptRoot "battery-report.txt"
adb shell dumpsys batterystats $Package > $report
adb shell dumpsys power >> $report
Write-Host "Relatorio em $report"
Write-Host ("Duracao: {0:N1} min" -f ((Get-Date) - $start).TotalMinutes)
```

`scripts/perfetto-ultron.cfg`:

```
buffers: {
    size_kb: 32768
    fill_policy: RING_BUFFER
}
data_sources: { config { name: "linux.ftrace" ftrace_config {
    ftrace_events: "sched/sched_switch"
    ftrace_events: "power/cpu_frequency"
    ftrace_events: "power/suspend_resume"
} } }
data_sources: { config { name: "android.power" } }
duration_ms: 300000
```

- [ ] **Step 2: Verify locally**

```powershell
powershell -NoProfile -File scripts/battery-test.ps1 -Minutes 0
```

Esperado (sem aparelho): erro claro "Nenhum dispositivo adb conectado." — não stack trace.

- [ ] **Step 3: Commit**

```bash
git add scripts/battery-test.ps1 scripts/perfetto-ultron.cfg
git commit -m "chore(bateria): script de medicao e config do Perfetto (Task 11)"
```

---

### Task 12: Protocolo de testes físicos

**Files:**
- Create: `docs/PHYSICAL_TEST_PROTOCOL.md`
- Create: `scripts/physical-test.ps1`

**Acceptance Criteria:**
- 12 cenários com passos e critério de aceite verificável.
- Script instala o APK, limpa logcat, acompanha a tag `Ultron` e imprime o diagnóstico.

- [ ] **Step 1: Write the protocol**

`docs/PHYSICAL_TEST_PROTOCOL.md` deve conter, para cada cenário: preparação, passos, o que
observar no HUD, e aceite (PASS/FAIL). Os 12: app aberto; background; tela bloqueada; swipe
dos recentes; chamada em curso; flip-to-shush; TTS falando; bateria <15%; reboot; headset
Bluetooth; ruído de TV; comando na mesma respiração.

Exemplo de entrada (repita no mesmo formato para os 12):

```markdown
### 1. App aberto
- Preparação: app em primeiro plano, sentinela ativo, HUD sem pendências.
- Passos: dizer "Ultron, que horas são".
- Observar: HUD muda para "Palavra detectada — ouvindo comando" e volta.
- Aceite: comando executado, `wakeDetections` +1 e `voskCommands` +1 no diagnóstico.
```

- [ ] **Step 2: Write the helper script**

```powershell
param([string]$Apk = "build\app\outputs\flutter-apk\app-debug.apk")
$ErrorActionPreference = "Stop"
if (-not (adb devices | Select-String "device$")) { throw "Nenhum dispositivo adb conectado." }
adb install -r $Apk
adb logcat -c
Write-Host "Rode os cenarios. Ctrl+C encerra a coleta."
adb logcat -s UltronWake:V
```

- [ ] **Step 3: Verify the script fails honestly**

Rodar sem aparelho deve imprimir "Nenhum dispositivo adb conectado.".

- [ ] **Step 4: Commit**

```bash
git add docs/PHYSICAL_TEST_PROTOCOL.md scripts/physical-test.ps1
git commit -m "docs(testes): protocolo fisico de 12 cenarios (Task 12)"
```

---

### Task 13: Versão, notas e fechamento

**Files:**
- Modify: `pubspec.yaml`
- Create: `CHANGELOG.md`
- Modify: `docs/WAKE_WORD_AUDIT.md`

**Acceptance Criteria:**
- `version: 1.3.0+15`.
- Nota de release explica que a palavra exige `.ppn` + AccessKey e que sem eles a feature
  fica desligada.
- CI verde com a versão nova (release APK deve reportar `versionCode='15' versionName='1.3.0'`).

- [ ] **Step 1: Bump version and write the note**

```yaml
version: 1.3.0+15
```

`CHANGELOG.md`:

```markdown
## 1.3.0+15 — Motor KWS dedicado

- Detecção da palavra "Ultron" por Porcupine (KWS dedicado, 16 kHz), sem porta de volume.
- Comando capturado com pré-roll de 1,5 s e transcrito offline pelo Vosk.
- Diagnóstico/HUD reportam o motor real e o motivo quando não há configuração.
- **Requer configuração:** `ultron_pt.ppn` em `android/app/src/main/assets/porcupine/` e
  `PORCUPINE_ACCESS_KEY`. Sem isso, a palavra de ativação fica desligada (a voz manual
  continua funcionando).
- APK cresce ~32 MB (modelo Vosk embarcado).
```

- [ ] **Step 2: Verify the release metadata**

No CI, o passo `Check release APK permissions and app id` deve imprimir
`versionCode='15' versionName='1.3.0'`.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml CHANGELOG.md docs/WAKE_WORD_AUDIT.md
git commit -m "chore(release): 1.3.0+15 com motor KWS dedicado (Task 13)"
```

---

## Cobertura da spec

| Requisito da spec | Task |
|---|---|
| D1 Porcupine | 5, 7 |
| D2 Vosk + pré-roll | 1, 6, 7 |
| D3 modelo embarcado | 4, 6, 10 |
| D4 AccessKey via secret | 4, 10 |
| D5 descarga do Vosk | 6, 7 |
| D6 frase com hotword | 2, 7 |
| D7 sem fallback | 7, 9 |
| D8 falso positivo/backoff | 3, 7 |
| D9 versão 1.3.0+15 | 13 |
| Seção 3.2 pausas existentes | 7 |
| Seção 4 componentes | 1–6 |
| Seção 6 build/assets | 4, 10 |
| Seção 7 bateria/instrumentação | 8, 11 |
| Seção 8 testes | 1, 2, 3, 12 |
| Seção 9 riscos | 13 (nota), 10 (hash) |
| Segurança (áudio em RAM, key não logada) | 1, 5, 6 |

## Riscos residuais do plano

- O `.ppn` e a AccessKey são do usuário; sem eles a Task 5 não tem verificação de detecção real.
- `Porcupine.Builder`/`Porcupine.process` e `org.vosk.*` são usados pela API pública documentada; se a versão 3.0.1 divergir, o erro aparece na compilação do CI e deve ser corrigido na task correspondente — não no plano.
- Os testes de loop continuam impossíveis em JVM; a cobertura real é compilação + protocolo físico.

## Rollback

Sem feature flag. Reverter os commits das tasks (`git revert <sha>...`) ou resetar a branch
devolve o motor antigo, que permanece no histórico. Um flag "Porcupine ou porta de volume"
recriaria os dois motores que a D7 eliminou.

## Stress Test Results: plano KWS

### Resolved Decisions
- **Sem KWS configurado o loop encerra** (Task 7): `captureHealthy = false`, notificação
  explica e o worker retorna. Nada de ler e descartar áudio.
- **AccessKey via `ORG_GRADLE_PROJECT_porcupineAccessKey`** no `env` do job (Task 10), para
  que `flutter build apk` e `./gradlew` herdem a propriedade; assert roda depois do build e
  rejeita `PORCUPINE_ACCESS_KEY = ""`.
- **Ordem no CI**: fetch do modelo depois de `Restore committed files` e de `Free disk
  space`, antes do build; vale para debug e release.
- **Task 7 unificada com dois commits** (captura, handler) no mesmo push.
- **Rollback por git**, sem flag de runtime.

### Changes Made
- Task 7 ganhou o passo "fail fast when the spotter is not configured"; passos renumerados;
  commit dividido em dois.
- Task 8 deixou de duplicar a atribuição de `Stats.kwsConfigured`.
- Task 10 reescrita: `env` do job, assert `if: env.PORCUPINE_ACCESS_KEY != ''`, comando de
  grep em arquivo único (sem quebra de linha em caminho).
- Seção "Rollback" adicionada.

### Deferred / Parking Lot
- Medição de `voskLoadMs` fica em 0 se não for instrumentada — não inventar número.
- Treinar modelo próprio de KWS.

### Confidence Assessment
- Overall: **High** para o plano; **Medium** para o resultado final, limitado pela ausência
  de `.ppn`, AccessKey e aparelho.
- Áreas de preocupação: comportamento em runtime do Porcupine/Vosk só se prova com o modelo
  e um telefone; task 7 é a de maior risco e deve ser revisada com atenção.
