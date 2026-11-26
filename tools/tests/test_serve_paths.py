#!/usr/bin/env python3
"""Path-mapping checks for the two local web servers (no server is started).

F09: build/serve_https.py listens on the LAN; URL tails under its mounts must
     never resolve outside the mounted folder.
F20: tools/web/play_in_browser.py must serve /extras/ (the scorer facade the
     web shell imports), with the same containment.

    python3.13 tools/tests/test_serve_paths.py
"""

from __future__ import annotations

import importlib.util
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
failures = 0


def check(name: str, cond: bool, detail: str = "") -> None:
    global failures
    if cond:
        print(f"✅ {name}")
    else:
        failures += 1
        suffix = f" — {detail}" if detail else ""
        print(f"❌ {name}{suffix}")


def load(rel: str, name: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / rel)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def handler(cls, directory: str):
    # translate_path needs no socket; skip the request-handling constructor.
    h = cls.__new__(cls)
    h.directory = directory
    return h


ESCAPES = [
    "//etc/passwd",
    "/../../etc/passwd",
    "../../../etc/passwd",
    "%2e%2e/%2e%2e/etc/passwd",
    "..%2f..%2fetc/passwd",
]
SCORER = "pronunciation/window_lqpron.js"


def inside(folder: str, path: str) -> bool:
    return os.path.commonpath([folder, os.path.realpath(path)]) == folder


def main() -> int:
    https = load("build/serve_https.py", "serve_https")
    extras = https.MOUNTS["/extras/"]
    h = handler(https.MountedHandler, https.ROOT)
    for tail in ESCAPES:
        out = h.translate_path("/extras/" + tail)
        check(f"serve_https: /extras/{tail} stays in mount", inside(extras, out), out)
        check(f"serve_https: /extras/{tail} does not exist", not os.path.exists(out), out)
    out = h.translate_path("/extras/" + SCORER)
    check("serve_https: scorer facade resolves", os.path.isfile(out), out)
    out = h.translate_path("/tools/../../etc/passwd")
    check("serve_https: /tools/ escape stays in mount", inside(https.MOUNTS["/tools/"], out), out)

    local = load("tools/web/play_in_browser.py", "play_in_browser")
    h = handler(local._Handler, local.WEB_DIR)
    out = h.translate_path("/extras/" + SCORER + "?v=1")
    check("play_in_browser: scorer facade resolves", os.path.isfile(out), out)
    for tail in ESCAPES:
        out = h.translate_path("/extras/" + tail)
        check(f"play_in_browser: /extras/{tail} stays in mount", inside(local.EXTRAS_DIR, out), out)
    out = h.translate_path("/index.html")
    check("play_in_browser: export root unchanged", out == os.path.join(local.WEB_DIR, "index.html"), out)

    if failures:
        print(f"\n{failures} check(s) failed")
        return 1
    print("\nAll server path checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
