# Prompt Pronto para o U.L.T.R.O.N. Desktop — Skill **Permutação do Fone** (`permutacao_do_fone`)

Copie e cole o bloco abaixo na IA/sessão do repositório **U.L.T.R.O.N. Desktop**:

---

```markdown
Implemente no U.L.T.R.O.N. Desktop (Windows) a skill **Permutação do Fone** (`permutacao_do_fone`), integrada via ponte LAN HMAC-SHA256 com o U.L.T.R.O.N. Mobile para o headset dual-mode **Attack Shark L30 Pro** (Dongle 2.4GHz USB ⇄ Bluetooth) com continuidade de música no **Spotify Connect** (mesma conta).

### Requisitos Funcionais

1. **Identificador e Catálogo de Skills**
   - ID/slug: `permutacao_do_fone`
   - Título: `Permutação do Fone`
   - Descrição: `Desconecta/reconecta o dongle USB 2.4GHz do Attack Shark L30 Pro no Windows e coordena o handoff com o celular + Spotify Connect.`
   - Expor esta skill no endpoint/handler de `PC_LIST_SKILLS` e executá-la em `PC_RUN_SKILL` (aceitando `args.direction` = `"to_mobile"` | `"to_desktop"` | `"auto"`, padrão `"auto"`, e `args.headset` = `"Attack Shark L30 Pro"`).

2. **Gatilhos por Voz / Linguagem Natural no Desktop**
   - Ativar a skill quando o usuário falar/digitar:
     - `"Permute a conexão do fone"` / `"Troque a conexão do fone"`
     - `"Permutar a conexão do fone"` / `"Trocar a conexão do fone"`
     - `"Permutação do fone"` (com ou sem destino `"pro celular"` / `"pro pc"`).

3. **Controle do Dongle USB 2.4GHz no Windows (Attack Shark L30 Pro)**
   - Criar helper em Python/PowerShell para localizar o dispositivo USB/áudio do dongle por padrão configurável (ex.: `HEADSET_DONGLE_MATCH` com fallback `"Attack Shark"`, `"L30"`, `"2.4G"`, `"Wireless Gaming Headset"`):
     - Listar via `Get-PnpDevice` (classes `MEDIA`, `AudioEndpoint`, `HIDClass`, `USB`) e salvar o `InstanceId` encontrado em config local para próximas execuções instantâneas.
   - **Modo `to_mobile` (PC Dongle → Celular Bluetooth):**
     1. Desabilitar o dispositivo do dongle via `pnputil /disable-device "<InstanceId>"` (ou PowerShell `Disable-PnpDevice -InstanceId "<InstanceId>" -Confirm:$false`; se não houver privilégio de administrador, usar fallback trocando o dispositivo de reprodução padrão do Windows para os alto-falantes/monitor e mutando o endpoint do fone, retornando aviso claro).
     2. Se a skill foi iniciada **no Desktop** (não recebida via `PC_RUN_SKILL` do celular):
        - Enfileirar comando reverso assinado (HMAC-SHA256) para o Mobile:
          ```json
          {
            "command": "RUN_SKILL",
            "args": {
              "skill": "permutacao_do_fone",
              "direction": "to_mobile",
              "headset": "Attack Shark L30 Pro"
            }
          }
          ```
          (ou diretamente `"command": "HEADSET_HANDOFF"` com os mesmos `args` — o Mobile já suporta ambos e não entra em loop).
        - Avisar por voz no PC: *"Dongle desconectado. Dê dois cliques no botão Power do fone para ativar o Bluetooth; o celular continuará o Spotify automaticamente."*
     3. Retornar resposta HTTP 200 JSON:
        ```json
        {
          "ok": true,
          "data": {
            "skill": "permutacao_do_fone",
            "direction": "to_mobile",
            "dongle_disabled": true,
            "instance_id": "<InstanceId>",
            "message": "Dongle 2.4GHz desconectado. Aguardando Bluetooth no celular."
          }
        }
        ```
   - **Modo `to_desktop` (Celular Bluetooth → PC Dongle):**
     1. Reabilitar o dispositivo do dongle via `pnputil /enable-device "<InstanceId>"` (ou `Enable-PnpDevice -InstanceId "<InstanceId>" -Confirm:$false`).
     2. Aguardar ~1.5s e definir o headset como saída de áudio padrão do Windows (se aplicável).
     3. Retornar `{ "ok": true, "data": { "skill": "permutacao_do_fone", "direction": "to_desktop", "dongle_enabled": true } }`.
   - **Modo `auto` (quando chamado sem direção):**
     - Se o dongle estiver habilitado (`Status == 'OK'`), executar `to_mobile`.
     - Se o dongle estiver desabilitado, executar `to_desktop`.

4. **Prevenção de Loop e Segurança**
   - Se o comando chegou via `PC_RUN_SKILL` vindo do Mobile, **NÃO** enviar `RUN_SKILL` de volta ao Mobile (apenas desabilitar/habilitar o dongle e responder JSON 200).
   - Manter validação obrigatória de `X-Ultron-Signature` (HMAC-SHA256), `X-Ultron-Timestamp` e `X-Ultron-Nonce` na ponte LAN.
   - Escrever testes unitários mockando `subprocess.run` (pnputil/PowerShell) e a fila reversa da ponte LAN cobrindo `to_mobile`, `to_desktop`, `auto` e prevenção de loop.
```
