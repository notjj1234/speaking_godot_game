#!/usr/bin/env python3
"""Static contracts for enemy HP crisp numbers (no Godot binary required).

Pins the approved design: m5x7 draw_string path, size 12, outline 1,
hp/max format helper, no Abaddon Label mush under nearest-neighbor stretch.
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
	src = (ROOT / "enemies/scripts/enemy_health_bar.gd").read_text(encoding="utf-8")

	check(
		"uses m5x7 pixel font",
		'preload("res://gui/fonts/m5x7.ttf")' in src,
		"expected NUMBER_FONT preload of m5x7.ttf",
	)
	check("no Abaddon font", "Abaddon" not in src)
	check("no Label number path", "_make_number" not in src and "Label.new()" not in src)
	check("draws string", "draw_string(" in src)
	check("draws string outline", "draw_string_outline(" in src)
	check(
		"NUMBER_SIZE is 12",
		bool(re.search(r"NUMBER_SIZE\s*:?=\s*12\b", src)),
		"expected NUMBER_SIZE := 12",
	)
	check(
		"OUTLINE_SIZE is 1",
		bool(re.search(r"OUTLINE_SIZE\s*:?=\s*1\b", src)),
		"expected OUTLINE_SIZE := 1",
	)
	check(
		"get_display_text helper",
		"func get_display_text()" in src and '"%d/%d"' in src,
		"expected get_display_text returning %d/%d",
	)
	check("keeps setup/update_bar/hide_bar", all(
		f"func {name}(" in src for name in ("setup", "update_bar", "hide_bar")
	))

	return 0 if failures == 0 else 1


if __name__ == "__main__":
	sys.exit(main())
