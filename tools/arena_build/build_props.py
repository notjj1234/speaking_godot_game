"""build_props.py — extend props/Sprites/Props.png (1024x192 = 16x3 cells of 64 px).

The bush at cell 0 is the original art and is copied through untouched (it is
what props/Plants/plant.tscn shows). Every biome prop is drawn into an EMPTY
cell. Footprint convention: a prop's ground contact is centred at (32, 48)
of its cell (bottom half = footprint, top half = overhang), so an arena
places the Sprite2D at the footprint centre with offset (0, -16).

PROPS (frame -> name) is the single source of truth: build_arenas.py and
render_arenas.py import it.
"""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "art_build"))
from pixrig import Mat, Rig, m_ellipse, m_limb, m_line, m_poly, m_rect, rp  # noqa: E402
from PIL import Image  # noqa: E402

OUT = "#150918"

# name: (frame, solid, width_in_cells, flat)
#   solid -> a Blockers collision shape is emitted and the cell counts as blocked
#   flat  -> ground decal: y-sorted from its top edge so actors always walk over it
PROPS = {
    "bush":          (0, False, 1, False),
    "oak":           (1, True, 1, False),
    "stump":         (2, True, 1, False),
    "mossy_boulder": (3, True, 1, False),
    "flowers":       (4, False, 1, True),
    "tall_grass":    (5, False, 1, False),
    "mushrooms":     (6, False, 1, True),
    "column":        (16, True, 1, False),
    "column_stump":  (17, True, 1, False),
    "fallen_pillar": (18, True, 2, False),
    "rubble":        (19, False, 1, True),
    "flagstones":    (20, False, 1, True),
    "tent":          (32, True, 2, False),
    "campfire":      (33, False, 1, False),
    "barrel":        (34, True, 1, False),
    "crates":        (35, True, 1, False),
    "scorch":        (36, False, 1, True),
    "banner":        (37, False, 1, False),
    "ice_crystal":   (40, True, 1, False),
    "frost_pine":    (41, True, 1, False),
    "frozen_rock":   (42, True, 1, False),
    "snow_drift":    (43, False, 1, True),
    "snow_patch":    (44, False, 1, True),
}

BARK = Mat("#8e5e38", "#654227", "#3e2717")
LEAF = Mat("#a2d050", "#5e9e36", "#2e5e22")
STONE = Mat("#bcbab0", "#8a887e", "#57564f")
MOSS = Mat("#9ccc5a", "#6aa23e", "#3f6e2a")
TUFT = Mat("#78c056", "#4c9638", "#2c6626")
RUIN = Mat("#d4d0c4", "#9e998c", "#65615a")
CANVAS = Mat("#e2d0a4", "#b49e70", "#7a6644")
WOOD = Mat("#b07a44", "#7c552e", "#4e341b")
IRON = Mat("#9ea4aa", "#6e7278", "#44474c")
FIRE = Mat("#ffe27a", "#ff9a2e", "#cc4a1e")
ASH = Mat("#5e554c", "#463f38", "#2e2a26")
OXBLOOD = Mat("#b04c4c", "#7e3236", "#531f20")
ICE = Mat("#f0fdff", "#a6e0f4", "#5aa6d0", rim="#ffffff")
PINE = Mat("#4a7a5e", "#2e5442", "#1a3428")
SNOW = Mat("#f6faff", "#d4e0ee", "#9fb0c8")
FROST = Mat("#a8b8c8", "#7a8a9c", "#4e5a6a")


def oak(r):
    r.part(m_rect(29, 36, 35, 54), BARK)
    r.part(m_poly([(26, 54), (38, 54), (36, 50), (28, 50)]), BARK)
    canopy = m_ellipse(32, 22, 17, 13) | m_ellipse(22, 28, 9, 7) | m_ellipse(42, 28, 9, 7)
    r.part(canopy, LEAF, shade="round")
    r.dot({(24, 14), (25, 13), (26, 13), (30, 11), (31, 11)}, LEAF.hi)


def stump(r):
    r.part(m_rect(23, 40, 41, 54), BARK)
    r.part(m_ellipse(32, 40, 9, 4), BARK, tone="hi")
    r.dot(m_ellipse(32, 40, 5, 2) - m_ellipse(32, 40, 4, 1), BARK.lo)
    r.part(m_poly([(20, 54), (25, 50), (25, 54)]) | m_poly([(44, 54), (39, 50), (39, 54)]), BARK)


