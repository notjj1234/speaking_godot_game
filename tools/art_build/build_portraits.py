"""build_portraits.py — NPC dialogue portraits, 400x148 = 4 frames of 100x148.

Consumed by gui/dialog_system (NPCResource.portrait_hframes = 4): the frame
advances while a line is "spoken", so the strip is
  0 eyes open / mouth closed, 1 blink, 2 mouth open, 3 blink + mouth open.

Same characters and palettes as build_npcs.py (Daniel = warm civilian guide
with flat cap, moustache, apron and satchel strap; Stefano = cool patrol
guard with steel cap + nasal guard, blue plume, mail, tabard and spear).
Each portrait is copied byte-for-byte into gui/dialog_system/sprites/portraits/.
"""
from __future__ import annotations

import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pixrig import Mat, Rig, hx, m_ellipse, m_line, m_poly, m_rect, rp  # noqa: E402
from build_npcs import DANIEL, STEFANO  # noqa: E402
from PIL import Image  # noqa: E402

W, H = 100, 148
OUT = "#150918"
EYE_WHITE = "#f4f0e6"
MOUTH = "#5a1e24"
TEETH = "#f4f0e6"

DAN_SKY = Mat("#fbd9a0", "#f4b27a", "#d98a5c")
DAN_HILL = Mat("#c9925a", "#a8703f", "#7e5030")
DAN_IRIS = "#5a3420"
STE_WALL = Mat("#8d9bb0", "#6c7a90", "#4c586b")
STE_IRIS = "#3c5a7a"


def card_mask():
    """Rounded card: inside pixels (corner radius 7)."""
    pts = set()
    r = 7
    for y in range(1, H - 1):
        for x in range(1, W - 1):
            cx = min(max(x, r + 1), W - r - 2)
            cy = min(max(y, r + 1), H - r - 2)
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                pts.add((x, y))
    return pts


CARD = card_mask()


