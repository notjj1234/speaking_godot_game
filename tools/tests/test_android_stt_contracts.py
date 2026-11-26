#!/usr/bin/env python3
"""Static contracts for Android-only STT behaviour (no device needed).

F22: the Android plugin only signals results and errors, so the provider must
     report listening_started/listening_stopped itself.
F15: a mic denial at boot happens on the title screen, which has no
     MicPermissionPanel; STTManager must retry when a level loads.

    python3.13 tools/tests/test_android_stt_contracts.py
"""

from __future__ import annotations

import re
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


def body(src: str, func: str) -> str:
    m = re.search(rf"func {func}\(.*?\n(?:.*\n)*?(?=\n(?:func |##)|\Z)", src)
    return m.group(0) if m else ""


def main() -> int:
    provider = (ROOT / "speech_to_text/android_stt_provider.gd").read_text(encoding="utf-8")
    check("listen() reports listening_started", "listening_started.emit()" in body(provider, "listen"))
    check("stop() reports listening_stopped", "listening_stopped.emit()" in body(provider, "stop"))
    for fn in ("_on_plugin_listening_completed", "_on_plugin_error"):
        b = body(provider, fn)
        check(f"{fn} reports listening_stopped before the result",
              "listening_stopped.emit()" in b
              and b.find("listening_stopped.emit()") < max(b.find("listening_completed.emit("), b.find("error.emit(")))

    manager = (ROOT / "speech_to_text/STTManager.gd").read_text(encoding="utf-8")
    notice = body(manager, "show_restart_notice")
    check("missing panel defers the notice to the next level load",
          "level_loaded.connect(_retry_restart_notice)" in notice)
    retry = body(manager, "_retry_restart_notice")
    check("retry re-checks a late permission grant", "get_granted_permissions()" in retry)
    check("boot denial marks the notice as a permission denial", "show_restart_notice(true)" in manager)

    if failures:
        print(f"\n{failures} contract(s) failed")
        return 1
    print("\nAll Android STT contracts passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