def mossy_boulder(r):
    r.part(m_ellipse(32, 44, 15, 11), STONE, shade="round")
    r.part({p for p in m_ellipse(30, 38, 12, 6) if p[1] <= 38}, MOSS)


def flowers(r):
    for (x, y) in ((20, 44), (30, 40), (40, 46), (26, 52), (38, 54), (46, 40)):
        r.part(m_line(x, y, x - 1, y + 4) | m_line(x, y + 1, x + 2, y + 4), TUFT)
    for (x, y), c in zip(((20, 43), (30, 39), (40, 45), (26, 51), (38, 53), (46, 39)),
                         ("#ffffff", "#ffd84a", "#ff8ab4", "#ffd84a", "#ffffff", "#ff8ab4")):
        r.part({(x, y), (x + 1, y), (x, y - 1), (x + 1, y - 1)}, Mat(c, c, c))


def tall_grass(r):
    pts = set()
    for k, x in enumerate(range(22, 43, 3)):
        top = 34 + (k * 5) % 9
        pts |= m_line(x, 54, x + (k % 3) - 1, top)
    r.part(pts, TUFT)


def mushrooms(r):
    for (x, y, s) in ((26, 48, 4), (36, 52, 3), (40, 44, 3)):
        r.part(m_rect(x - 1, y, x + 1, y + 4), CANVAS)
        r.part({p for p in m_ellipse(x, y, s + 1, s) if p[1] <= y}, OXBLOOD)
        r.dot({(x - 1, y - s + 1), (x + 1, y - 1)}, "#ffffff")


def column(r):
    r.part(m_rect(22, 50, 42, 55), RUIN)                     # plinth
    shaft = m_rect(25, 16, 39, 50)
    shaft -= m_poly([(25, 16), (30, 16), (27, 22)]) | m_poly([(34, 16), (39, 16), (39, 21), (36, 19)])  # broken top
    r.part(shaft, RUIN)
    for x in (29, 33, 37):
        r.dot(m_line(x, 22, x, 49), RUIN.lo)
    r.part({p for p in m_ellipse(31, 30, 4, 3)}, MOSS)


def column_stump(r):
    r.part(m_rect(22, 50, 42, 55), RUIN)
    r.part(m_rect(25, 36, 39, 50) - m_poly([(25, 36), (33, 36), (25, 40)]), RUIN)
    for x in (29, 33, 37):
        r.dot(m_line(x, 39, x, 49), RUIN.lo)


def fallen_pillar(r):
    r.part(m_rect(4, 40, 58, 52), RUIN)
    r.part(m_ellipse(58, 46, 4, 6), RUIN, tone="hi")
    for y in (43, 47):
        r.dot(m_line(6, y, 54, y), RUIN.lo)
    r.part(m_ellipse(16, 38, 6, 3), MOSS)
    r.part(m_poly([(4, 40), (8, 36), (12, 40)]), RUIN)


def rubble(r):
    for (x, y, a, b) in ((22, 48, 4, 3), (34, 52, 5, 3), (42, 44, 3, 2), (28, 42, 2, 2)):
        r.part(m_ellipse(x, y, a, b), RUIN)


def flagstones(r):
    for (x0, y0, x1, y1) in ((14, 34, 29, 45), (31, 33, 49, 43), (16, 47, 35, 61), (37, 45, 50, 60)):
        r.part(m_rect(x0, y0, x1, y1) - {(x0, y0), (x1, y0), (x0, y1), (x1, y1)}, RUIN, sep=False)


def tent(r):
    body = m_poly([(6, 54), (32, 18), (58, 54)])
    r.part(body, CANVAS)
    r.part(m_poly([(26, 54), (32, 36), (38, 54)]), ASH, tone="lo")       # open flap
    r.part(m_line(32, 14, 32, 20, 2), WOOD)
    r.dot(m_line(10, 52, 30, 22), CANVAS.hi)


def campfire(r):
    for a, (x, y) in enumerate(((22, 52), (32, 55), (42, 52), (26, 46), (38, 46))):
        r.part(m_ellipse(x, y, 3, 2), STONE)
    r.part(m_line(24, 52, 40, 46, 3) | m_line(24, 46, 40, 52, 3), WOOD)
    r.part(m_poly([(26, 48), (32, 30), (38, 48)]), FIRE, shade="round")
    r.dot(m_poly([(30, 47), (32, 38), (34, 47)]), FIRE.hi)