def frame_card(img, rim):
    """Outline the card edge (2 px: dark outer, coloured inner) and clear outside."""
    px = img.load()
    rim = hx(rim)
    dark = hx(OUT)
    for y in range(H):
        for x in range(W):
            if (x, y) not in CARD:
                px[x, y] = (0, 0, 0, 0)
                continue
            n4 = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
            if any(q not in CARD for q in n4):
                px[x, y] = dark
            elif any((qx + dx, qy + dy) not in CARD for qx, qy in n4 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                px[x, y] = rim
    return img


def face(r, skin, hair, iris, blink, talk, brow_y=59):
    # ears + head + jaw
    r.part(m_ellipse(25, 72, 4, 7) | m_ellipse(75, 72, 4, 7), skin, band=2)
    r.part(m_ellipse(50, 67, 25, 28) | m_poly([(30, 80), (70, 80), (62, 96), (50, 99), (38, 96)]), skin, band=3)
    # brows
    for bx in (39, 61):
        r.part(m_rect(bx - 6, brow_y, bx + 6, brow_y + 2) - {(bx - 6, brow_y), (bx + 6, brow_y)}, hair, tone="mid")
    # eyes
    for ex in (39, 61):
        if blink:
            r.part(m_line(ex - 5, 70, ex + 5, 70) | {(ex - 5, 69), (ex + 5, 69)}, skin, tone="lo")
            r.dot(m_line(ex - 4, 70, ex + 4, 70), OUT)
        else:
            r.part(m_ellipse(ex, 69, 5, 3.5), Mat(EYE_WHITE, EYE_WHITE, "#cfc6b4"), sep=False)
            r.dot(m_ellipse(ex + 1, 69, 2.5, 3) & m_ellipse(ex, 69, 5, 3.5), iris)
            r.dot({(ex + 1, 69), (ex + 1, 70)}, OUT)
            r.dot({(ex, 68)}, EYE_WHITE)
            r.dot(m_line(ex - 5, 65, ex + 5, 65) & m_ellipse(ex, 68, 6, 4), OUT)   # upper lid line
    # nose (light from top-left: shadow on the right side)
    r.dot(m_line(53, 72, 54, 80), skin.lo)
    r.dot({(48, 81), (49, 81), (52, 81), (53, 81), (54, 80)}, skin.lo)
    # mouth
    if talk:
        r.part(m_ellipse(50, 88, 6, 3.5), Mat(MOUTH, MOUTH, "#3a1016"), sep=False)
        r.dot(m_line(46, 86, 54, 86), TEETH)
    else:
        r.dot(m_line(45, 88, 55, 88), skin.lo)
        r.dot({(44, 87), (56, 87)}, skin.lo)


def daniel(blink, talk):
    M = DANIEL
    r = Rig(W, H, OUT)
    r.part(m_rect(0, 0, W - 1, 60), DAN_SKY, tone="hi")
    r.part(m_rect(0, 61, W - 1, 92), DAN_SKY, tone="mid")
    r.part(m_ellipse(14, 22, 9, 4) | m_ellipse(22, 20, 7, 4), DAN_SKY, tone="lo")    # cloud
    r.part(m_ellipse(84, 34, 8, 3), DAN_SKY, tone="lo")
    r.part(m_ellipse(20, 120, 40, 30) | m_ellipse(88, 112, 34, 26), DAN_HILL, band=3)
    # stout shoulders, rust shirt
    r.part(m_poly([(2, 147), (8, 118), (30, 106), (70, 106), (92, 118), (98, 147)]), M["shirt"], band=3)
    r.part(m_rect(41, 92, 59, 110), M["skin"], band=2)                                 # neck
    r.part(m_poly([(36, 106), (50, 120), (64, 106), (58, 104), (50, 112), (42, 104)]), M["apron"], tone="mid")  # collar
    r.part(m_rect(32, 122, 68, 147), M["apron"], band=2)                               # apron bib
    r.part(m_line(34, 122, 26, 108, 3) | m_line(66, 122, 74, 108, 3), M["apron"], tone="lo")
    r.part(m_poly([(10, 112), (17, 108), (92, 145), (86, 147), (80, 147)]), M["bag"], band=2)  # satchel strap
    r.dot({(56, 128), (57, 128), (56, 129), (57, 129)}, M["cap"].hi)                   # strap buckle
    r.part({p for p in m_ellipse(50, 62, 29, 20) if p[1] <= 80}, M["hair"], band=2)     # hair mass behind the head
    face(r, M["skin"], M["hair"], DAN_IRIS, blink, talk)
    # sideburns + moustache
    r.part(m_poly([(38, 82), (62, 82), (64, 86), (58, 85), (50, 84), (42, 85), (36, 86)]), M["hair"], band=1)
    # flat cap: dome + forward brim
    r.part(m_poly([(26, 62), (30, 62), (31, 74), (27, 72)]) | m_poly([(70, 62), (74, 62), (73, 72), (69, 74)]), M["hair"], band=1)
    # flat cap: low wide crown leaning forward, short stiff brim
    r.part({p for p in m_ellipse(52, 47, 31, 12) if p[1] <= 53}, M["cap"], band=3)
    r.part(m_poly([(22, 52), (80, 52), (82, 57), (20, 57)]), M["cap"], tone="lo")
    r.dot(m_line(30, 44, 70, 41), M["cap"].lo)                                          # crown seam
    r.dot({(52, 36), (53, 36), (52, 37), (53, 37)}, M["cap"].hi)                       # button
    return frame_card(r.render(outline_mode="dark"), "#a8703f")


def stefano(blink, talk):
    M = STEFANO
    r = Rig(W, H, OUT)
    r.part(m_rect(0, 0, W - 1, H - 1), STE_WALL, tone="mid")
    for row in range(0, H, 16):                                                         # stone courses
        r.part(m_rect(0, row, W - 1, row), STE_WALL, tone="lo")
        off = 0 if (row // 16) % 2 else 14
        for x in range(off, W, 28):
            r.part(m_rect(x, row, x, row + 15), STE_WALL, tone="lo")
            r.part(m_rect(x + 1, row + 1, x + 9, row + 1), STE_WALL, tone="hi")
    # spear behind the shoulder
    r.part(m_rect(86, 22, 88, 147), M["wood"], band=1)
    r.part(m_poly([(87, 4), (92, 14), (87, 24), (82, 14)]), M["steel"], band=1)
    # mail shoulders + tabard
    r.part(m_poly([(4, 147), (10, 120), (32, 108), (68, 108), (90, 120), (96, 147)]), M["steel"], band=3)
    r.dot({(x, y) for y in range(112, 147, 3) for x in range(8 + (y // 3) % 2, 94, 3)}, M["steel"].lo)  # mail rings
    r.part(m_rect(42, 92, 58, 112), M["skin"], band=2)
    r.part(m_poly([(28, 118), (72, 118), (74, 147), (26, 147)]), M["tabard"], band=3)
    r.part(m_line(50, 124, 50, 142, 3) | m_line(42, 131, 58, 131, 3), M["steel"], tone="hi")   # emblem
    r.part({p for p in m_ellipse(50, 64, 28, 18) if p[1] <= 78}, M["hair"], band=2)
    face(r, M["skin"], M["hair"], STE_IRIS, blink, talk, brow_y=60)
    # steel cap: dome, rim, nasal guard, rivets, plume
    r.part(m_ellipse(50, 18, 5, 9), M["tabard"], band=2)
    r.part({p for p in m_ellipse(50, 46, 29, 20) if p[1] <= 53}, M["steel"], band=3)
    r.part(m_rect(21, 52, 79, 56), M["steel"], tone="lo")
    r.part(m_rect(48, 56, 52, 76), M["steel"], band=1)
    r.dot({(28, 54), (40, 54), (60, 54), (72, 54)}, M["steel"].hi)
    return frame_card(r.render(outline_mode="dark"), "#3a4a66")


def strip(fn):
    out = Image.new("RGBA", (400, 148), (0, 0, 0, 0))
    for i, (blink, talk) in enumerate(((False, False), (True, False), (False, True), (True, True))):
        out.paste(fn(blink, talk), (i * 100, 0))
    return out


TARGETS = [(daniel, "npc/sprites/portraits/npc_portrait_01.png"), (stefano, "npc/sprites/portraits/npc_portrait_02.png")]

if __name__ == "__main__":
    if len(sys.argv) > 1:
        o = Image.new("RGBA", (400, 296))
        o.paste(strip(daniel), (0, 0)); o.paste(strip(stefano), (0, 148))
        o.save(sys.argv[1])
        print("✅ wrote preview", sys.argv[1])
    else:
        for fn, path in TARGETS:
            strip(fn).save(rp(path))
            dup = path.replace("npc/sprites/", "gui/dialog_system/sprites/")
            shutil.copyfile(rp(path), rp(dup))
            print("✅ wrote", path, "and copied to", dup)
