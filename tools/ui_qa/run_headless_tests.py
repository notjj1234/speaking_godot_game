#!/usr/bin/env python3
"""Run the headless input tests on a throwaway copy of the project.

    python3.13 tools/ui_qa/run_headless_tests.py            # all test_*.tscn here
    GODOT=/path/to/Godot python3.13 tools/ui_qa/run_headless_tests.py

The copy keeps Godot's --import step from rewriting tracked .import files.
It also gets a throwaway user data dir (a renamed project), so the tests never
read or overwrite your real save or settings.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IGNORE = shutil.ignore_patterns(".git", "build", "graphify-out", "attachments",
                                "capture", "inbox", "pinned", "android", "__pycache__")


def find_godot() -> str | None:
    candidates = [os.environ.get("GODOT"),
                  str(Path.home() / "Downloads/Godot.app/Contents/MacOS/Godot"),
                  "/Applications/Godot.app/Contents/MacOS/Godot",
                  shutil.which("godot"), shutil.which("godot4")]
    return next((c for c in candidates if c and os.access(c, os.X_OK)), None)


def main() -> int:
    godot = find_godot()
    if godot is None:
        print("❌ No Godot binary found. Set GODOT=/path/to/Godot.")
        return 2
    with tempfile.TemporaryDirectory(prefix="loqui-uiqa-") as tmp:
        copy = Path(tmp) / "project"
        shutil.copytree(ROOT, copy, ignore=IGNORE)
        config = copy / "project.godot"
        config.write_text(re.sub(r'config/name="[^"]*"', f'config/name="uiqa-{Path(tmp).name}"',
                                 config.read_text()))
        base = [godot, "--headless", "--path", str(copy)]
        imported = subprocess.run(base + ["--import"], capture_output=True, text=True, timeout=900)
        bad = [l for l in (imported.stdout + imported.stderr).splitlines()
               if "SCRIPT ERROR" in l or "Parse Error" in l]
        if bad:
            print("\n".join(bad))
            return 1
        failed = 0
        for scene in sorted((copy / "tools/ui_qa").glob("test_*.tscn")):
            print(f"\n=== {scene.name}")
            run = subprocess.run(base + [f"res://tools/ui_qa/{scene.name}", "--quit-after", "6000"],
                                 capture_output=True, text=True, timeout=600)
            out = run.stdout + run.stderr
            lines = out.splitlines()
            for i, line in enumerate(lines):
                if line.startswith(("PASS", "FAIL", "RESULT")):
                    print(line)
                elif "SCRIPT ERROR" in line or "Parse Error" in line:
                    print("\n".join(lines[i:i + 3]))
            if run.returncode != 0 or "SCRIPT ERROR" in out or "RESULT" not in out:
                failed += 1
        return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
