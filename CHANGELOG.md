# Changelog — U.L.T.R.O.N. Mobile

## 1.3.0+15 — Motor KWS dedicado (Porcupine) + pré-roll (Vosk)

- Detecção da palavra "Ultron" pelo Porcupine (KWS dedicado, 16 kHz, mono, PCM16), sem porta de volume.
- Comando capturado com pré-roll de 1,5 s e transcrito offline pelo Vosk (sem handoff do microfone).
- Diagnóstico e HUD reportam o motor real e o motivo quando não há configuração (`kwsUnavailableReason`).
- Falsos positivos: miss silencioso com cooldown de 1,5 s e backoff 5 s → 10 s → 20 s (teto 30 s).
- **Requer configuração:** `ultron_pt.ppn` em `android/app/src/main/assets/porcupine/` (treine no Picovoice Console) e
  `PORCUPINE_ACCESS_KEY` (GitHub Secret no build de CI). Sem eles, a palavra de ativação fica desligada
  — a voz manual continua funcionando (sem fallback por volume).
- APK cresce ~32 MB (modelo Vosk ~45 MB compactado, baixado e verificado por SHA-256 no CI).
- Instrumentação de bateria: `wakeDetections`, `voskCommands`, `voskLoadMs`, `lastCommandMs`, `voskResident`,
  `kwsConfigured`, `kwsUnavailableReason` no diagnóstico. Scripts: `scripts/battery-test.ps1` e
  `scripts/perfetto-ultron.cfg`.
- Testes físicos: `docs/PHYSICAL_TEST_PROTOCOL.md` (12 cenários) + `scripts/physical-test.ps1`.
- Removido: `UltronWakeWordRecognizer.kt` (caminho antigo via SpeechRecognizer).

## 1.2.1+14

- Auditoria de confiabilidade da wake word (Fase 2): `captureHealthy`, watchdog de 8 falhas, half-duplex,
  diagnóstico `dedicatedKws = false` e HUD com pendência explícita.
