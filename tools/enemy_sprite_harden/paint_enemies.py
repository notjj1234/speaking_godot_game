#!/usr/bin/env python3
"""Paint orc/bandit/skeleton sheets at goblin craft level.

Strategy: remix goblin sheet structure (silhouette, shading density, walk bob)
with character-specific palettes, heads, and weapons. Replace pure #000000
outlines with player/slime #150918. Emit 512x192 RGBA sheets.
"""
from __future__ import annotations

import struct
import zlib
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUTLINE = (0x15, 0x09, 0x18, 255)
TRANSPARENT = (0, 0, 0, 0)

# Goblin skin ramp → remap targets
GOBLIN_SKIN = {
    (0xCA, 0xB5, 0x91): "hi",
    (0xA3, 0x92, 0x63): "mid",
    (0x71, 0x64, 0x31): "shade",
    (0x2E, 0x28, 0x11): "deep",
}
GOBLIN_CLOTH = {(0x45, 0x28, 0x3C), (0x71, 0x4D, 0x31)}
GOBLIN_METAL = {(0x9B, 0xAD, 0xB7), (0xFF, 0xFF, 0xFF), (0x59, 0x56, 0x52)}
GOBLIN_EYE = (0xFF, 0xC9, 0x52)
GOBLIN_BLACK = (0, 0, 0)


def hex_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


ORC_PAL = {
    "hi": hex_rgb("#b5d65c"),
    "mid": hex_rgb("#8f9a4a"),
    "shade": hex_rgb("#5a7a32"),
    "deep": hex_rgb("#3a4a1c"),
    "cloth_hi": hex_rgb("#714d31"),
    "cloth": hex_rgb("#45283c"),
    "cloth_deep": hex_rgb("#2a1824"),
    "leather": hex_rgb("#8f563b"),
    "leather_deep": hex_rgb("#5a3e24"),
    "tusk": hex_rgb("#f0e6c8"),
    "tusk_shade": hex_rgb("#cbb891"),
    "metal": hex_rgb("#9badb7"),
    "metal_hi": hex_rgb("#ffffff"),
    "metal_shade": hex_rgb("#595652"),
    "wood": hex_rgb("#a06a3a"),
    "wood_deep": hex_rgb("#5a3e24"),
    "eye": hex_rgb("#ffc952"),
    "accent": hex_rgb("#ac3232"),
    "buckle": hex_rgb("#d4a017"),
    "lip": hex_rgb("#6b3030"),
}

BANDIT_PAL = {
    "hi": hex_rgb("#e8c090"),
    "mid": hex_rgb("#c9a06a"),
    "shade": hex_rgb("#8f563b"),
    "deep": hex_rgb("#663931"),
    "cloth_hi": hex_rgb("#6b4a7a"),
    "cloth": hex_rgb("#45283c"),
    "cloth_deep": hex_rgb("#2a1824"),
    "leather": hex_rgb("#714d31"),
    "leather_deep": hex_rgb("#3d2024"),
    "hood": hex_rgb("#5a3a6a"),
    "hood_hi": hex_rgb("#7a5a8a"),
    "mask": hex_rgb("#323c39"),
    "metal": hex_rgb("#c7d1d7"),
    "metal_hi": hex_rgb("#ffffff"),
    "metal_shade": hex_rgb("#595652"),
    "wood": hex_rgb("#8f563b"),
    "wood_deep": hex_rgb("#5a3e24"),
    "eye": hex_rgb("#ffc952"),
    "accent": hex_rgb("#ac3232"),
    "buckle": hex_rgb("#d4a017"),
    "scarf": hex_rgb("#37946e"),
}

