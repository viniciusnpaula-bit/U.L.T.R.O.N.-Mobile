# sherpa-onnx Keyword Spotting

O sentinela de wake word usa o sherpa-onnx Zipformer KWS no Android. A detecção é executada localmente em CPU e não envia áudio para Groq, Mistral ou serviços remotos.

## Modelo e palavra de ativação

- Runtime Kotlin/Android: sherpa-onnx v1.13.8 (com.github.k2-fsa:sherpa-onnx via JitPack), projeto sob Apache-2.0.
- Licença do modelo: a documentação oficial do KWS não apresenta uma licença explícita para o pacote GigaSpeech. Não inferir a licença do modelo a partir da licença do runtime; confirmar os termos específicos antes de distribuir publicamente ou usar comercialmente.
- Modelo: sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01, publicado no release oficial kws-models do projeto sherpa-onnx.
- Entrada: PCM16 mono, 16 kHz.
- Palavra: ULTRON, convertida para tokens SentencePiece BPE durante a preparação dos assets.
- Execução: CPU, 2 threads; sem chave de API e sem rede durante a escuta.

O modelo acústico GigaSpeech é treinado principalmente para inglês. A palavra personalizada pode ser especificada por BPE, mas a pronúncia portuguesa de “Ultron” ainda precisa de validação em aparelho real; não se deve considerar o reconhecimento validado apenas porque o APK compila.

## Preparar assets

Após gerar/recuperar a plataforma Android com Flutter, execute:

    bash scripts/prepare_sherpa_kws.sh

O script adiciona JitPack ao bloco de repositórios do android/settings.gradle, baixa o pacote oficial do modelo, mantém apenas encoder/decoder/joiner/tokens/BPE, gera keywords.txt para ULTRON e coloca os assets no diretório Android que será empacotado no APK.

O modelo é gerado no build e ignorado pelo Git para evitar armazenar binários pesados no repositório. Os workflows CI e Android Release executam essa preparação antes da compilação.

## Ciclo de áudio

O serviço alimenta o KeywordSpotter com frames de 100 ms. Ao detectar a palavra, fecha o stream e libera AudioRecord antes de enviar onWakeWordDetected ao Flutter. O guard anti-eco impede que a captura reabra durante a transferência para o reconhecimento de comando, durante o TTS e durante a janela de proteção após a fala.

A leitura de amostras zeradas existe somente como diagnóstico de microfone silenciado; não participa da detecção de palavra.

## Diagnóstico

O painel recebe motor KWS, estado de carregamento do modelo, captura real, detecções, falhas de inicialização/execução do KWS, último erro e permissão do microfone.

Falsos acionamentos acústicos não podem ser quantificados automaticamente sem protocolo de rotulagem/feedback; por isso o relatório informa que essa métrica não está disponível em vez de inventar um número.

## Referências

- https://k2-fsa.github.io/sherpa/onnx/kws/index.html
- https://k2-fsa.github.io/sherpa/onnx/kws/pretrained_models/index.html
- https://github.com/k2-fsa/sherpa-onnx/releases/tag/kws-models
- https://github.com/k2-fsa/sherpa-onnx/releases/tag/v1.13.8
