# Protocolo de Testes Físicos — Motor KWS (v1.3.0+15)

**Execução:** pelo operador, em aparelho Android real com depuração USB. Não executável nesta revisão (sem aparelho conectado; sem `.ppn`/AccessKey para detecção real).

**Apoio:** `scripts/physical-test.ps1` (instala APK, limpa o logcat e acompanha a tag `UltronWake:V`); `scripts/battery-test.ps1` (medição de consumo).

**Pré-requisitos:** APK de build (debug ou release), app concedido com permissão de microfone, sentinela de voz ativada. O `.ppn` e a AccessKey precisam estar configurados no build para testar detecção real; sem eles, todos os cenários de "ativação" falham por design (sem fallback de volume).

Critério geral: cada cenário tem PASS/FAIL com base no que aparece no HUD/diagnóstico e na tag de log `UltronWake:V`.

---

### 1. App aberto
- Preparação: app em primeiro plano, sentinela ativo, HUD sem pendências.
- Passos: dizer "Ultron, que horas são".
- Observar: HUD/diagnóstico mudam para "Palavra detectada — ouvindo comando" e voltam.
- Aceite: comando executado, `wakeDetections` +1 e `voskCommands` +1 no diagnóstico.

### 2. App em segundo plano
- Preparação: app aberto, sessão de captura ativa; minimizar o app (não swipe dos recentes).
- Passos: dizer "Ultron, toque a lanterna".
- Observar: notificação de ativação ("U.L.T.R.O.N. ouviu você") e comando executado ao reabrir.
- Aceite: comando executado; serviço continua vivo no diagnóstico (`running == true`).

### 3. Tela bloqueada
- Preparação: app em segundo plano, tela desligada.
- Passos: aguardar 30 s; dizer "Ultron, que horas são".
- Observar: notificação full-screen de ativação (se disponível no Android); comando executado ao desbloquear.
- Aceite: notificação de ativação aparece; comando executado.

### 4. Swipe dos recentes (app removido dos recentes)
- Preparação: app executando em segundo plano.
- Passos: abrir o switcher de apps e remover o U.L.T.R.O.N. dos recentes.
- Observar: serviço de primeiro plano continua (notificação permanente mantida); dizer "Ultron, que horas são".
- Aceite: serviço não morreu (`onTaskRemoved` não encerra); comando executado.

### 5. Chamada em curso
- Preparação: segunda linha ligando para o aparelho.
- Passos: atender a chamada; durante a chamada, dizer "Ultron, ...".
- Observar: nada acontece (half-duplex: ligação ocupa o microfone).
- Aceite: nenhum gatilho durante a chamada; após desligar, a captura retoma normalmente e um novo "Ultron" funciona.

### 6. Flip-to-shush (aparelho virado com a tela para baixo)
- Preparação: app em primeiro plano, sentinela ativo.
- Passos: virar o aparelho com a tela para baixo; dizer "Ultron, que horas são".
- Observar: nenhum gatilho (Microfone liberado pelo Flip-to-Shush).
- Aceite: nenhum log de gatilho no `UltronWake:V`; ao virar de volta, a detecção volta a funcionar.

### 7. TTS falando (eco do próprio Ultron)
- Preparação: app em primeiro plano; disparar qualquer resposta de voz do Ultron (TTS).
- Passos: enquanto o TTS fala, dizer "Ultron, pare" ou simplesmente "Ultron".
- Observar: nenhum gatilho próprio (half-duplex: microfone liberado enquanto o TTS fala).
- Aceite: nenhum log de detecção durante a fala do TTS; após o término, o próximo "Ultron" é detectado.

### 8. Bateria < 15% sem carregador
- Preparação: aparelho com bateria abaixo de 15% e desconectado do carregador.
- Passos: aguardar o modo economia entrar em ação; dizer "Ultron, que horas são".
- Observar: notificação "Bateria crítica — escuta em pausa"; nenhum gatilho.
- Aceite: captura pausada e motivo visível; ao conectar o carregador ou carregar acima de 15%, a captura retoma.

### 9. Reboot do aparelho
- Preparação: app configurado com boot automático (opt-in no diagnóstico).
- Passos: reiniciar o aparelho; aguardar o boot completar; não abrir o app.
- Observar: notificação de alta prioridade publicada pelo BootReceiver convidando o usuário a reativar.
- Aceite: após o toque na notificação, o serviço inicia e a detecção funciona (se bootAutostart não estiver ativo, a falha é esperada — o app não inicia microfone em background sozinho).

### 10. Headset Bluetooth
- Preparação: fone de ouvido Bluetooth emparelhado e conectado.
- Passos: dizer "Ultron, que horas são" pelo microfone do headset.
- Observar: áudio capturado pela fonte `VOICE_RECOGNITION` (bluetooth quando disponível).
- Aceite: detecção funciona com o headset; comando executado.

### 11. Ruído de TV/fundo contínuo
- Preparação: TV ou rádio ligado ao fundo (fala contínua, música).
- Passos: deixar rodar por 5 min sem dizer nada.
- Observar: nenhum gatilho do Porcupine (sem "Ultron" dito).
- Aceite: zero ativações; `wakeDetections` não muda; sem notificações de "Palavra detectada".

### 12. Comando na mesma respiração
- Preparação: app em primeiro plano, microfone livre.
- Passos: dizer "Ultron que horas são" em uma única fôlego, sem pausa entre a palavra e o comando.
- Observar: o início do comando ("que horas são") está no anel de pré-roll de 1,5 s.
- Aceite: comando executado corretamente (início não cortado); `voskCommands` +1.

---

### Registro de execução

Para cada cenário, anote: data, versão do APK (1.3.0+15), modelo do aparelho, Android API, resultado (PASS/FAIL) e evidência (trecho do logcat `UltronWake:V` e tela do diagnóstico).

Colete ao final:
```
adb logcat -d -s UltronWake:V > logcat-ultronwake.txt
adb shell dumpsys batterystats com.viniciusnpaula.ultron_mobile > batterystats-final.txt
```
