# Keyword do Porcupine

Coloque aqui `ultron_pt.ppn`, treinado no Picovoice Console:

1. https://console.picovoice.ai/ → Porcupine → Create Wake Word
2. Idioma: Portuguese. Frase: `ultron`.
3. Plataforma: Android. Baixe o `.ppn` e salve com este nome exato:

```
android/app/src/main/assets/porcupine/ultron_pt.ppn
```

Sem este arquivo o app compila e reporta "KWS não configurado"; a palavra de
ativação fica desligada (a voz manual continua funcionando).
