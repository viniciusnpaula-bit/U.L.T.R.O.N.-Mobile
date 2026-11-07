# Protocolo de validação da wake word "Ultron" (pt-BR)

Este protocolo existe porque a detecção **não pode ser validada sem áudio real em português brasileiro**. Emulador não serve: o microfone não representa um aparelho de verdade.

Nenhum resultado de precisão deve ser publicado antes da execução completa.

## Amostras necessárias (fornecidas pelo operador)

Formato: WAV, PCM16, mono, 16 kHz. Não enviar áudio para servidores externos nem commitar gravações no repositório.

| Arquivo | Conteúdo |
|---|---|
| `ultron_natural.wav` | "Ultron" com pronúncia natural |
| `ultron_rapido.wav` | fala rápida |
| `ultron_devagar.wav` | fala lenta |
| `ultron_baixo.wav` | volume baixo |
| `ultron_distante.wav` | a 1–2 m do aparelho |
| `ruido_fundo.wav` | "Ultron" com TV/rádio ao fundo |
| `palavras_semelhantes.wav` | "ultra", "outro", "elétron", "ultrassom" |
| `comando.wav` | "Ultron, que horas são" |

Sem esses arquivos, a execução fica bloqueada e o estado é **"não validado em aparelho físico"**.

## Como executar

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb logcat -c
adb logcat -s UltronWake:V
```

1. Abrir o app, conceder permissão de microfone e ativar o sentinela.
2. Confirmar no diagnóstico: `modelLoaded = true`, `dedicatedKws = true`, `capturing = true`.
3. Reproduzir cada WAV perto do microfone (ou falar as frases) e anotar os contadores antes/depois.
4. Repetir com a tela bloqueada e com o app em segundo plano.

## Cenários

| # | Cenário | Esperado |
|---|---|---|
| R1 | "Ultron" natural | ativação; `detections` +1 |
| R2 | "Ultron" rápido | ativação |
| R3 | "Ultron" lento | ativação |
| R4 | "Ultron" baixo | ativação |
| R5 | "Ultron" a 2 m | ativação |
| R6 | "Ultron" com ruído | ativação ou falso negativo anotado |
| R7 | Palavras semelhantes | nenhuma ativação |
| R8 | "Ultron, que horas são" | ativação + comando transcrito |
| R9 | Tela bloqueada | ativação e notificação |
| R10 | App em segundo plano | ativação |
| R11 | TTS falando | não ativar (anti-eco) |
| R12 | Bateria < 15% | pausa documentada, sem ativação falsa |

## Interpretação das métricas

| Observação | Conclusão |
|---|---|
| `kwsFrames = 0` | áudio não chegou ao KWS: captura, pausa ou inicialização |
| `kwsFrames` cresce, `kwsDecodes = 0` | stream não ficou pronto para decode |
| `kwsDecodes` cresce, `detections = 0` | áudio chegou ao modelo e a palavra não foi reconhecida |
| `kwsErrors` cresce | falha de inicialização/execução do KWS |
| `micSilencedEvents` cresce | microfone silenciado pelo sistema |
| `paused = true` | serviço pausado; ver `lastError`/notificação |

## Critério de aceite

- Pipeline sem erros: `kwsFrames` e `kwsDecodes` crescendo, `kwsErrors = 0`.
- R1–R5 com ativação consistente (mínimo 4 de 5 execuções por cenário; registrar o número real).
- R7 sem ativação.
- Nenhuma regressão nos recursos existentes.
- Resultado e amostras anotados na PR; se falhar, anexar os WAV que falharam.

## O que continua sem resposta até lá

- Taxa de acerto, falso positivo e falso negativo.
- Se `UTRON` ajuda, atrapalha ou é indiferente.
- Latência e consumo de bateria em uso contínuo.