SKELETON_PAL = {
    "hi": hex_rgb("#f0e6c8"),
    "mid": hex_rgb("#d4c4a0"),
    "shade": hex_rgb("#a39263"),
    "deep": hex_rgb("#716431"),
    "cloth_hi": hex_rgb("#6b4a7a"),
    "cloth": hex_rgb("#45283c"),
    "cloth_deep": hex_rgb("#2a1824"),
    "leather": hex_rgb("#595652"),
    "leather_deep": hex_rgb("#323c39"),
    "metal": hex_rgb("#9badb7"),
    "metal_hi": hex_rgb("#ffffff"),
    "metal_shade": hex_rgb("#515454"),
    "wood": hex_rgb("#cab591"),
    "wood_deep": hex_rgb("#716431"),
    "eye": hex_rgb("#ff7600"),
    "socket": hex_rgb("#150918"),
    "accent": hex_rgb("#d22c0d"),
    "moss": hex_rgb("#356c56"),
    "moss_hi": hex_rgb("#37946e"),
    "crack": hex_rgb("#663931"),
    "wrap_hi": hex_rgb("#8f563b"),
    "wrap_mid": hex_rgb("#a06a3a"),
    "gold": hex_rgb("#d4a017"),
    "ember": hex_rgb("#ffb000"),
}


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else (b if pb <= pc else c)


