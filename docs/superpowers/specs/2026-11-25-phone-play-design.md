# Phone play: one command, works on iOS and Android

## Intent

`python3 tools/web/play_in_browser.py` plays the game in the desktop browser today.
The owner wants the same one-command flow on a phone, both iPhone and Android, with
the microphone working (the speech challenge is the game).

## Why the current `--phone` flag falls short

`play_in_browser.py --phone` already delegates to `build/serve_https.py`, which binds
`0.0.0.0` and prints the LAN URL. Three things stop it being usable on a phone:

1. `build/web-certs/cert.pem` is `CN=localhost` with **no Subject Alternative Name**.
   A phone opens `https://<lan-ip>:8443/`, which the certificate does not name. iOS
   Safari treats a SAN-less certificate as a hard failure and often offers no
   "proceed" at all.
2. Nothing checks that the LAN URL answers, and the macOS firewall can silently block
   incoming connections to Python.
3. No guidance for trusting the certificate, so the mic prompt is a coin flip.

## Goals

- `python3 tools/web/play_in_browser.py --phone` works on iPhone and Android with no
  extra flags.
- The certificate names the addresses the phone actually uses.
- The terminal prints exactly what to do on each platform.
- The phone can download the certificate from the same server.

## Non-goals

- No dependency on `mkcert`, Homebrew, or `pip install`.
- No changes to the desktop flow (`http://localhost:8060`), the game code, or the
  committed `build/web-certs/` certificate.
- No automatic firewall reconfiguration (that needs admin rights and user consent).

## Approach

Change `build/serve_https.py` only; `play_in_browser.py` already hands over to it.

- Generate a self-signed certificate into `build/phone-certs/` (gitignored) with
  SANs for `localhost`, `127.0.0.1`, `<mac-name>.local`, and every current LAN IPv4.
  Regenerate only when the existing one no longer covers the current addresses or has
  expired.
- Serve the certificate at `/cert.crt` so the phone can install it as a trusted root.
- Self-test the LAN URL after boot and report firewall state with the fix.
- Print per-platform steps for iOS and Android.
- Serve with `ThreadingHTTPServer` so the WASM/PCK requests do not queue.

## Calls made

- `build/phone-certs/` rather than reusing `build/web-certs/`: keeps the committed
  desktop certificate untouched and avoids dirtying git on every LAN change.
- One self-signed root with `CA:TRUE` used as the server certificate: the only shape
  both iOS and Android will install as a trusted root without extra tooling.
- No QR code: it needs a dependency, and the printed URL is short enough to type.
