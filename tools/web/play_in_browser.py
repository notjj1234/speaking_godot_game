#!/usr/bin/env python3
"""play_in_browser.py — export the Web build and play it in your local browser.

    python3 tools/web/play_in_browser.py              # export, then serve http://localhost:8060 and open it
    python3 tools/web/play_in_browser.py --no-export  # just serve the last export (build/web/)
    python3 tools/web/play_in_browser.py --export-only
    python3 tools/web/play_in_browser.py --phone      # export, then serve over HTTPS on your Wi-Fi
                                                      # for a phone or tablet: it prints the phone URL,
                                                      # firewall hint, and the certificate-trust steps
                                                      # for iOS and Android (build/serve_https.py)

Why localhost: browsers only allow the microphone (Web Speech API) in a
"secure context". http://localhost counts as one, so desktop testing needs no
certificate. A phone on your Wi-Fi reaches the Mac by IP, which is not
localhost, so --phone hands over to the existing HTTPS server instead.

Windows: run `py tools\\web\\play_in_browser.py` (or `python ...`), or double-click
tools\\web\\play_in_browser.cmd. `python3` on Windows is often the Microsoft Store stub.

Godot is found in this order: $GODOT, then on macOS ~/Downloads/Godot.app,
/Applications/Godot*.app, ~/Applications/Godot*.app; on Windows
Godot_v4.7*_win64[_console].exe in Downloads, Desktop, Documents, Program Files,
%LOCALAPPDATA%\\Programs, scoop or Steam; then `godot` / `godot4` on PATH. The
first 4.7.x found wins. It must be 4.7.x (the
project's version) with the 4.7 web export templates installed
(Editor > Manage Export Templates). The "Web" preset in export_presets.cfg
writes build/web/index.html; the build is single-threaded, so it needs no
special server headers and runs on any static server.

Press Ctrl+C to stop the server.
"""
from __future__ import annotations

import glob
import http.server
import os
import re
import shutil
import socketserver
import subprocess
import sys
import threading
import urllib.parse
import webbrowser

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WEB_DIR = os.path.join(ROOT, "build", "web")
EXTRAS_DIR = os.path.realpath(os.path.join(ROOT, "web", "extras"))
PRESET = "Web"
PORT = int(os.environ.get("PORT", "8060"))
WANT_MAJOR_MINOR = "4.7"


def _windows_candidates(home: str) -> list[str]:
    """Godot_v4.x-stable_win64[_console].exe in the usual places, best first.

    The _console build is preferred: the plain .exe detaches from the terminal,
    so the headless import/export prints nothing and is hard to debug.
    """
    dirs = [os.path.join(home, d) for d in ("Downloads", "Desktop", "Documents", "Godot", "Apps")]
    for env in ("ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA"):
        base = os.environ.get(env)
        if base:
            dirs += [base, os.path.join(base, "Godot"), os.path.join(base, "Programs", "Godot")]
    dirs += [os.path.join(home, "scoop", "apps", "godot", "current"),
             r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine"]
    found = []
    for d in dirs:
        found += glob.glob(os.path.join(d, "Godot*.exe")) + glob.glob(os.path.join(d, "Godot*", "Godot*.exe"))

    def rank(path: str):
        name = os.path.basename(path).lower()
        nums = tuple(int(n) for n in re.findall(r"v(\d+(?:\.\d+)*)", name)[0].split(".")) \
            if re.search(r"v\d", name) else ()
        return (name.startswith(f"godot_v{WANT_MAJOR_MINOR}"), nums, "_console" in name)

    return sorted(dict.fromkeys(found), key=rank, reverse=True)


def find_godot() -> str | None:
    cands = []
    if os.environ.get("GODOT"):
        cands.append(os.environ["GODOT"])
    home = os.path.expanduser("~")
    if os.name == "nt":
        cands += _windows_candidates(home)
    else:
        for app in [os.path.join(home, "Downloads", "Godot.app")] + sorted(glob.glob("/Applications/Godot*.app")) \
                + sorted(glob.glob(os.path.join(home, "Applications", "Godot*.app"))):
            cands.append(os.path.join(app, "Contents", "MacOS", "Godot"))
    for name in ("godot", "godot4", "godot_console"):
        p = shutil.which(name)
        if p:
            cands.append(p)
    usable = [c for c in dict.fromkeys(cands) if os.path.isfile(c) and os.access(c, os.X_OK)]
    if os.environ.get("GODOT") and usable and usable[0] == os.environ["GODOT"]:
        return usable[0]  # an explicit choice wins; export() still checks its version
    # Several editors may be installed (e.g. 4.4 and 4.7): pick the first 4.7.x.
    for c in usable:
        if godot_version(c).startswith(WANT_MAJOR_MINOR):
            return c
    return usable[0] if usable else None


def godot_version(godot: str) -> str:
    try:
        out = subprocess.run([godot, "--version"], capture_output=True, text=True, timeout=60)
        return (out.stdout.strip().splitlines() or [""])[-1]
    except (OSError, subprocess.TimeoutExpired):
        return ""


def templates_dir(ver: str) -> str | None:
    """Where Godot keeps export templates for `ver` ("4.7.1.stable.official.x" -> ".../4.7.1.stable")."""
    m = re.match(r"(\d+\.\d+(?:\.\d+)?\.[a-z0-9]+)", ver)
    if not m:
        return None
    if os.name == "nt":
        base = os.path.join(os.environ.get("APPDATA", ""), "Godot")
    elif sys.platform == "darwin":
        base = os.path.expanduser("~/Library/Application Support/Godot")
    else:
        base = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "godot")
    return os.path.join(base, "export_templates", m.group(1))


