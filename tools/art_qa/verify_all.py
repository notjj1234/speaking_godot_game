"""verify_all.py — single entry point for the horde art pass checks.

    python3.13 tools/art_qa/verify_all.py            # all checks, previews refreshed
    python3.13 tools/art_qa/verify_all.py --no-previews

Exits 1 if any check fails. Prints one line per check (✅ / ❌).
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verify_sheets as V  # noqa: E402


def main():
    results = []
    gob_res, gob = V.check_enemy("goblin", None)
    results += gob_res
    for key in ("slime", "beetle", "orc", "skeleton", "bandit"):
        r, _ = V.check_enemy(key, gob)
        results += r
    for key in V.ENEMIES:
        results += V.check_tscn(key)
    results += V.check_npcs()
    results += V.check_props()
    results += V.check_frozen()
    results += V.check_contract_shas()
    fails = 0
    for ok, msg in results:
        print(("✅ " if ok else "❌ ") + msg)
        fails += 0 if ok else 1
    if "--no-previews" not in sys.argv:
        out = V.rp("tools/art_qa/preview")
        n = len(V.render_previews(out))
        print(f"✅ wrote {n} previews to tools/art_qa/preview/")
    print(f"\n{len(results) - fails}/{len(results)} checks passed")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
