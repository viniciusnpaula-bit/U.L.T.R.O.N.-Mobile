# Auditoria do Wake Word — U.L.T.R.O.N. Mobile v1.2.1

> Documento histórico da v1.2.1 (antes do sherpa-onnx). O motor atual é o Zipformer KWS offline descrito em `docs/SHERPA_KWS.md`; a evidência sobre o Vosk abaixo continua válida para justificar por que ele não foi usado.

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