def barrel(r):
    r.part(m_rect(24, 30, 40, 54) - {(24, 30), (40, 30), (24, 54), (40, 54)}, WOOD)
    r.part(m_ellipse(32, 30, 8, 3), WOOD, tone="hi")
    for y in (36, 48):
        r.part(m_rect(24, y, 40, y + 1), IRON)


def crates(r):
    r.part(m_rect(18, 36, 38, 54), WOOD)
    r.dot(m_line(18, 36, 38, 54) | m_line(18, 54, 38, 36), WOOD.lo)
    r.part(m_rect(30, 22, 46, 38), WOOD)
    r.dot(m_rect(30, 29, 46, 30), WOOD.lo)


def scorch(r):
    r.part(m_ellipse(32, 47, 18, 10), ASH, sep=False)
    r.part(m_ellipse(30, 46, 9, 5), ASH, tone="lo")


def banner(r):
    r.part(m_rect(23, 10, 24, 54), WOOD)
    r.part(m_poly([(25, 12), (42, 12), (42, 32), (34, 27), (25, 32)]), OXBLOOD)
    r.dot(m_ellipse(33, 19, 2, 2), CANVAS.hi)


def ice_crystal(r):
    r.part(m_poly([(26, 54), (24, 30), (29, 16), (33, 30), (32, 54)]), ICE, rim=True)
    r.part(m_poly([(32, 54), (36, 26), (40, 20), (42, 34), (40, 54)]), ICE, rim=True)
    r.part(m_poly([(18, 54), (17, 42), (21, 36), (24, 54)]), ICE, rim=True)


def frost_pine(r):
    r.part(m_rect(30, 46, 34, 55), BARK)
    for k, (y, w) in enumerate(((14, 6), (24, 10), (34, 14))):
        tier = m_poly([(32, y - 6), (32 + w, y + 10), (32 - w, y + 10)])
        r.part(tier, PINE)
        r.part(m_poly([(32, y - 6), (32 + w // 2, y + 2), (32 - w // 2, y + 2)]), SNOW)


def frozen_rock(r):
    r.part(m_ellipse(32, 45, 15, 10), FROST, shade="round")
    r.part({p for p in m_ellipse(30, 39, 12, 6) if p[1] <= 39}, SNOW)


def snow_drift(r):
    r.part(m_ellipse(26, 50, 14, 7) | m_ellipse(40, 47, 12, 6), SNOW, sep=False)


def snow_patch(r):
    r.part(m_ellipse(32, 48, 10, 5), SNOW, sep=False)


DRAW = {
    "oak": oak, "stump": stump, "mossy_boulder": mossy_boulder, "flowers": flowers, "tall_grass": tall_grass,
    "mushrooms": mushrooms, "column": column, "column_stump": column_stump, "fallen_pillar": fallen_pillar,
    "rubble": rubble, "flagstones": flagstones, "tent": tent, "campfire": campfire, "barrel": barrel,
    "crates": crates, "scorch": scorch, "banner": banner, "ice_crystal": ice_crystal, "frost_pine": frost_pine,
    "frozen_rock": frozen_rock, "snow_drift": snow_drift, "snow_patch": snow_patch,
}


def build(src: Image.Image):
    src = src.convert("RGBA")
    assert src.size == (1024, 192)
    out = Image.new("RGBA", (1024, 192), (0, 0, 0, 0))
    out.paste(src.crop((0, 0, 64, 64)), (0, 0))          # original bush, untouched
    for name, (frame, *_rest) in PROPS.items():
        if name == "bush":
            continue
        cx, cy = (frame % 16) * 64, (frame // 16) * 64
        assert src.crop((cx, cy, cx + 64, cy + 64)).getbbox() is None or name in DRAW, f"cell {frame} not empty"
        r = Rig(64, 64, OUT)
        DRAW[name](r)
        out.paste(r.render(), (cx, cy))
    return out


if __name__ == "__main__":
    import subprocess
    import io
    # always build from the committed original so re-runs are idempotent
    orig = subprocess.run(["git", "show", "ab3ca09:props/Sprites/Props.png"], cwd=rp("."), capture_output=True, check=True).stdout
    dst = sys.argv[1] if len(sys.argv) > 1 else rp("props/Sprites/Props.png")
    build(Image.open(io.BytesIO(orig))).save(dst)
    print("✅ wrote", dst)
