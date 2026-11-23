# Contrato de Ponte Desktop — Self-Evolving Mini-Apps (`create_mini_app`)

Este documento define o contrato de integração entre o **U.L.T.R.O.N. Mobile** (`PC_EXEC_TOOL`) e o agente **U.L.T.R.O.N. Desktop** para geração e hospedagem temporária de Mini-Apps locais (HTML/JS ou Python) na rede local (LAN) ou Tailscale.

## 1. Requisitos de Segurança Obrigatórios
- **Assinatura:** Requisição autenticada via `HMAC-SHA256` + `timestamp` + `nonce` da ponte LAN (`DesktopPairingService`).
- **Action Gate (Mobile):** `create_mini_app` está classificado em `_highRiskDesktopTools` (`RiskLevel.critical`), exigindo `AccessLevel.sovereign` (Biometria) **e confirmação explícita do operador** antes do envio.
- **Sandbox (Desktop):**
  - Gravar arquivos exclusivamente em um diretório temporário isolado por execução (ex.: `<temp>/ultron_miniapp_<uuid>/`), sem path traversal.
  - Subir servidor HTTP em **porta efêmera** (`port=0`) vinculada **somente** à interface LAN privada (`192.168.x.x` / `10.x.x.x` / `172.16-31.x.x`) ou Tailscale (`100.64.0.0/10`), nunca em IP público.
  - Exigir **token efêmero de sessão** (>= 16 bytes aleatórios via `secrets.token_urlsafe(18)`) via query `?token=...` ou cookie/header.
  - Aplicar **TTL de auto-encerramento** (`60..3600s`, padrão `900s`): encerrar o processo/servidor e limpar o diretório temporário ao expirar.
- **Validação de Retorno (Mobile):** `MiniAppLaunchResponse.tryParse()` rejeita qualquer URL fora de LAN/Tailscale, sem porta explícita ou sem token de sessão válido.

## 2. Payload Enviado pelo Mobile (`PC_EXEC_TOOL`)

```json
{
  "command": "PC_EXEC_TOOL",
  "args": {
    "tool": "create_mini_app",
    "params": {
      "title": "Calculadora de Resistor LED",
      "runtime": "html",
      "spec": "Calculadora interativa para resistor limitador de LED com curva de potência",
      "source_code": "<!doctype html>...",
      "ttl_seconds": 900,
      "bind_scope": "lan_or_tailscale",
      "sandboxed": true,
      "ephemeral_port": true,
      "require_session_token": true
    }
  }
}
```

## 3. Resposta Esperada do Desktop (HTTP 200)

```json
{
  "ok": true,
  "data": {
    "sandbox_id": "miniapp_8f31c2a9",
    "url": "http://192.168.1.42:54123/?token=AbCdEfGhIjKlMnOpQrSt",
    "session_token": "AbCdEfGhIjKlMnOpQrSt",
    "ttl_seconds": 900,
    "expires_at": "2026-11-23T18:30:00Z"
  }
}
```

## 4. Handler de Referência no U.L.T.R.O.N. Desktop (Python)

```python
import http.server
import secrets
import shutil
import socketserver
import tempfile
import threading
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import parse_qs, urlparse


def handle_create_mini_app(params: dict, lan_ip: str) -> dict:
    ttl = max(60, min(3600, int(params.get("ttl_seconds", 900))))
    token = secrets.token_urlsafe(18)
    sandbox_dir = Path(tempfile.mkdtemp(prefix="ultron_miniapp_"))
    html_code = params.get("source_code") or f"<h1>{params.get('title', 'Mini-App')}</h1>"
    (sandbox_dir / "index.html").write_text(html_code, encoding="utf-8")

    class TokenGuardedHandler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(sandbox_dir), **kwargs)

        def do_GET(self):
            qs = parse_qs(urlparse(self.path).query)
            if qs.get("token", [""])[0] != token:
                self.send_error(403, "Invalid or missing session token")
                return
            super().do_GET()

    server = socketserver.TCPServer((lan_ip, 0), TokenGuardedHandler)
    port = server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()

    def _cleanup():
        time.sleep(ttl)
        server.shutdown()
        server.server_close()
        shutil.rmtree(sandbox_dir, ignore_errors=True)

    threading.Thread(target=_cleanup, daemon=True).start()
    expires = (datetime.now(timezone.utc) + timedelta(seconds=ttl)).isoformat()
    return {
        "ok": True,
        "data": {
            "sandbox_id": sandbox_dir.name,
            "url": f"http://{lan_ip}:{port}/?token={token}",
            "session_token": token,
            "ttl_seconds": ttl,
            "expires_at": expires,
        },
    }
```
