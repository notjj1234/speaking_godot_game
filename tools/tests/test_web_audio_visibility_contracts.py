#!/usr/bin/env python3
"""Static contracts for the web shell's audio/mic focus guard (no browser needed).

The guard must be installed before the engine script loads, so Godot's own
AudioContext is created through the tracking wrapper.
"""

from __future__ import annotations

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
    shell = (ROOT / "export" / "web_shell.html").read_text(encoding="utf-8")
    begin = shell.find("/* LQ_AUDIO_FOCUS_BEGIN */")
    end = shell.find("/* LQ_AUDIO_FOCUS_END */")
    engine = shell.find('<script src="$GODOT_URL"></script>')
    check("focus block present", begin != -1 and end > begin)
    check("engine script present", engine != -1)
    check("focus block installs before the engine loads", begin != -1 and end < engine,
          f"begin={begin} end={end} engine={engine}")
    # The marker pair holds the installer only (the Node test runs it with
    # fakes); the call that installs it sits between the end marker and the
    # engine script.
    block = shell[begin:engine] if begin != -1 and engine > begin else ""
    for needle in ("webkitAudioContext", "visibilitychange", "pagehide", "pageshow",
                   "getUserMedia", "speechSynthesis", "installAudioFocus(window, document)"):
        check(f"block mentions {needle}", needle in block)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main())
