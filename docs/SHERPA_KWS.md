# sherpa-onnx Keyword Spotting

O sentinela de wake word usa o sherpa-onnx Zipformer KWS no Android. A detecção é executada localmente em CPU e não envia áudio para Groq, Mistral ou serviços remotos.

## Modelo e palavra de ativação

- Runtime Kotlin/Android: sherpa-onnx v1.13.8, AAR oficial do release Android (Kotlin API + JNI), projeto sob Apache-2.0.
- Licença do modelo: a documentação oficial do KWS não apresenta uma licença explícita para o pacote GigaSpeech. Não inferir a licença do modelo a partir da licença do runtime; confirmar os termos específicos antes de distribuir publicamente ou usar comercialmente.
- Modelo: sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01, publicado no release oficial kws-models do projeto sherpa-onnx.
- Entrada: PCM16 mono, 16 kHz.
- Palavras: `ULTRON` (forma escrita) e `UTRON` (pronúncia brasileira sem o L vocalizado).
- Execução: CPU, 2 threads; sem chave de API e sem rede durante a escuta.

### Evidência de tokenização (pt-BR)

Tokens gerados com o `bpe.model` deste modelo (SentencePiece 0.2.3):

```text
ULTRON -> ▁ UL T RO N   ids 20 182 4 89 9
UTRON  -> ▁ U T RO N    ids 20 28  4 89 9
```

Nenhum token cai em `<unk>` (id 2). `ULTRÃO` cai em `<unk>` e por isso não é usada. Ou seja, a conversão BPE é válida: o risco está no modelo acústico, que é treinado principalmente em inglês, não na tokenização.

A pronúncia brasileira /uˈtɾõ/ vocaliza o L antes de consoante. `UTRON` é a variante que representa essa pronúncia no BPE inglês; ela entra com boosting menor (1.0 contra 1.5) justamente por ser uma hipótese ainda não medida. Isso não garante detecção — só um teste em aparelho real decide.

## Preparar assets

Após gerar/recuperar a plataforma Android com Flutter, execute:

    bash scripts/prepare_sherpa_kws.sh

O script baixa o AAR oficial do runtime e o pacote oficial do modelo, valida o AAR, mantém apenas encoder/decoder/joiner/tokens/BPE, escreve o `keywords.txt` e coloca os arquivos nos diretórios Android que serão empacotados no APK.

O `keywords.txt` tem uma palavra por linha, no formato oficial do sherpa-onnx:

```text
▁ UL T RO N :1.5 #0.25
▁ U T RO N :1.0 #0.25
```

O script sempre reescreve o `keywords.txt`, inclusive quando o modelo já está em cache, e falha se algum token não existir no `tokens.txt` ou for `<unk>`. Tokens fixos valem para o modelo fixado; ao trocar `MODEL_NAME`, regenere-os com SentencePiece.

O modelo é gerado no build e ignorado pelo Git para evitar armazenar binários pesados no repositório. Os workflows CI e Android Release executam essa preparação antes da compilação.

## Ciclo de áudio

O serviço alimenta o KeywordSpotter com frames de 100 ms. Ao detectar a palavra, fecha o stream e libera AudioRecord antes de enviar onWakeWordDetected ao Flutter. O guard anti-eco impede que a captura reabra durante a transferência para o reconhecimento de comando, durante o TTS e durante a janela de proteção após a fala.

A leitura de amostras zeradas existe somente como diagnóstico de microfone silenciado; não participa da detecção de palavra.

## Diagnóstico

O painel recebe motor KWS, estado de carregamento do modelo, captura real, detecções, falhas de inicialização/execução do KWS, último erro e permissão do microfone.

Dois contadores separam "não capturou" de "capturou e o modelo não reconheceu":

- `kwsFrames`: janelas de áudio entregues ao decoder.
- `kwsDecodes`: execuções de decode do KWS.

Se `kwsFrames` cresce e `detections` fica em zero, o áudio chegou ao modelo e a palavra não foi reconhecida. Se `kwsFrames` não cresce, o problema é anterior (captura, pausa ou inicialização).

Falsos acionamentos acústicos não podem ser quantificados automaticamente sem protocolo de rotulagem/feedback; por isso o relatório informa que essa métrica não está disponível em vez de inventar um número.

## Alternativas avaliadas

| Alternativa | Evidência | Situação |
|---|---|---|
| sherpa-onnx com modelo GigaSpeech (atual) | Já integrado, offline, sem chave; BPE válido para ULTRON/UTRON | Mantido; precisa de validação em aparelho |
| sherpa-onnx com modelo zh-en | Releases oficiais `kws-models` só têm en, zh e zh+en | Não resolve pt-BR |
| Porcupine (Picovoice) | Suporte oficial a português, mas exige `ultron_pt.ppn` e AccessKey que não existem no repositório | Descartado sem teste comparativo |
| Vosk `vosk-model-small-pt-0.3` | `docs/WAKE_WORD_AUDIT.md` registra que "ultron" não está no vocabulário; sem gramática o áudio vira "outro" | Descartado sem recompilar léxico/grafo |
| KWS treinado sob medida | Exige dataset rotulado de pt-BR e treinamento | Fora do escopo desta correção |

Trocar de motor sem gravações comparativas violaria a regra de não substituir o sherpa-onnx sem justificativa técnica e testes. O caminho escolhido é reduzir a chance de erro de pronúncia com variantes e medir em aparelho real.

## Validação em aparelho físico

O protocolo e a lista de amostras necessárias estão em `docs/WAKE_WORD_TEST_PTBR.md`. Nenhuma taxa de acerto é afirmada até que esses testes sejam executados.

## Referências

- https://k2-fsa.github.io/sherpa/onnx/kws/index.html
- https://k2-fsa.github.io/sherpa/onnx/kws/pretrained_models/index.html
- https://github.com/k2-fsa/sherpa-onnx/releases/tag/kws-models
- https://github.com/k2-fsa/sherpa-onnx/releases/tag/v1.13.8
