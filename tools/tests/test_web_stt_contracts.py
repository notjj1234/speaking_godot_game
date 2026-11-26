#!/usr/bin/env python3
"""Static contracts for the web STT provider (no browser or Godot binary needed).

F08: with continuous recognition still running (or still stopping), start()
throws InvalidStateError and _eval_start() returns "already". listen() must
treat that as live, not emit error(-1): -1 means "mic refused" to callers
(the bonfire cancels, and voice-only mode unlocks the keyboard).
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


def main() -> int:
    src = (ROOT / "speech_to_text/web_stt_provider.gd").read_text(encoding="utf-8")
    listen = re.search(r"func listen\(.*?\n(?:.*\n)*?(?=\nfunc |\Z)", src)
    body = listen.group(0) if listen else ""
    check("listen() exists", bool(listen))
    check(
        'listen() treats "already" as listening',
        'status == "ok" or status == "already"' in body,
        'expected `if status == "ok" or status == "already":` before listening_started',
    )
    check(
        "listen() does not stop/restart a running recognition",
        "_eval_stop()" not in body,
        "stop+start in the same frame races the browser's stopping state",
    )

    if failures:
        print(f"\n{failures} contract(s) failed")
        return 1
    print("\nAll web STT contracts passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
