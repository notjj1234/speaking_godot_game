#!/usr/bin/env python3
"""build_portraits.py — NPC dialogue portraits, 400x148 = 4 frames of 100x148.

Consumed by gui/dialog_system (NPCResource.portrait_hframes = 4): the frame
advances while a line is "spoken", so the strip is
  0 eyes open / mouth closed, 1 blink, 2 mouth open, 3 blink + mouth open.

Built from the hero's own portrait (npc/sprites/portraits/hero_portrait.png)
so the face, rendering and card match the main character: each frame is
recoloured per NPC (hair, eyes, scarf, shirt, background; shared hair/skin
reds are told apart by their neighbourhood), then the role pieces from
build_npcs.py are painted on with form shading: the smith's flat cap, beard
and satchel strap, the guard's kettle helmet, plume and mail, the cook's
toque. Each strip is copied byte-for-byte into
gui/dialog_system/sprites/portraits/.

    python3.13 tools/art_build/build_portraits.py           # write the strips
    python3.13 tools/art_build/build_portraits.py out.png   # preview, stacked
"""
from __future__ import annotations

import math
import os
import shutil
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERO = os.path.join(ROOT, "npc/sprites/portraits/hero_portrait.png")
W, H = 100, 148


def hx(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3)) + (255,)


OUT = hx("#150918")
NAMES = {"#ac3232": "h", "#730e1d": "H", "#356c56": "g", "#d95763": "r", "#37946e": "G", "#323c39": "k",
         "#ffffff": "w", "#4884ff": "b", "#3b0404": "J", "#ffcc9f": "s", "#590a12": "j", "#ffa88d": "S",
         "#150918": "o", "#a30a0a": "R", "#c7d1d7": "c", "#000000": "0", "#cbdbfc": "l", "#9badb7": "C",
         "#ffe6c4": "W", "#b7c6e5": "L", "#89b3ff": "B", "#6abe30": "v", "#696a6a": "m"}
HAIR_ONLY = set("hHJj")
SKIN_ONLY = set("sSW")
EYES = (42, 60, 83, 78)  # x0, y0, x1, y1


def frames():
    im = Image.open(HERO).convert("RGBA")
    return [im.crop((k * W, 0, k * W + W, H)) for k in range(4)]


