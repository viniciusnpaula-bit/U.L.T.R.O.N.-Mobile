# U.L.T.R.O.N. Mobile — Regras Permanentes do Projeto

## Microfone e Reconhecimento de Voz (Regra Obrigatória)
- **NUNCA** usar o microfone/serviço de reconhecimento de voz do **Google** (`android.speech.SpeechRecognizer`, `android.speech.RecognizerIntent`, diálogo/popup de voz do Google ou pacote Google Speech).
- **SEMPRE** capturar áudio exclusivamente pelo **microfone nativo do aparelho** (`AudioRecord` em `AudioCaptureHandler.kt` / `AudioCaptureSource`) ou por outro provedor/aplicativo **não-Google** configurável pelo usuário (ex.: `GroqWhisperSttService` / endpoint Whisper compatível e motor KWS offline `sherpa-onnx` em `UltronAudioService.kt`).

## Ambiente Windows / Testes Locais
- Ao rodar comandos `flutter` / `dart` no Windows com disco `C:` cheio, redirecionar `TEMP` e `TMP` para `D:\downloads\tmp`.
