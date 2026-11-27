# Contrato Bidirecional de Skills (Celular ⇄ U.L.T.R.O.N. Desktop)

Este documento descreve os contratos HMAC-SHA256 da ponte LAN/Tailscale para ativar skills do PC pelo celular e skills do celular (`Skills/*.md`) pelo PC.

## 1. Celular → PC (`/api/mobile/command`)

Todas as requisições saem assinadas com `X-Ultron-Device`, `X-Ultron-Timestamp`, `X-Ultron-Nonce` e `X-Ultron-Signature`.

### 1.1 Listar Skills do PC (`PC_LIST_SKILLS`)
```json
{
  "device_id": "galaxy-a34",
  "command": "PC_LIST_SKILLS",
  "args": {},
  "timestamp": "1700000000000",
  "nonce": "..."
}
```
Resposta esperada (HTTP 200):
```json
{
  "ok": true,
  "data": {
    "skills": [
      {
        "id": "modo_trabalho",
        "title": "Modo Trabalho",
        "description": "Abre VS Code, Docker e terminal"
      }
    ]
  }
}
```
*(Fallback automático: se o Desktop retornar 404/501 para `PC_LIST_SKILLS`, o Mobile tenta `PC_EXEC_TOOL` com `{"tool": "listar_skills"}`.)*

### 1.2 Executar Skill no PC (`PC_RUN_SKILL`)
```json
{
  "device_id": "galaxy-a34",
  "command": "PC_RUN_SKILL",
  "args": {
    "skill": "modo_trabalho",
    "args": "opcional"
  }
}
```

### 1.3 Sincronizar Catálogo do Celular para o PC (`PC_SYNC_MOBILE_SKILLS`)
```json
{
  "device_id": "galaxy-a34",
  "command": "PC_SYNC_MOBILE_SKILLS",
  "args": {
    "skills": [
      {
        "id": "modo_estudo",
        "slug": "modo_estudo",
        "title": "Modo Estudo (Pomodoro 25m)",
        "description": "Silencia áudio de mídia e inicia temporizador Pomodoro de 25 minutos.",
        "actionCount": 2,
        "riskLevel": "safe",
        "requiresConfirmation": false
      }
    ]
  }
}
```

## 2. PC → Celular (`/api/mobile/poll` + `/api/mobile/result`)

O `DesktopCommandListener` no Mobile (autenticado em `AccessLevel.sovereign` — Biometria Nível 3) aceita:

### 2.1 Descobrir Skills do Celular (`LIST_SKILLS` / `SKILLS` / `MOBILE_SKILLS`)
Envelope enviado pelo PC via long-poll:
```json
{
  "command_id": "cmd-skills-1",
  "device_id": "galaxy-a34",
  "command": "LIST_SKILLS",
  "args": {},
  "timestamp": "1700000000000",
  "nonce": "..."
}
```
O celular responde em `/api/mobile/result` com `data.skills` contendo `{id, slug, title, actions, riskLevel, requiresConfirmation}`.

### 2.2 Executar Skill do Celular pelo PC (`RUN_SKILL` / `SKILL` / `EXEC_SKILL` / `MOBILE_RUN_SKILL`)
```json
{
  "command_id": "cmd-run-1",
  "device_id": "galaxy-a34",
  "command": "RUN_SKILL",
  "args": {
    "skill": "modo_estudo"
  },
  "timestamp": "1700000000000",
  "nonce": "..."
}
```
- **Segurança (ActionGate fail-closed):** o celular inspeciona todas as tags `[ACTION:...]` / `[HTTP:...]` da skill antes de executar. Se houver qualquer ação `sensitive` ou `critical`, o envio exige confirmação explícita no celular; caso contrário, recusa com `status: "cancelled"` e grava no `AuditLogService`.