def codes(f):
    g = [[None] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            p = f.getpixel((x, y))
            if p[3]:
                g[y][x] = NAMES.get("#%02x%02x%02x" % p[:3], "?")
    return g


def classify(g):
    """Per pixel: hair / skin / eye / scarf / shirt / bg / line."""
    cls = [[None] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            c = g[y][x]
            if c is None:
                continue
            in_eyes = EYES[0] <= x <= EYES[2] and EYES[1] <= y <= EYES[3]
            if c in HAIR_ONLY:
                k = "hair"
            elif c in SKIN_ONLY:
                k = "skin"
            elif c in ("r", "R"):
                hair = skin = 0
                for dy in range(-3, 4):
                    for dx in range(-3, 4):
                        if 0 <= y + dy < H and 0 <= x + dx < W:
                            n = g[y + dy][x + dx]
                            hair += n in HAIR_ONLY
                            skin += n in SKIN_ONLY
                k = "skin" if skin > hair else "hair"
            elif in_eyes and c in ("G", "v", "C", "w", "k", "0"):
                k = "eye"
            elif c in ("g", "G", "k"):
                k = "scarf"
            elif c == "w" and sum(1 for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                                  if 0 <= y + dy < H and 0 <= x + dx < W and g[y + dy][x + dx] in SKIN_ONLY) >= 3:
                k = "skin_white"
            elif c in ("c", "C", "m") or (c == "w" and y >= 105):
                k = "shirt"
            elif c in ("b", "B", "l", "L", "w"):
                k = "bg"
            else:
                k = "line"
            cls[y][x] = k
    return cls


def recolour(f, P):
    g = codes(f)
    cls = classify(g)
    out = f.copy()
    hair, skin = P["hair"], P.get("skin")
    for y in range(H):
        for x in range(W):
            c, k = g[y][x], cls[y][x]
            if c is None:
                continue
            col = None
            if k == "hair":
                col = {"r": hair[0], "h": hair[1], "R": hair[2], "H": hair[3], "j": hair[4], "J": hair[5]}.get(c)
            elif k == "skin" and skin:
                col = skin.get(c)
            elif k == "eye":
                col = {"G": P["iris"][1], "v": P["iris"][0]}.get(c)
            elif k == "scarf":
                col = {"G": P["scarf"][0], "g": P["scarf"][1], "k": P["scarf"][2]}.get(c)
            elif k == "shirt":
                col = {"w": P["shirt"][0], "c": P["shirt"][1], "C": P["shirt"][2], "m": P["shirt"][3]}.get(c)
            elif k == "bg":
                col = {"b": P["bg"][0], "B": P["bg"][1], "L": P["bg"][2], "l": P["bg"][3], "w": P["bg"][4]}.get(c)
            if col:
                out.putpixel((x, y), col)
    return out, g, cls


# ---------------------------------------------------------------- painting
def mask_of(draw_fn):
    m = Image.new("L", (W, H), 0)
    draw_fn(ImageDraw.Draw(m))
    return {(x, y) for y in range(H) for x in range(W) if m.getpixel((x, y))}


def _ray(mask, x, y, dx, dy, limit=60):
    n = 0
    fx, fy = x + 0.5, y + 0.5
    while n < limit:
        fx += dx
        fy += dy
        if (int(fx), int(fy)) not in mask:
            break
        n += 1
    return n


def paint(img, mask, tones, light=(-0.6, -0.8), outline=True, clip=None, cuts=(0.16, 0.42, 0.78)):
    """Form shading: light from `light` direction. tones = [hi, mid, lo] or [hi2, hi, mid, lo]."""
    if clip:
        mask = {p for p in mask if p in clip}
    if not mask:
        return
    if len(tones) == 3:
        tones = [tones[0]] + list(tones)
    lx, ly = light
    for (x, y) in mask:
        edge = any((x + dx, y + dy) not in mask for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        if outline and edge:
            img.putpixel((x, y), OUT)
            continue
        to_light = _ray(mask, x, y, lx, ly)
        away = _ray(mask, x, y, -lx, -ly)
        t = to_light / max(1, to_light + away)
        k = 0 if t < cuts[0] else 1 if t < cuts[1] else 2 if t < cuts[2] else 3
        img.putpixel((x, y), tones[k])


def dots(img, pts, col):
    for p in pts:
        img.putpixel(p, col)


def ramp(*hexes):
    return [hx(h) for h in hexes]

SMITH_P = dict(
    hair=ramp("#c48a5a", "#9a5a32", "#7e4626", "#6b3b1f", "#4e2a16", "#2e180c"),
    iris=ramp("#c08a50", "#7a4a26"),
    scarf=ramp("#de7840", "#ad5228", "#6f321a"),
    shirt=ramp("#f6ecd0", "#d2c096", "#958160", "#6a5a40"),
    bg=ramp("#f4b27a", "#fbd9a0", "#f6c890", "#fde8c4", "#fff4e0"),
)
GUARD_P = dict(
    hair=ramp("#8a7466", "#5a463e", "#4a3a32", "#3a2c26", "#2a1e1a", "#181010"),
    iris=ramp("#8ab0d8", "#3c5a7a"),
    scarf=ramp("#5a8ad0", "#3a62a0", "#223f70"),
    shirt=ramp("#e2ebf2", "#a3b3c3", "#617183", "#3e4a58"),
    bg=ramp("#6c7a90", "#8d9bb0", "#7c8aa0", "#a8b4c4", "#c4cdd8"),
)
COOK_P = dict(
    hair=ramp("#f0a868", "#d88444", "#c06e34", "#a85a28", "#7e4020", "#4e2410"),
    iris=ramp("#9ac070", "#4a6a3a"),
    scarf=ramp("#a8c486", "#789a5a", "#4c663a"),
    shirt=ramp("#fbf5e6", "#e2d6b8", "#b4a482", "#80704e"),
    bg=ramp("#dcc8a2", "#f2e2c4", "#e8d4b0", "#f8eedc", "#fffaf0"),
)

CARD = {(x, y) for x in range(11, 89) for y in range(10, 137)}


def mouth_zone(fs):
    a, b = fs[0], fs[2]
    pts = {(x, y) for y in range(H) for x in range(W) if a.getpixel((x, y)) != b.getpixel((x, y))}
    return {(x + dx, y + dy) for (x, y) in pts for dx in range(-2, 3) for dy in range(-2, 3)}


def beard_mask(mouth, full=True):
    m = set()
    if full:
        m |= mask_of(lambda dr: dr.polygon([(43, 84), (47, 82), (52, 92), (58, 96), (66, 95), (72, 90), (76, 82),
                                            (80, 84), (79, 96), (73, 106), (64, 113), (55, 111), (48, 103)], fill=255))
    m |= mask_of(lambda dr: dr.polygon([(49, 87), (53, 82), (59, 79), (64, 80), (70, 78), (76, 81), (78, 86),
                                        (72, 85), (65, 85), (58, 86), (52, 89)], fill=255))
    return {p for p in m if p not in mouth or p[1] < 84}


def beard(img, cls, mouth, tones, full=True):
    m = beard_mask(mouth, full)
    paint(img, m, tones, light=(-0.5, -0.9))
    for (x, y) in m:  # strands
        if img.getpixel((x, y)) != OUT and (x * 3 + y) % 7 == 0 and (x, y + 1) in m:
            img.putpixel((x, y), tones[min(3, tones.index(img.getpixel((x, y))) + 1)] if img.getpixel((x, y)) in tones else tones[2])


def strap(img, tones):
    m = mask_of(lambda d: d.polygon([(86, 100), (90, 104), (30, 137), (22, 137)], fill=255))
    m = {p for p in m if p in CARD}
    paint(img, m, tones)


MUSTARD = [hx("#ffe08a"), hx("#f2c85a"), hx("#c8962e"), hx("#8a5e1c")]


def smith(f, fs):
    img, g, cls = recolour(f, SMITH_P)
    beard(img, cls, mouth_zone(fs), [hx("#b87a4a"), hx("#93582f"), hx("#6e3e1e"), hx("#46240f")])
    strap(img, [hx("#c08a50"), hx("#8a5a30"), hx("#5a381c")])
    brim = mask_of(lambda d: d.polygon([(52, 44), (90, 40), (99, 46), (96, 54), (70, 56), (50, 52)], fill=255))
    paint(img, brim, [MUSTARD[2], MUSTARD[3], hx("#5e3e12")], clip=CARD)
    crown = mask_of(lambda d: d.polygon([(10, 50), (12, 34), (22, 20), (40, 12), (62, 11), (80, 16), (92, 28),
                                         (93, 42), (80, 46), (60, 47), (36, 49), (20, 54)], fill=255))
    paint(img, crown, MUSTARD, clip=CARD)
    dots(img, [(x, 46 - (x - 20) // 12) for x in range(18, 88) if (x, 46 - (x - 20) // 12) in crown], MUSTARD[3])
    dots(img, [(48 + (y - 12) // 6, y) for y in range(13, 46)], MUSTARD[2])
    dots(img, [(48 + (y - 12) // 6 - 1, y) for y in range(13, 46)], MUSTARD[1])
    return img


STEEL = [hx("#ffffff"), hx("#d8e2ea"), hx("#93a5b7"), hx("#58697c")]


def guard(f, fs):
    img, g, cls = recolour(f, GUARD_P)
    mail = [(x, y) for y in range(H) for x in range(W) if cls[y][x] == "shirt" and (x + y * 2) % 4 == 0]
    dots(img, mail, hx("#617183"))
    plume = mask_of(lambda d: d.polygon([(30, 22), (18, 18), (12, 11), (24, 11), (38, 16)], fill=255))
    paint(img, plume, [hx("#9ac0f4"), hx("#5a8ad0"), hx("#3a62a0"), hx("#223f70")], clip=CARD)
    brim = mask_of(lambda d: d.ellipse((6, 38, 98, 58), fill=255))
    paint(img, brim, [STEEL[1], STEEL[2], STEEL[3], hx("#3c4a5a")], clip=CARD)
    dome = mask_of(lambda d: d.chord((18, 10, 86, 76), 180, 360, fill=255))
    paint(img, dome, STEEL, clip=CARD)
    dots(img, [(x, 41) for x in range(26, 80, 8) if (x, 41) in dome], hx("#d6ac4a"))
    return img


def cook(f, fs):
    img, g, cls = recolour(f, COOK_P)
    white = [hx("#ffffff"), hx("#f4f0e6"), hx("#d6cfbf"), hx("#9c9484")]
    puff = mask_of(lambda d: [d.ellipse(b, fill=255) for b in ((14, 12, 46, 42), (32, 6, 70, 40), (56, 10, 90, 42))])
    paint(img, puff, white, clip=CARD)
    for x in (34, 50, 66):  # pleats
        dots(img, [(x + (y - 24) // 8, y) for y in range(24, 38) if (x + (y - 24) // 8, y) in puff], white[2])
    band = mask_of(lambda d: d.polygon([(18, 34), (50, 30), (86, 34), (86, 50), (50, 47), (18, 52)], fill=255))
    paint(img, band, white, clip=CARD)
    return img


def strip(fn):
    fs = frames()
    out = Image.new("RGBA", (W * 4, H))
    for k, f in enumerate(fs):
        out.alpha_composite(fn(f, fs), (k * W, 0))
    return out


TARGETS = [(smith, "npc/sprites/portraits/npc_portrait_01.png"), (guard, "npc/sprites/portraits/npc_portrait_02.png"),
           (cook, "npc/sprites/portraits/npc_portrait_03.png")]


def rp(path):
    return os.path.join(ROOT, path)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        o = Image.new("RGBA", (400, 148 * len(TARGETS)))
        for row, (fn, _path) in enumerate(TARGETS):
            o.paste(strip(fn), (0, 148 * row))
        o.save(sys.argv[1])
        print("✅ wrote preview", sys.argv[1])
    else:
        for fn, path in TARGETS:
            strip(fn).save(rp(path))
            dup = path.replace("npc/sprites/", "gui/dialog_system/sprites/")
            shutil.copyfile(rp(path), rp(dup))
            print("✅ wrote", path, "and copied to", dup)
