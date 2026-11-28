"""style_check.py — do enemy/NPC sheets match the player's pixel style?

    python3.13 tools/art_build/style_check.py     # exit 1 if any target misses the bar

Pixel art only looks consistent when every character is drawn at the same
pixel density and line weight. This measures each sheet the way it shows up in
game (nearest filtering inside the fixed 640x480 viewport):

* net scale   root `scale` x Sprite2D `scale` in the character's scene. Anything
              but 1.0 drops or doubles pixel rows/columns, so lines come out
              uneven (a 1 px line renders as 0 or 1 px at 0.75).
* outline     share of silhouette-edge pixels that are dark (the player has a
              solid outline; pixrig's "selective" outline leaves gaps).
* region      average size of a flat same-colour region (bigger = blockier,
              flatter shading than the player).
* thick       share of dark pixels that are part of a 2x2+ dark line (heavy
              double outlines).

References (player, goblin, slime) are the style the user picked as "right";
they are printed for calibration and must clear the outline/region bars too.
"""
from __future__ import annotations

import os
import re
import sys
from collections import deque

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

MIN_OUTLINE = 0.90
MAX_REGION = 4.0
MAX_THICK = 0.20
DARK_EDGE_LUM = 60
DARK_LINE_LUM = 45
FRAMES_SAMPLED = 8

# name: (sheet, hframes, vframes, scene or None)
REFERENCES = {
    "player": ("player/Sprites/PlayerSprite02.png", 16, 3, "player/player.tscn"),
    "goblin": ("enemies/goblin/goblin.png", 8, 3, "enemies/goblin/goblin.tscn"),
    "slime": ("enemies/slime/Slime.png", 16, 2, "enemies/slime/slime.tscn"),
}
## A slime is one round blob: big flat regions are its design, so only its
## outline is held to the bar.
REGION_EXEMPT = {"slime", "boss_slime_king", "boss_slime_minion"}
TARGETS = {
    "orc": ("enemies/orc/orc.png", 8, 3, "enemies/orc/orc.tscn"),
    "bandit": ("enemies/bandit/bandit.png", 8, 3, "enemies/bandit/bandit.tscn"),
    "npc_smith": ("npc/sprites/npc_sprite.png", 15, 1, "npc/npc.tscn"),
    "npc_trainer": ("npc/sprites/npc_sprite_02.png", 15, 1, "npc/npc.tscn"),
    "npc_cook": ("npc/sprites/npc_sprite_03.png", 15, 1, "npc/npc.tscn"),
    # Bosses have no scene of their own: enemy.gd make_boss shows the sheet at
    # 0.5 inside a 2x boss (net 1.0); test_boss_fight.gd checks that at runtime.
    "boss_slime_king": ("enemies/bosses/slime_king.png", 16, 2, None),
    # Slime King adds: shown on the split child's own Sprite2D at net 1.0.
    "boss_slime_minion": ("enemies/bosses/slime_minion.png", 16, 2, None),
    "boss_bone_captain": ("enemies/bosses/bone_captain.png", 8, 3, None),
    "boss_orc_warlord": ("enemies/bosses/orc_warlord.png", 8, 3, None),
    "boss_frost_bandit": ("enemies/bosses/frost_bandit.png", 8, 3, None),
}


def _lum(p) -> float:
    return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]


def _scene_scale(scene: str) -> float:
    """Net x scale of the main Sprite2D: root scale x Sprite2D scale."""
    text = open(os.path.join(ROOT, scene)).read()
    blocks = re.split(r"^(?=\[node )", text, flags=re.M)
    root_scale = sprite_scale = 1.0
    for block in blocks:
        header = block.splitlines()[0] if block else ""
        m = re.search(r"^scale = Vector2\(([-\d.]+),", block, re.M)
        value = float(m.group(1)) if m else 1.0
        if header.startswith("[node") and "parent=" not in header:
            root_scale = value
        elif re.match(r'\[node name="Sprite2D" type="Sprite2D" parent="\."', header):
            sprite_scale = value
    return root_scale * sprite_scale


def measure(path: str, hf: int, vf: int) -> dict:
    im = Image.open(os.path.join(ROOT, path)).convert("RGBA")
    fw, fh = im.size[0] // hf, im.size[1] // vf
    opaque = transitions = edge = edge_dark = dark = thick = regions = 0
    for f in range(min(hf * vf, FRAMES_SAMPLED)):
        fx, fy = (f % hf) * fw, (f // hf) * fh
        px = im.crop((fx, fy, fx + fw, fy + fh)).load()

        def op(x, y):
            return 0 <= x < fw and 0 <= y < fh and px[x, y][3] > 0

        seen = set()
        for y in range(fh):
            for x in range(fw):
                if not op(x, y):
                    continue
                opaque += 1
                if any(not op(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    edge += 1
                    edge_dark += _lum(px[x, y]) < DARK_EDGE_LUM
                if _lum(px[x, y]) < DARK_LINE_LUM:
                    dark += 1
                    if all(op(x + dx, y + dy) and _lum(px[x + dx, y + dy]) < DARK_LINE_LUM
                           for dx, dy in ((1, 0), (0, 1))):
                        thick += 1
                if (x, y) in seen:
                    continue
                regions += 1
                colour = px[x, y]
                queue = deque([(x, y)])
                seen.add((x, y))
                while queue:
                    a, b = queue.popleft()
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        q = (a + dx, b + dy)
                        if q not in seen and op(*q) and px[q] == colour:
                            seen.add(q)
                            queue.append(q)
    if opaque == 0:
        raise ValueError(f"{path}: sampled frames are empty")
    return {
        "outline": edge_dark / edge,
        "region": opaque / regions,
        "thick": thick / max(dark, 1),
        "frame": f"{fw}x{fh}",
    }


def main() -> int:
    failures = 0
    for group, entries in (("reference", REFERENCES), ("target", TARGETS)):
        for name, (path, hf, vf, scene) in entries.items():
            if not os.path.exists(os.path.join(ROOT, path)):
                print(f"FAIL {name}: missing {path}")
                failures += 1
                continue
            m = measure(path, hf, vf)
            scale = _scene_scale(scene) if scene else 1.0
            problems = []
            if m["outline"] < MIN_OUTLINE:
                problems.append(f"outline {m['outline']:.0%} < {MIN_OUTLINE:.0%}")
            if m["region"] > MAX_REGION and name not in REGION_EXEMPT:
                problems.append(f"region {m['region']:.1f} > {MAX_REGION}")
            if group == "target":
                if abs(scale - 1.0) > 0.001:
                    problems.append(f"net scale {scale:.3f} != 1.0")
                if m["thick"] > MAX_THICK:
                    problems.append(f"thick {m['thick']:.0%} > {MAX_THICK:.0%}")
            line = (f"{name:12s} {group:9s} frame {m['frame']:6s} scale {scale:.3f} "
                    f"outline {m['outline']:.0%} region {m['region']:.1f} thick {m['thick']:.0%}")
            if problems:
                failures += 1
                print(f"FAIL {line}  <- {'; '.join(problems)}")
            else:
                print(f"PASS {line}")
    print(f"RESULT failures={failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