def export(godot: str) -> bool:
    ver = godot_version(godot)
    print(f"Godot: {godot}\nVersion: {ver or 'unknown'}")
    if not ver.startswith(WANT_MAJOR_MINOR):
        print(f"❌ This project is Godot {WANT_MAJOR_MINOR}; exporting with another version can break it.\n"
              f"   Point GODOT at a {WANT_MAJOR_MINOR}.x editor binary and run again.")
        return False
    if not os.path.isfile(os.path.join(ROOT, "export_presets.cfg")):
        print("❌ export_presets.cfg is missing (it is gitignored, so a fresh clone has none).\n"
              "   Open the project in Godot, Project > Export > Add… > Web, name it 'Web', and save.")
        return False
    tdir = templates_dir(ver)
    if tdir and not os.path.isfile(os.path.join(tdir, "web_nothreads_release.zip")):
        print(f"❌ Godot {ver.split('.official')[0]} web export templates are not installed\n"
              f"   (looked in {tdir}).\n"
              "   Open this Godot editor > Editor > Manage Export Templates > Download and Install, then run again.")
        return False
    os.makedirs(WEB_DIR, exist_ok=True)
    print("⏳ Importing assets (first run can take a minute)…")
    subprocess.run([godot, "--headless", "--path", ROOT, "--import"], timeout=1800)
    print(f"⏳ Exporting the '{PRESET}' preset to build/web/ …")
    res = subprocess.run([godot, "--headless", "--path", ROOT, "--export-release", PRESET,
                          os.path.join(WEB_DIR, "index.html")], timeout=1800)
    need = ["index.html", "index.js", "index.wasm", "index.pck"]
    missing = [f for f in need if not os.path.isfile(os.path.join(WEB_DIR, f))]
    if res.returncode != 0 or missing:
        print(f"❌ Export failed (exit {res.returncode}{', missing ' + ', '.join(missing) if missing else ''}).\n"
              "   Check that the 4.7 Web export templates are installed (Editor > Manage Export Templates).")
        return False
    print("✅ Web build ready in build/web/")
    return True


class _Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm", ".js": "text/javascript", ".pck": "application/octet-stream"}

    def __init__(self, *a, **kw):
        super().__init__(*a, directory=WEB_DIR, **kw)

    def translate_path(self, path):
        # The web shell imports /extras/pronunciation/window_lqpron.js (the
        # pronunciation scorer), which lives outside the export, as in
        # build/serve_https.py. Escapes from the mount map to a missing file.
        clean = path.split("?", 1)[0].split("#", 1)[0]
        if clean.startswith("/extras/"):
            rel = urllib.parse.unquote(clean[len("/extras/"):]).lstrip("/")
            full = os.path.realpath(os.path.join(EXTRAS_DIR, rel))
            if os.path.commonpath([EXTRAS_DIR, full]) != EXTRAS_DIR:
                return os.path.join(EXTRAS_DIR, "__outside_mount__")
            return full
        return super().translate_path(path)

    def end_headers(self):
        # Always load the newest export after re-exporting.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        pass


def serve_local(open_browser: bool) -> int:
    if not os.path.isfile(os.path.join(WEB_DIR, "index.html")):
        print("❌ No web build in build/web/ yet — run without --no-export first.")
        return 1
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("127.0.0.1", PORT), _Handler) as httpd:
        url = f"http://localhost:{PORT}/"
        print(f"\n🎮 Play at: {url}\n   (microphone works here: localhost is a secure context)\n   Ctrl+C to stop.")
        if open_browser:
            threading.Timer(0.8, lambda: webbrowser.open(url)).start()
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nStopped.")
    return 0


def main() -> int:
    # Windows consoles/pipes may default to cp1252, which can't print the emoji logs.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    args = set(sys.argv[1:])
    if "--no-export" not in args:
        godot = find_godot()
        if not godot:
            if os.name == "nt":
                print("❌ Godot 4.7 not found. Set GODOT to the editor exe, e.g.\n"
                      "   $env:GODOT = \"C:\\path\\to\\Godot_v4.7.1-stable_win64_console.exe\"")
            else:
                print("❌ Godot 4.7 not found. Set GODOT=/path/to/Godot (the binary inside Godot.app/Contents/MacOS/).")
            return 1
        if not export(godot):
            return 1
    if "--export-only" in args:
        return 0
    if "--phone" in args:
        print("📱 Phone mode — the phone URLs and certificate steps follow.\n", flush=True)
        return subprocess.call([sys.executable, os.path.join(ROOT, "build", "serve_https.py")])
    return serve_local(open_browser="--no-open" not in args)


if __name__ == "__main__":
    sys.exit(main())