def read_png(path: Path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos = 8
    w = h = None
    idat = b""
    color_type = 6
    while pos < len(data):
        ln = struct.unpack(">I", data[pos : pos + 4])[0]
        t = data[pos + 4 : pos + 8]
        ch = data[pos + 8 : pos + 8 + ln]
        pos += 12 + ln
        if t == b"IHDR":
            w, h = struct.unpack(">II", ch[:8])
            color_type = ch[9]
        elif t == b"IDAT":
            idat += ch
        elif t == b"IEND":
            break
    raw = zlib.decompress(idat)
    bpp = 4 if color_type == 6 else 3
    stride = w * bpp
    rows = []
    i = 0
    prev = bytearray(stride)
    for _y in range(h):
        f = raw[i]
        i += 1
        row = bytearray(raw[i : i + stride])
        i += stride
        if f == 1:
            for x in range(stride):
                row[x] = (row[x] + (row[x - bpp] if x >= bpp else 0)) & 255
        elif f == 2:
            for x in range(stride):
                row[x] = (row[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride):
                left = row[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + ((left + prev[x]) // 2)) & 255
        elif f == 4:
            for x in range(stride):
                a = row[x - bpp] if x >= bpp else 0
                b = prev[x]
                c = prev[x - bpp] if x >= bpp else 0
                row[x] = (row[x] + paeth(a, b, c)) & 255
        rows.append(bytes(row))
        prev = row
    px = []
    for row in rows:
        if color_type == 6:
            px.append(
                [
                    (row[x], row[x + 1], row[x + 2], row[x + 3])
                    for x in range(0, len(row), 4)
                ]
            )
        else:
            px.append(
                [(row[x], row[x + 1], row[x + 2], 255) for x in range(0, len(row), 3)]
            )
    return w, h, px


def write_png(path: Path, w: int, h: int, pixels):
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(
            ">I", zlib.crc32(t + d) & 0xFFFFFFFF
        )

    raw = b""
    for y in range(h):
        raw += b"\x00"
        for x in range(w):
            r, g, b, a = pixels[y][x]
            raw += bytes((r, g, b, a))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def blank_cell():
    return [[TRANSPARENT for _ in range(64)] for _ in range(64)]


def copy_cell(sheet, idx):
    col, row = idx % 8, idx // 8
    return [
        [sheet[row * 64 + yy][col * 64 + xx] for xx in range(64)] for yy in range(64)
    ]


def put_cell(sheet, idx, cell):
    col, row = idx % 8, idx // 8
    for yy in range(64):
        for xx in range(64):
            sheet[row * 64 + yy][col * 64 + xx] = cell[yy][xx]


def setp(cell, x, y, rgba):
    if 0 <= x < 64 and 0 <= y < 64:
        cell[y][x] = rgba


def getp(cell, x, y):
    if 0 <= x < 64 and 0 <= y < 64:
        return cell[y][x]
    return TRANSPARENT


def fill_ellipse(cell, cx, cy, rx, ry, rgba):
    for y in range(cy - ry, cy + ry + 1):
        for x in range(cx - rx, cx + rx + 1):
            if rx == 0 or ry == 0:
                continue
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0:
                setp(cell, x, y, rgba)


def outline_opaque(cell, outline=OUTLINE):
    """Replace pure black + add missing outline neighbors with warm outline."""
    out = [row[:] for row in cell]
    for y in range(64):
        for x in range(64):
            r, g, b, a = cell[y][x]
            if a < 200:
                continue
            if (r, g, b) == (0, 0, 0):
                out[y][x] = outline
                continue
            # edge: any transparent 4-neighbor → outline pixel if currently mid/deep-ish
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if getp(cell, x + dx, y + dy)[3] < 200:
                    # darken edge pixel toward outline if it's already a dark tone
                    if r + g + b < 180:
                        out[y][x] = outline
                    break
    return out


def remap_goblin_cell(cell, pal, kind: str):
    """Map goblin colors onto character palette; keep structure."""
    out = blank_cell()
    for y in range(64):
        for x in range(64):
            r, g, b, a = cell[y][x]
            if a < 200:
                continue
            rgb = (r, g, b)
            if rgb == GOBLIN_BLACK:
                out[y][x] = OUTLINE
            elif rgb in GOBLIN_SKIN:
                key = GOBLIN_SKIN[rgb]
                rr, gg, bb = pal[key]
                out[y][x] = (rr, gg, bb, 255)
            elif rgb in GOBLIN_CLOTH:
                if rgb == (0x45, 0x28, 0x3C):
                    rr, gg, bb = pal["cloth"]
                else:
                    rr, gg, bb = pal["cloth_hi"]
                out[y][x] = (rr, gg, bb, 255)
            elif rgb == GOBLIN_EYE:
                rr, gg, bb = pal["eye"]
                out[y][x] = (rr, gg, bb, 255)
            elif rgb in GOBLIN_METAL:
                if rgb == (0xFF, 0xFF, 0xFF):
                    rr, gg, bb = pal["metal_hi"]
                elif rgb == (0x9B, 0xAD, 0xB7):
                    rr, gg, bb = pal["metal"]
                else:
                    rr, gg, bb = pal["metal_shade"]
                out[y][x] = (rr, gg, bb, 255)
            else:
                # leftover browns → leather
                if r > 60 and g > 40 and b < 80:
                    rr, gg, bb = pal["leather"]
                    out[y][x] = (rr, gg, bb, 255)
                else:
                    out[y][x] = (r, g, b, 255)
    return out


def clear_rect(cell, x0, y0, x1, y1):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            setp(cell, x, y, TRANSPARENT)


def paint_rect(cell, x0, y0, x1, y1, rgba):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            setp(cell, x, y, rgba)


def clear_goblin_spear(cell, pal, side=False):
    """Strip remapped goblin spear tip + thin shaft before drawing a new weapon."""
    metalish = {
        pal["metal_hi"],
        pal["metal"],
        pal["metal_shade"],
        (0xFF, 0xFF, 0xFF),
        (0x9B, 0xAD, 0xB7),
        (0x59, 0x56, 0x52),
    }
    woodish = {pal["wood"], pal["wood_deep"], pal["leather"], pal["leather_deep"]}
    for y in range(64):
        for x in range(64):
            r, g, b, a = cell[y][x]
            if a < 200:
                continue
            rgb = (r, g, b)
            if side:
                # goblin side spear is a thin horizontal protrusion on the right
                if x >= 42 and rgb in metalish:
                    setp(cell, x, y, TRANSPARENT)
                if x >= 40 and 28 <= y <= 34 and rgb in woodish | metalish:
                    setp(cell, x, y, TRANSPARENT)
            else:
                # front/back: spear tip + shaft on the far left
                if x <= 22 and y >= 18 and rgb in metalish:
                    setp(cell, x, y, TRANSPARENT)
                if x <= 21 and 22 <= y <= 48 and rgb in woodish and getp(cell, x + 2, y)[3] < 200:
                    setp(cell, x, y, TRANSPARENT)


def replace_spear_with_club(cell, pal, side=False, chase=False):
    """Erase goblin spear and draw a thicker club."""
    clear_goblin_spear(cell, pal, side=side)

    wood = (*pal["wood"], 255)
    wood_d = (*pal["wood_deep"], 255)
    head = (*pal["metal_shade"], 255)
    head_hi = (*pal["metal"], 255)

    if side:
        y0 = 30 if not chase else 28
        paint_rect(cell, 35, y0, 46, y0 + 2, wood)
        paint_rect(cell, 35, y0 + 1, 45, y0 + 1, wood_d)
        paint_rect(cell, 46, y0 - 1, 50, y0 + 3, head)
        paint_rect(cell, 47, y0, 49, y0 + 2, head_hi)
        for x, y in ((45, y0 - 2), (51, y0 - 2), (51, y0 + 4), (45, y0 + 4)):
            setp(cell, x, y, OUTLINE)
    else:
        x0 = 19
        paint_rect(cell, x0, 24, x0 + 2, 42, wood)
        paint_rect(cell, x0 + 1, 24, x0 + 1, 42, wood_d)
        paint_rect(cell, x0 - 1, 20, x0 + 4, 26, head)
        paint_rect(cell, x0, 21, x0 + 3, 25, head_hi)
        for x, y in ((x0 - 2, 19), (x0 + 5, 19), (x0 - 2, 27), (x0 + 5, 27)):
            setp(cell, x, y, OUTLINE)


def replace_spear_with_dagger(cell, pal, side=False, chase=False):
    clear_goblin_spear(cell, pal, side=side)
    blade = (*pal["metal_hi"], 255)
    shade = (*pal["metal"], 255)
    hilt = (*pal["leather"], 255)
    if side:
        y0 = 31 if not chase else 29
        paint_rect(cell, 36, y0, 48, y0, blade)
        paint_rect(cell, 36, y0 + 1, 46, y0 + 1, shade)
        paint_rect(cell, 34, y0, 36, y0 + 1, hilt)
        setp(cell, 49, y0, blade)
        setp(cell, 48, y0 - 1, OUTLINE)
        setp(cell, 48, y0 + 2, OUTLINE)
    else:
        paint_rect(cell, 19, 28, 20, 40, blade)
        paint_rect(cell, 20, 28, 20, 38, shade)
        paint_rect(cell, 18, 38, 21, 40, hilt)


def replace_spear_with_bone_club(cell, pal, side=False, chase=False):
    clear_goblin_spear(cell, pal, side=side)
    bone = (*pal["hi"], 255)
    bone_s = (*pal["shade"], 255)
    if side:
        y0 = 30 if not chase else 28
        paint_rect(cell, 35, y0, 46, y0 + 1, bone)
        paint_rect(cell, 35, y0 + 1, 45, y0 + 1, bone_s)
        paint_rect(cell, 46, y0 - 1, 50, y0 + 3, bone)
        paint_rect(cell, 47, y0, 49, y0 + 2, bone_s)
    else:
        paint_rect(cell, 19, 22, 21, 40, bone)
        paint_rect(cell, 20, 22, 20, 40, bone_s)
        paint_rect(cell, 17, 18, 23, 24, bone)
        paint_rect(cell, 18, 19, 22, 23, bone_s)


def draw_orc_face_down(cell, pal, bob=0):
    """Add tusks + heavier brow on front-facing head region."""
    # tusks under mouth area ~ y=30
    tusk = (*pal["tusk"], 255)
    tusk_s = (*pal["tusk_shade"], 255)
    y = 30 + bob
    setp(cell, 28, y, tusk)
    setp(cell, 28, y + 1, tusk)
    setp(cell, 28, y + 2, tusk_s)
    setp(cell, 35, y, tusk)
    setp(cell, 35, y + 1, tusk)
    setp(cell, 35, y + 2, tusk_s)
    setp(cell, 29, y, (*pal["lip"], 255))
    setp(cell, 34, y, (*pal["lip"], 255))
    # brow ridge
    brow = (*pal["deep"], 255)
    for x in range(27, 37):
        if getp(cell, x, 22 + bob)[3] > 200:
            setp(cell, x, 22 + bob, brow)
    # harness straps across chest
    leather = (*pal["leather"], 255)
    for x in range(26, 38):
        if getp(cell, x, 36 + bob)[3] > 200:
            setp(cell, x, 36 + bob, leather)
            setp(cell, x, 37 + bob, (*pal["leather_deep"], 255))
    setp(cell, 31, 36 + bob, (*pal["buckle"], 255))
    setp(cell, 32, 36 + bob, (*pal["buckle"], 255))
    setp(cell, 30, 42 + bob, (*pal["accent"], 255))  # small wound accent


def draw_orc_face_side(cell, pal, bob=0):
    tusk = (*pal["tusk"], 255)
    tusk_s = (*pal["tusk_shade"], 255)
    # snout / tusk on right-facing profile
    setp(cell, 38, 28 + bob, tusk)
    setp(cell, 39, 28 + bob, tusk)
    setp(cell, 39, 29 + bob, tusk_s)
    setp(cell, 40, 29 + bob, tusk_s)
    # thicker ear already from goblin; add brow
    if getp(cell, 30, 22 + bob)[3] > 200:
        setp(cell, 30, 22 + bob, (*pal["deep"], 255))


def draw_bandit_hood_down(cell, pal, bob=0):
    hood = (*pal["hood"], 255)
    hood_hi = (*pal["hood_hi"], 255)
    hood_d = (*pal["cloth_deep"], 255)
    # recolor existing head pixels into hood — do not invent a rectangular box
    for y in range(16 + bob, 28 + bob):
        for x in range(22, 42):
            if getp(cell, x, y)[3] > 200:
                setp(cell, x, y, hood_hi if y <= 19 + bob else hood)
    # soft hood peak (only on already-opaque or immediate neighbors of head)
    for x in range(26, 37):
        if getp(cell, x, 17 + bob)[3] > 200:
            setp(cell, x, 16 + bob, OUTLINE)
    # face mask band on existing face pixels
    mask = (*pal["mask"], 255)
    for x in range(27, 36):
        if getp(cell, x, 26 + bob)[3] > 200:
            setp(cell, x, 26 + bob, mask)
        if getp(cell, x, 27 + bob)[3] > 200:
            setp(cell, x, 27 + bob, mask)
    eye = (*pal["eye"], 255)
    setp(cell, 29, 26 + bob, eye)
    setp(cell, 33, 26 + bob, eye)
    setp(cell, 31, 32 + bob, (*pal["scarf"], 255))
    setp(cell, 32, 32 + bob, (*pal["scarf"], 255))
    setp(cell, 31, 33 + bob, (*pal["buckle"], 255))
    setp(cell, 28, 40 + bob, (*pal["accent"], 255))
    # cloak sides only where body already exists or 1px outward
    for y in range(34 + bob, 48 + bob):
        if getp(cell, 24, y)[3] > 200:
            setp(cell, 23, y, hood)
            setp(cell, 22, y, hood_d)
        if getp(cell, 39, y)[3] > 200:
            setp(cell, 40, y, hood)
            setp(cell, 41, y, hood_d)


def draw_bandit_hood_side(cell, pal, bob=0):
    hood = (*pal["hood"], 255)
    hood_hi = (*pal["hood_hi"], 255)
    for y in range(17 + bob, 30 + bob):
        for x in range(24, 40):
            if getp(cell, x, y)[3] > 200:
                setp(cell, x, y, hood_hi if y < 20 + bob else hood)
    # short hood tip — only 2px forward of existing silhouette
    tip_x = max((x for x in range(64) if getp(cell, x, 22 + bob)[3] > 200), default=36)
    setp(cell, tip_x + 1, 21 + bob, hood)
    setp(cell, tip_x + 1, 22 + bob, hood)
    setp(cell, tip_x + 2, 22 + bob, OUTLINE)
    mask = (*pal["mask"], 255)
    for x in range(tip_x - 4, tip_x + 1):
        for y in range(26 + bob, 29 + bob):
            if getp(cell, x, y)[3] > 200:
                setp(cell, x, y, mask)
    setp(cell, tip_x - 2, 26 + bob, (*pal["eye"], 255))
    for y in range(32 + bob, 46 + bob):
        if getp(cell, 26, y)[3] > 200:
            setp(cell, 25, y, hood)
            setp(cell, 24, y, (*pal["cloth_deep"], 255))


def draw_bandit_hood_up(cell, pal, bob=0):
    hood = (*pal["hood"], 255)
    hood_hi = (*pal["hood_hi"], 255)
    for y in range(14 + bob, 28 + bob):
        for x in range(22, 42):
            if getp(cell, x, y)[3] > 200:
                setp(cell, x, y, hood_hi if y < 18 + bob else hood)
    for x in range(24, 40):
        setp(cell, x, 14 + bob, OUTLINE)


def draw_skeleton_skull_down(cell, pal, bob=0):
    bone = (*pal["hi"], 255)
    bone_m = (*pal["mid"], 255)
    bone_s = (*pal["shade"], 255)
    sock = (*pal["socket"], 255)
    # clear face skin area and redraw skull
    for y in range(18 + bob, 32 + bob):
        for x in range(25, 39):
            if getp(cell, x, y)[3] > 200:
                setp(cell, x, y, bone_m if y < 24 + bob else bone)
    # skull dome highlight
    paint_rect(cell, 28, 18 + bob, 35, 20 + bob, bone)
    # sockets
    paint_rect(cell, 27, 24 + bob, 30, 26 + bob, sock)
    paint_rect(cell, 33, 24 + bob, 36, 26 + bob, sock)
    setp(cell, 28, 25 + bob, (*pal["eye"], 255))
    setp(cell, 34, 25 + bob, (*pal["eye"], 255))
    # nasal
    setp(cell, 31, 27 + bob, sock)
    setp(cell, 31, 28 + bob, sock)
    # teeth
    for x in range(28, 35):
        setp(cell, x, 30 + bob, bone)
        if x % 2 == 0:
            setp(cell, x, 31 + bob, bone_s)
    # skull crack + moss
    setp(cell, 32, 20 + bob, (*pal["crack"], 255))
    setp(cell, 32, 21 + bob, (*pal["crack"], 255))
    setp(cell, 26, 22 + bob, (*pal["moss"], 255))
    setp(cell, 26, 23 + bob, (*pal["moss_hi"], 255))
    setp(cell, 37, 23 + bob, (*pal["moss"], 255))
    setp(cell, 38, 24 + bob, (*pal["moss_hi"], 255))
    # ragged wrap accent + amulet
    setp(cell, 29, 44 + bob, (*pal["wrap_hi"], 255))
    setp(cell, 30, 44 + bob, (*pal["wrap_mid"], 255))
    setp(cell, 34, 44 + bob, (*pal["accent"], 255))
    setp(cell, 31, 34 + bob, (*pal["gold"], 255))
    setp(cell, 32, 34 + bob, (*pal["ember"], 255))
    # ribs on torso
    for y in (36 + bob, 38 + bob, 40 + bob):
        for x in range(27, 37):
            if getp(cell, x, y)[3] > 200:
                setp(cell, x, y, bone if (x + y) % 2 == 0 else bone_s)
    # clear soft flesh look on arms → bone
    for y in range(34 + bob, 48 + bob):
        for x in list(range(18, 25)) + list(range(39, 46)):
            r, g, b, a = getp(cell, x, y)
            if a > 200 and (r, g, b) in (
                pal["hi"],
                pal["mid"],
                pal["shade"],
                pal["deep"],
            ):
                setp(cell, x, y, bone_m if y < 40 + bob else bone_s)


def draw_skeleton_skull_side(cell, pal, bob=0):
    bone = (*pal["hi"], 255)
    bone_m = (*pal["mid"], 255)
    sock = (*pal["socket"], 255)
    for y in range(18 + bob, 30 + bob):
        for x in range(26, 40):
            if getp(cell, x, y)[3] > 200:
                setp(cell, x, y, bone if y < 22 + bob else bone_m)
    paint_rect(cell, 34, 23 + bob, 37, 26 + bob, sock)
    setp(cell, 35, 24 + bob, (*pal["eye"], 255))
    # jaw
    paint_rect(cell, 32, 28 + bob, 38, 29 + bob, bone)
    # ribs
    for y in (34 + bob, 36 + bob, 38 + bob):
        for x in range(28, 36):
            if getp(cell, x, y)[3] > 200:
                setp(cell, x, y, bone if x % 2 == 0 else (*pal["shade"], 255))


def draw_skeleton_skull_up(cell, pal, bob=0):
    bone = (*pal["hi"], 255)
    bone_m = (*pal["mid"], 255)
    for y in range(14 + bob, 28 + bob):
        for x in range(24, 40):
            if getp(cell, x, y)[3] > 200:
                setp(cell, x, y, bone if y < 18 + bob else bone_m)
    # occiput shading
    paint_rect(cell, 28, 16 + bob, 35, 18 + bob, (*pal["shade"], 255))


def bob_offset(frame_i: int) -> int:
    # 0,1,2,3 walk cycle vertical bob
    return [0, -1, 0, 1][frame_i % 4]


def shift_cell(cell, dy: int):
    if dy == 0:
        return cell
    out = blank_cell()
    for y in range(64):
        for x in range(64):
            src = getp(cell, x, y - dy)
            out[y][x] = src
    return out


def thicken_side_silhouette(cell, pal):
    """Fill only 1px interior gaps so side turns stay solid — never checker-dither."""
    mid = (*pal["mid"], 255)
    for y in range(18, 50):
        xs = [x for x in range(64) if getp(cell, x, y)[3] > 200]
        if len(xs) < 3:
            continue
        lo, hi = min(xs), max(xs)
        # only close single-pixel holes inside the silhouette span
        for x in range(lo + 1, hi):
            if getp(cell, x, y)[3] < 200:
                left = getp(cell, x - 1, y)[3] > 200
                right = getp(cell, x + 1, y)[3] > 200
                if left and right:
                    setp(cell, x, y, mid)
    return cell


def finalize(cell):
    # replace any remaining pure black
    out = [row[:] for row in cell]
    for y in range(64):
        for x in range(64):
            r, g, b, a = out[y][x]
            if a > 200 and (r, g, b) == (0, 0, 0):
                out[y][x] = OUTLINE
    return out


def build_enemy(kind: str, goblin_sheet, pal):
    sheet = [[TRANSPARENT for _ in range(512)] for _ in range(192)]

    def process(src_idx, dest_idx, facing, chase=False):
        cell = remap_goblin_cell(copy_cell(goblin_sheet, src_idx), pal, kind)
        # 1) features on body  2) close tiny side holes  3) weapons last (never thickened)
        if kind == "orc":
            if facing == "down":
                draw_orc_face_down(cell, pal, bob=0)
                replace_spear_with_club(cell, pal, side=False, chase=chase)
            elif facing == "side":
                draw_orc_face_side(cell, pal, bob=0)
                thicken_side_silhouette(cell, pal)
                replace_spear_with_club(cell, pal, side=True, chase=chase)
            else:
                leather = (*pal["leather"], 255)
                for x in range(26, 38):
                    if getp(cell, x, 30)[3] > 200:
                        setp(cell, x, 30, leather)
                replace_spear_with_club(cell, pal, side=False, chase=chase)
        elif kind == "bandit":
            if facing == "down":
                draw_bandit_hood_down(cell, pal)
                replace_spear_with_dagger(cell, pal, side=False, chase=chase)
            elif facing == "side":
                draw_bandit_hood_side(cell, pal)
                thicken_side_silhouette(cell, pal)
                replace_spear_with_dagger(cell, pal, side=True, chase=chase)
            else:
                draw_bandit_hood_up(cell, pal)
                replace_spear_with_dagger(cell, pal, side=False, chase=chase)
        elif kind == "skeleton":
            if facing == "down":
                draw_skeleton_skull_down(cell, pal)
                replace_spear_with_bone_club(cell, pal, side=False, chase=chase)
            elif facing == "side":
                draw_skeleton_skull_side(cell, pal)
                thicken_side_silhouette(cell, pal)
                replace_spear_with_bone_club(cell, pal, side=True, chase=chase)
            else:
                draw_skeleton_skull_up(cell, pal)
                replace_spear_with_bone_club(cell, pal, side=False, chase=chase)

        if chase:
            cell = shift_cell(cell, -1 if facing != "up" else 0)
            for y in range(64):
                for x in range(64):
                    r, g, b, a = cell[y][x]
                    if a > 200 and (r, g, b) == pal["eye"]:
                        hi = pal["metal_hi"] if kind != "skeleton" else pal["eye"]
                        setp(cell, x, y, (*hi, 255))

        cell = finalize(cell)
        put_cell(sheet, dest_idx, cell)

    # walk down 0-3, up 4-7, side 8-11 from goblin same indices
    for i in range(4):
        process(i, i, "down", chase=False)
        process(4 + i, 4 + i, "up", chase=False)
        process(8 + i, 8 + i, "side", chase=False)
        # chase: use walk sources but mark chase for weapon/lean
        process(i, 12 + i, "down", chase=True)
        process(4 + i, 16 + i, "up", chase=True)
        process(8 + i, 20 + i, "side", chase=True)

    return sheet


def audit(path: Path):
    w, h, px = read_png(path)
    assert (w, h) == (512, 192), (w, h)
    colors = Counter()
    opaque = black = 0
    corner_ok = True
    for idx in range(24):
        col, row = idx % 8, idx // 8
        for yy, xx in ((0, 0), (0, 63), (63, 0), (63, 63)):
            if px[row * 64 + yy][col * 64 + xx][3] > 10:
                corner_ok = False
        for yy in range(64):
            for xx in range(64):
                r, g, b, a = px[row * 64 + yy][col * 64 + xx]
                if a < 200:
                    continue
                opaque += 1
                colors[(r, g, b)] += 1
                if (r, g, b) == (0, 0, 0):
                    black += 1
    pct = 100 * black / max(opaque, 1)
    print(
        f"AUDIT {path.name}: unique={len(colors)} opaque={opaque} "
        f"pure_black={black} ({pct:.1f}%) corners_clear={corner_ok}"
    )
    ok = len(colors) >= 18 and pct <= 5.0 and corner_ok
    # side frame fill check
    for idx in (8, 20):
        col, row = idx % 8, idx // 8
        count = sum(
            1
            for yy in range(64)
            for xx in range(64)
            if px[row * 64 + yy][col * 64 + xx][3] > 200
        )
        print(f"  side frame {idx} opaque={count}")
        if count < 350:
            ok = False
    return ok


def main():
    _, _, goblin = read_png(ROOT / "enemies/goblin/goblin.png")
    enemies = {
        "orc": ORC_PAL,
        "bandit": BANDIT_PAL,
        "skeleton": SKELETON_PAL,
    }
    for kind, pal in enemies.items():
        sheet = build_enemy(kind, goblin, pal)
        out = ROOT / "enemies" / kind / f"{kind}.png"
        write_png(out, 512, 192, sheet)
        # also stash in work/
        write_png(ROOT / "tools/enemy_sprite_harden/work" / f"{kind}_sheet.png", 512, 192, sheet)
        ok = audit(out)
        print(f"  -> {'PASS' if ok else 'RETRY NEEDED'} {out}")


if __name__ == "__main__":
    main()
