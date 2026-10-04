# Playing Loqui Quest in Your Browser

The browser build uses the Web Speech API, which needs a **Secure Context** (HTTPS).
Serve the export with the included HTTPS script — the browser will warn about the
self-signed certificate; click through / continue anyway.

## Quick start (terminal)

Paste this one command (starts HTTPS and opens the local browser):

```bash
cd "/Users/JJ/Documents/WORK VSCODE/speaking_godot_game" && (sleep 1; open "https://127.0.0.1:8443/") & python3 build/serve_https.py
```

Accept the certificate warning, then play. Stop with `Ctrl+C`.

The server prints every URL you need. Current links (while this Mac is on the same Wi‑Fi):

| Device | URL |
|--------|-----|
| This Mac (local) | https://127.0.0.1:8443/ |
| Phone / tablet / other LAN device | https://192.168.50.33:8443/ |

If `192.168.50.33` stops working, your Mac’s Wi‑Fi IP changed — use the address printed by
`serve_https.py`, or check **System Settings → Network → Wi‑Fi → Details → IP Address**.

Do **not** use plain HTTP (e.g. `python3 -m http.server 8080`) if you need the mic —
speech will fail outside HTTPS / a true Secure Context.

## 1. Build the web export (if needed)

In Godot, export with the **"Web"** preset → writes to `build/web/`.
Skip this if `build/web/index.html` is already present.

## 2. HTTPS server details

```bash
python3 build/serve_https.py
```

Defaults:
- Listens on **all interfaces** (`0.0.0.0:8443`) so phones on the same Wi‑Fi can connect
- This Mac: **https://127.0.0.1:8443/**
- Phone / tablet: **https://`<LAN-IP>`:8443/** (printed at startup)
- Serves `build/web/`
- Certs: `build/web-certs/cert.pem` and `build/web-certs/key.pem`

Optional overrides:

```bash
PORT=9000 python3 build/serve_https.py
HOST=127.0.0.1 python3 build/serve_https.py   # local only (blocks phones)
```

If certs are missing, regenerate them once:

```bash
mkdir -p build/web-certs
openssl req -x509 -newkey rsa:2048 \
  -keyout build/web-certs/key.pem \
  -out build/web-certs/cert.pem \
  -days 365 -nodes -subj "/CN=localhost"
```

## 3. Open it in a browser

### Desktop (this Mac)
Open **https://127.0.0.1:8443/** in Chrome, Edge, Firefox, or Safari.
On the certificate warning: **Continue** / **Advanced → Proceed**.

### Phone / tablet / other devices (same Wi‑Fi)
When the server starts it prints something like:

```
On this Mac:  https://127.0.0.1:8443/
On your phone (same Wi‑Fi):
  https://192.168.x.x:8443/
```

On the phone or tablet, open that **https://192.168…:8443/** link in Chrome or Safari.
Accept the self-signed certificate warning, then allow the microphone when asked.

Notes:
- Phone/tablet and Mac must share the **same Wi‑Fi** (router client isolation off).
- Allow **Python incoming connections** if macOS asks.
- This is **LAN only** — not a public internet URL. For a public link you’d need a tunnel
  (e.g. cloudflared); that is separate from `serve_https.py`.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Missing web build folder: build/web` | Export the Godot **"Web"** preset first. |
| `Missing certs` | Run the `openssl` command above (or restore committed `build/web-certs/`). |
| Connection refused | Server not running, or firewall blocking the port. |
| Mic doesn’t work | Must be on HTTPS (`serve_https.py`); grant mic permission. |
| Can’t reach from phone | Same Wi‑Fi; allow Python incoming connections; use the printed LAN URL (not 127.0.0.1). |
