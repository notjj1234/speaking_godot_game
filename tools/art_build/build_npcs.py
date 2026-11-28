#!/usr/bin/env python3
"""build_npcs.py — the three NPC walk sheets (600x64 = 15 frames of 40x64).

Every NPC is built on the hero's own frames (player/Sprites/PlayerSprite02.png)
so proportions, face, outline, shading and the walk cycle match the main
character exactly: the hero's head is recoloured (hair, skin, eyes) and his
legs and boots are reused (pants and boots recoloured; behind his cape the
thighs are extended up to the tunic). The cape and sword are dropped; a
hand-drawn body (FRONT / SIDE below) and each role's outfit, hat and props
go on top. Role flavour follows the original NPCs: puffy hair, a beard,
warm chunky clothes.

* Smith / tutorial guide (Daniel): flat mustard cap, bushy beard, rust shirt,
  cream apron, satchel on a strap.              -> npc/sprites/npc_sprite.png
* Trainer / patrol guard (Stefano): steel kettle helmet with a blue plume,
  mail sleeves, blue tabard, spear.             -> npc/sprites/npc_sprite_02.png
* Cook: chef's toque, ginger hair, sage shirt, long cream apron.
                                                -> npc/sprites/npc_sprite_03.png

Frame map (npc/npc.tscn, unchanged): 0 idle_down, 1 idle_up, 2 idle_side,
3-6 walk_down, 7-10 walk_up, 11-14 walk_side. Side frames face right
(npc.gd flips them for left). Feet baseline (bbox bottom, exclusive) = 54.
Each sheet is copied byte-for-byte into gui/dialog_system/sprites/.

    python3.13 tools/art_build/build_npcs.py             # write the sheets
    python3.13 tools/art_build/build_npcs.py out.png     # preview, all stacked
"""
from __future__ import annotations

import os
import shutil
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERO = os.path.join(ROOT, "player/Sprites/PlayerSprite02.png")
CROP_X = 12          # hero 64 px frame -> 40 px NPC frame
FW, FH = 40, 64
HEAD_TOP = 9         # hero idle hair top row
CHIN = 27
LEG_TOP = 40


def hx(s):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255)

OUT = hx("#150918")
H = {k: hx(v) for k, v in dict(
    A="#150918", B="#37946e", C="#356c56", D="#730e1d", E="#ac3232", F="#663931", G="#323c39",
    Hh="#383d3d", I="#8f563b", J="#3b0404", K="#9badb7", L="#515454", M="#696a6a", N="#c7d1d7",
    O="#d95763", P="#ffffff", Q="#eb8e97", R="#a30a0a", S="#ffa88d", T="#3d2024", U="#ffcc9f",
    V="#d9a066", W="#ffe6c4", X="#df7126", Y="#fbf236", Z="#88949a").items()}
INV = {v: k for k, v in H.items()}
GREENS = {"B", "C", "G"}
HAIR = {"D", "E", "J", "O", "Q", "R"}


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3)) + (255,)


def tones(hi, mid, lo):
    hi, mid, lo = hx(hi), hx(mid), hx(lo)
    return {"hi2": mix(hi, (255, 255, 255), 0.35), "hi": hi, "mid": mid, "lo": lo, "lo2": mix(lo, OUT, 0.25)}


hero = Image.open(HERO).convert("RGBA")


def hero_frame(i):
    f = hero.crop(((i % 16) * 64 + CROP_X, (i // 16) * 64, (i % 16) * 64 + CROP_X + FW, (i // 16) * 64 + FH))
    return f


def code(px):
    if px[3] == 0:
        return None
    return INV.get(px, "?")


def hair_top(f):
    for y in range(HEAD_TOP - 3, 30):
        if sum(code(f.getpixel((x, y))) in HAIR for x in range(FW)) >= 4:
            return y
    return HEAD_TOP


def head_layer(f, P):
    """Hero head rows (no ahoge, scarf or sword), recoloured for this NPC."""
    out = Image.new("RGBA", (FW, FH))
    top = hair_top(f)
    xs = [x for y in range(top, top + 14) for x in range(FW) if code(f.getpixel((x, y))) in HAIR]
    x0, x1 = min(xs) - 1, max(xs) + 1
    hair = P["hair"]
    skin = P["skin"]
    for y in range(top - 1, top + CHIN - HEAD_TOP + 1):
        for x in range(x0, x1 + 1):
            c = code(f.getpixel((x, y)))
            if c is None or c == "?":
                continue
            row = y - top + HEAD_TOP
            col = None
            if c in GREENS:
                near = {code(f.getpixel((x + dx, y))) for dx in (-1, 1) if 0 <= x + dx < FW}
                if c == "B" and "K" in near and 20 <= row <= 24:
                    out.putpixel((x, y), P["iris"])
                continue
            if c in HAIR:
                face_row = row >= 23
                neigh = {code(f.getpixel((x + dx, y + dy))) for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                         if 0 <= x + dx < FW and 0 <= y + dy < FH}
                if face_row and c in ("O", "Q") and neigh & {"S", "U"}:
                    col = skin["blush"]
                elif face_row and c == "R" and neigh & {"S", "U"}:
                    col = skin["lo"]
                else:
                    col = {"Q": hair["hi"], "O": hair["hi"], "E": hair["mid"], "R": hair["lo"],
                           "D": hair["lo"], "J": hair["lo2"]}[c]
            elif c == "U":
                col = skin["hi"]
            elif c == "S":
                col = skin["mid"]
            elif c == "W":
                col = skin["hi"]
            elif c == "K":
                if not (20 <= row <= 24):
                    continue
                col = P.get("iris_hi", H["K"])
            elif c in ("N", "P", "T", "F", "I", "V", "X", "Y", "M", "L", "Hh"):
                continue
            else:
                col = H[c]
            out.putpixel((x, y), col)
    return out, top - HEAD_TOP


def legs_layer(f, P, from_behind=False):
    out = Image.new("RGBA", (FW, FH))
    pants, boots = P["pants"], P["boots"]
    m = {"M": pants["hi"], "L": pants["mid"], "Hh": pants["lo"], "V": boots["hi"], "I": boots["mid"],
         "F": boots["lo"], "A": OUT}
    # the cape hides the hero's thighs from behind: legs start where it ends.
    # (From the front and side the thighs are there; only the cape's own pixels drop.)
    start = LEG_TOP
    while from_behind and start < 48 and any(code(f.getpixel((x, start))) in GREENS for x in range(FW)):
        start += 1
    for y in range(start, FH):
        for x in range(FW):
            c = code(f.getpixel((x, y)))
            if c in ("V", "I", "F") and y < 45:
                continue  # the hero's fists, not boots
            if c in m:
                out.putpixel((x, y), m[c])
    # drop cape outline left floating
    px = out.load()
    for y in range(LEG_TOP, FH):
        for x in range(FW):
            if px[x, y][3] and px[x, y][:3] == OUT[:3]:
                keep = any(0 <= x + dx < FW and 0 <= y + dy < FH and px[x + dx, y + dy][3]
                           and px[x + dx, y + dy][:3] != OUT[:3]
                           for dx in (-1, 0, 1) for dy in (-1, 0, 1))
                if not keep:
                    px[x, y] = (0, 0, 0, 0)
    if start > LEG_TOP + 1:
        _extend_thighs(out, start)
    return out


def _extend_thighs(out, start):
    """Behind the cape the hero has no thighs: run each leg column straight up to the hem."""
    px = out.load()
    is_pants = lambda p: p[3] and p[:3] != OUT[:3]
    tops = {}
    for x in range(FW):
        for y in range(start, min(start + 5, FH)):
            if is_pants(px[x, y]):
                tops[x] = y
                break
    for x, ty in tops.items():
        for y in range(LEG_TOP, ty):
            px[x, y] = px[x, ty]
    for x, ty in tops.items():
        for nx in (x - 1, x + 1):
            if nx not in tops and 0 <= nx < FW:
                for y in range(LEG_TOP, ty + 1):
                    if not is_pants(px[nx, y]):
                        px[nx, y] = OUT

# ---------------------------------------------------------------- bodies
# (x, text) rows; absolute NPC pixels at the idle pose, row index = key.
FRONT = {
    24: (15, "ooaabbccoo"),
    25: (14, "oaabbbbbbcco"),
    26: (13, "oaabbbbbbbbcco"),
    27: (12, "oaabbbbbbbbbbcco"),
    28: (11, "oaabbbbbbbbbbbbcco"),
    29: (10, "oaabbbbbbbbbbbbbbcco"),
    30: (10, "oaabbbbbbbbbbbbbbcco"),
    31: (10, "oaabobbbbbbbbbbocbco"),
    32: (10, "oaaoabbbbbbbbbbcocco"),
    33: (10, "oaaoabbbbbbbbbbcocco"),
    34: (10, "oaaoabbcbbbbcbbcocco"),
    35: (10, "oaaoabbcbbbbcbbcocco"),
    36: (9, "okkkoabbbbbbbbbbcolmmo"),
    37: (9, "okkloggghhhyyhhhiolmmo"),
    38: (9, "ookkoabbbbbbbbbbcommoo"),
    39: (10, "oooabbbbbbbbbbbbcooo"),
    40: (12, "occcccccccccccco"),
    41: (12, "oooooooooooooooo"),
}
NECK_BACK = {r: (17, "okllmo") for r in range(21, 24)}
SIDE = {
    24: (18, "oooooo"),
    25: (17, "oabbbbco"),
    26: (16, "oabbbbbbco"),
    27: (16, "oabbbbbbbco"),
    28: (16, "oabbbbbbbbco"),
    29: (16, "oabbbbbbbbco"),
    30: (16, "oabbbbbbbbco"),
    31: (16, "oabbbbbbbbco"),
    32: (16, "oabbbbbbbbco"),
    33: (16, "oabbbbbbcbco"),
    34: (16, "oabbbbbbcbco"),
    35: (16, "oabbbbbbbbco"),
    36: (16, "oabbbbbbbbco"),
    37: (16, "ogghhhhhhyho"),
    38: (16, "oabbbbbbbbco"),
    39: (16, "oabbbbbbbbco"),
    40: (16, "occcccccccco"),
    41: (16, "oooooooooooo"),
}
SIDE_ARM = {27: (19, "oaao"), 28: (19, "oabo"), 29: (19, "oabo"), 30: (19, "oabo"), 31: (19, "oabo"),
            32: (19, "oabo"), 33: (19, "oabo"), 34: (19, "oabo"), 35: (19, "oabo"), 36: (18, "okklo"),
            37: (18, "okkmo"), 38: (18, "ooooo")}


# mid tone -> (light, dark) neighbours for the fold streaks
FOLDS = {"b": ("a", "c"), "e": ("d", "f"), "q": ("p", "r"), "v": ("u", "w"),
         "p": ("p", "q"), "d": ("d", "e"), "z": ("z", "n"), "a": ("a", "b"), "c": ("b", "c")}


def put(img, rows, pal, dx=0, dy=0):
    for y, (x0, text) in rows.items():
        for i, ch in enumerate(text):
            if ch == ".":
                continue
            X, Y = x0 + i + dx, y + dy
            if ch in FOLDS:
                if (X * 3 + Y // 3) % 5 == 0:
                    ch = FOLDS[ch][1]
                elif (X * 5 + Y // 2) % 7 == 0:
                    ch = FOLDS[ch][0]
            if 0 <= X < FW and 0 <= Y < FH:
                img.putpixel((X, Y), pal[ch] if ch != "_" else (0, 0, 0, 0))


# hero frame per NPC frame: idle down/up/side, walk down x4, up x4, side x4
HERO_OF = [0, 3, 6, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
VIEW_OF = ["down", "up", "side"] + ["down"] * 4 + ["up"] * 4 + ["side"] * 4
PHASE_OF = [None, None, None, 0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3]
ARM_SWING = {None: (0, 0), 0: (1, 0), 1: (0, 0), 2: (-1, 0), 3: (0, 0)}


def palette(P):
    pal = {"o": OUT, "_": (0, 0, 0, 0)}
    for letters, key in (("abc", "shirt"), ("def", "cloth"), ("ghi", "leather"), ("pqr", "hat"),
                         ("uvw", "beard"), ("st", "plume"), ("klm", "skin")):
        mat = P.get(key)
        if mat is None:
            continue
        for ch, tone in zip(letters, ("hi", "mid", "lo")):
            pal[ch] = mat[tone]
    pal.update(P.get("extra", {}))
    return pal


def build_frame(n, P, design):
    f = hero_frame(HERO_OF[n])
    view, phase = VIEW_OF[n], PHASE_OF[n]
    pal = palette(P)
    img = Image.new("RGBA", (FW, FH))
    head, top = head_layer(f, P)
    dy = top - 1
    design("behind", img, view, phase, dy, pal)
    img.alpha_composite(legs_layer(f, P, view == "up"))
    if view == "side":
        put(img, SIDE, pal, dy=dy)
    else:
        if view == "up":
            put(img, NECK_BACK, pal, dy=dy)
        put(img, FRONT, pal, dy=dy)
    design("torso", img, view, phase, dy, pal)
    if view == "side":
        sx, _ = ARM_SWING[phase]
        design("arm_under", img, view, phase, dy, pal)
        if not design("arm", img, view, phase, dy, pal):  # a design may draw its own arm
            put(img, SIDE_ARM, pal, dx=sx, dy=dy)
    img.alpha_composite(head)
    design("head", img, view, phase, dy, pal)
    design("front", img, view, phase, dy, pal)
    return img


def build_sheet(P, design):
    sheet = Image.new("RGBA", (FW * 15, FH))
    for n in range(15):
        sheet.alpha_composite(build_frame(n, P, design), (n * FW, 0))
    return sheet


def skin(hi, mid, lo):
    return dict(hi=hx(hi), mid=hx(mid), lo=hx(lo), hi2=mix(hx(hi), (255, 255, 255), 0.5),
                blush=mix(hx(mid), hx("#e05a5a"), 0.45))


# ------------------------------------------------------------- smith / guide
SMITH = {
    "hair": tones("#a8663a", "#7a4426", "#5a3018"), "skin": skin("#f4c9a0", "#d99a6c", "#a8653f"),
    "iris": hx("#5a3420"), "iris_hi": hx("#c8b8a0"),
    "shirt": tones("#de7840", "#ad5228", "#6f321a"), "cloth": tones("#f6ecd0", "#d2c096", "#958160"),
    "leather": tones("#94643c", "#6c4628", "#4e3220"), "hat": tones("#e8b64a", "#b88328", "#7a5216"),
    "beard": tones("#8a5030", "#643820", "#40220f"),
    "pants": tones("#7e6a48", "#5e4c34", "#463824"), "boots": tones("#94643c", "#6c4628", "#4e3220"),
    "extra": {"y": hx("#eeb52f")},
}
CAP_FRONT = {
    7: (14, "oooooooooooo"),
    8: (12, "ooppppqqqqqqrroo"),
    9: (11, "oppqqqqqqqqqqqqrro"),
    10: (11, "opqqqqqqqqqqqqqrro"),
    11: (10, "oopqqqqqqqqqqqqqqroo"),
    12: (10, "orrrrrrrrrrrrrrrrrro"),
}
CAP_BACK = {
    7: (14, "oooooooooooo"),
    8: (12, "ooppppqqqqqqrroo"),
    9: (11, "oppqqqqqqqqqqqqrro"),
    10: (11, "opqqqqqqqqqqqqqrro"),
    11: (11, "oqqqqqqqqqqqqqqrro"),
    12: (11, "orrrrrrrrrrrrrrrro"),
}
CAP_SIDE = {
    7: (16, "oooooooooo"),
    8: (14, "ooppqqqqqqroo"),
    9: (13, "oppqqqqqqqqqrro"),
    10: (13, "opqqqqqqqqqqqro"),
    11: (13, "oqqqqqqqqqqqqrroooo"),
    12: (13, "orrrrrrrrrrrrrrrrrro"),
}
BEARD_FRONT = {
    24: (14, "ow........wo"),
    25: (14, "ovw.ouuo.wvo"),
    26: (14, "ovvwuvvuwvvo"),
    27: (14, "ouvvvvvvvvwo"),
    28: (15, "ouvvvvvvwo"),
    29: (16, "ovvvvvwo"),
    30: (17, "owwwwo"),
    31: (18, "oooo"),
}
BEARD_SIDE = {
    23: (22, "ow"),
    24: (22, "ovw..."),
    25: (22, "ovvouuo"),
    26: (21, "ouvvvvvo"),
    27: (21, "ouvvvvvo"),
    28: (21, "ovvvvvwo"),
    29: (22, "ovvvwo"),
    30: (23, "owwo"),
    31: (24, "oo"),
}
APRON_FRONT = {
    27: (16, "oddddeeo"),
    28: (16, "odeeeeef"),
    29: (16, "odeeeeef"),
    30: (16, "odeeeeef"),
    31: (16, "odeeeeef"),
    32: (16, "odeeeeef"),
    33: (16, "odefffef"),
    34: (16, "odeeeeef"),
    35: (16, "odeeeeef"),
    37: (15, "oddeeeeefo"),
    38: (14, "oddeeeeeeefo"),
    39: (14, "odeeeeeeeefo"),
    40: (14, "offffffffffo"),
}
STRAP_FRONT = {27 + k: (24 - k, "hi") for k in range(10)}
STRAP_BACK = {27 + k: (14 + k, "ih") for k in range(10)}
BAG = {35: (5, "oooooo"), 36: (5, "oghhho"), 37: (5, "ohhhio"), 38: (5, "oiyiio"), 39: (5, "ohhhio"),
       40: (5, "ohhiio"), 41: (5, "oooooo")}


def smith(stage, img, view, phase, dy, pal):
    if stage == "behind":
        if view == "down":
            put(img, BAG, pal, dx=1, dy=dy)
        elif view == "up":
            put(img, BAG, pal, dx=22, dy=dy)
        else:
            put(img, BAG, pal, dx=9, dy=dy)
    elif stage == "torso":
        if view == "down":
            put(img, APRON_FRONT, pal, dy=dy)
            put(img, STRAP_FRONT, pal, dy=dy)
        elif view == "up":
            put(img, STRAP_BACK, pal, dy=dy)
            put(img, {36: (18, "odeo"), 37: (17, "odeefo"), 38: (18, "offo")}, pal, dy=dy)
        else:
            put(img, {27 + k: (24, "odef") for k in range(10)}, pal, dy=dy)
            put(img, {37: (24, "oddeo"), 38: (24, "odeefo"), 39: (24, "odeefo"), 40: (24, "offffo")}, pal, dy=dy)
            put(img, {27 + k: (21 - (k // 3), "h") for k in range(10)}, pal, dy=dy)
    elif stage == "head":
        if view == "down":
            put(img, CAP_FRONT, pal, dy=dy)
            put(img, BEARD_FRONT, pal, dy=dy)
        elif view == "up":
            put(img, CAP_BACK, pal, dy=dy)
        else:
            put(img, CAP_SIDE, pal, dy=dy)
            put(img, BEARD_SIDE, pal, dy=dy)


# ------------------------------------------------------------- guard / trainer
GUARD = {
    "hair": tones("#7a6456", "#5a463c", "#43342c"), "skin": skin("#eab792", "#c48866", "#8c573c"),
    "iris": hx("#3c5a7a"), "iris_hi": hx("#b8c8d8"),
    "shirt": tones("#b4c0cc", "#7e8c9a", "#4e5a68"), "cloth": tones("#5a8ad0", "#3a62a0", "#223f70"),
    "leather": tones("#86644a", "#624834", "#4a3626"), "hat": tones("#e2ebf2", "#a3b3c3", "#617183"),
    "plume": tones("#5a8ad0", "#3a62a0", "#223f70"),
    "pants": tones("#6e7a94", "#505a70", "#3c4456"), "boots": tones("#86644a", "#624834", "#4a3626"),
    "extra": {"y": hx("#d6ac4a"), "x": hx("#f4f8fb"), "z": hx("#a8805a"), "n": hx("#755638")},
}
HELM_FRONT = {
    2: (18, "oooo"),
    3: (17, "osstto"),
    4: (17, "osstto"),
    5: (18, "osto"),
    6: (14, "ooooostooooo"),
    7: (12, "ooppppqqqqqqrroo"),
    8: (11, "oppqqqqqqqqqqqqrro"),
    9: (11, "opqqqqqqqqqqqqqrro"),
    10: (11, "oqqqqqqqqqqqqqqrro"),
    11: (10, "oopqqqqqqqqqqqqqqroo"),
    12: (10, "oppppypppppppypppppo"),
    13: (10, "orrrrrrrrrrrrrrrrrro"),
}
HELM_SIDE = {
    2: (19, "ooo"),
    3: (17, "osstto"),
    4: (16, "osstto"),
    5: (16, "osto"),
    6: (16, "ooooooooooo"),
    7: (14, "ooppqqqqqqroo"),
    8: (13, "oppqqqqqqqqqrro"),
    9: (13, "opqqqqqqqqqqqro"),
    10: (13, "oqqqqqqqqqqqqro"),
    11: (12, "oopqqqqqqqqqqqrroo"),
    12: (12, "oppppypppppypppppo"),
    13: (12, "orrrrrrrrrrrrrrrro"),
}
TABARD = {
    26: (15, "oddddeeeeo"),
    27: (15, "odeeeeeeef"),
    28: (15, "odeeeeeeef"),
    29: (15, "odeeexeeef"),
    30: (15, "odeexxxeef"),
    31: (15, "odeeexeeef"),
    32: (15, "odeeexeeef"),
    33: (15, "odeeeeeeef"),
    34: (15, "odeeeeeeef"),
    35: (15, "odeeeeeeef"),
    36: (15, "odeeeeeeef"),
    38: (15, "odeeeeeeef"),
    39: (15, "odeeeeeeef"),
    40: (15, "offfoofffo"),
}
TABARD_BACK = {r: v for r, v in TABARD.items()}
TABARD_BACK.update({29: (15, "odeeeeeeef"), 30: (15, "odeeeeeeef"), 31: (15, "odeeeeeeef"), 32: (15, "odeeeeeeef")})
TABARD_SIDE = {r: (21, "deeef") for r in range(26, 37)}
TABARD_SIDE.update({38: (21, "deeef"), 39: (21, "deeef"), 40: (21, "fffoo")})
SPEAR_TIP = {2: (0, "o"), 3: (-1, "oxo"), 4: (-1, "oxp"), 5: (-1, "oxp"), 6: (-1, "opr"), 7: (-1, "oro"), 8: (-1, "oyo")}


# Side view: forearm forward to a fist around the spear at x 31-34.
GUARD_ARM_SIDE = {27: (19, "oaao"), 28: (19, "oabo"), 29: (19, "oabo"), 30: (19, "oabo"),
                  31: (19, "oaboooooooo"), 32: (19, "oaaaaaaaaaab"), 33: (19, "obbbbbbbbbbc"),
                  34: (20, "oooooooooooo")}
GUARD_FIST_SIDE = {31: (29, "oooo"), 32: (29, "okklo"), 33: (29, "oklmo"), 34: (29, "okmmo"), 35: (30, "ooo")}


def spear(img, pal, x, dy):
    put(img, {r: (x - 1, "onzo" if r % 5 == 0 else "ozno") for r in range(9, 53)}, pal, dy=0)
    put(img, SPEAR_TIP, pal, dx=x, dy=0)


def guard(stage, img, view, phase, dy, pal):
    if stage == "behind" and view == "up":
        spear(img, pal, 10, dy)
    elif stage == "torso":
        if view == "down":
            put(img, TABARD, pal, dy=dy)
        elif view == "up":
            put(img, TABARD_BACK, pal, dy=dy)
        else:
            put(img, TABARD_SIDE, pal, dy=dy)
    elif stage == "arm" and view == "side":
        put(img, GUARD_ARM_SIDE, pal, dy=dy)
        return True
    elif stage == "head":
        if view == "side":
            put(img, HELM_SIDE, pal, dy=dy)
            put(img, {r: (17, "pr") for r in range(8, 12)}, pal, dy=dy)  # ridge
        else:
            put(img, HELM_FRONT, pal, dy=dy)
            put(img, {r: (19, "pr") for r in range(8, 12)}, pal, dy=dy)  # ridge
    elif stage == "front" and view == "side":
        # held out in front, clear of the face (a shaft at the body's centre ran through it)
        spear(img, pal, 32, dy)
        put(img, GUARD_FIST_SIDE, pal, dy=dy)
    elif stage == "front" and view == "down":
        spear(img, pal, 29, dy)
        put(img, {36: (27, "olmmo"), 37: (27, "olmmo"), 38: (27, "ooooo")}, pal, dy=dy)


# ------------------------------------------------------------------- cook
COOK = {
    "hair": tones("#d88444", "#a85a28", "#6e3616"), "skin": skin("#f0bf98", "#cf9270", "#965a40"),
    "iris": hx("#4a6a3a"), "iris_hi": hx("#c8d8b8"),
    "shirt": tones("#a8c486", "#789a5a", "#4c663a"), "cloth": tones("#f8f0dc", "#d8caa8", "#9c8c6a"),
    "leather": tones("#8a5a36", "#603c22", "#3c2414"), "hat": tones("#ffffff", "#e2dccf", "#aaa293"),
    "beard": tones("#d88444", "#a85a28", "#6e3616"),
    "pants": tones("#7a6652", "#5a4a3c", "#44382e"), "boots": tones("#94643c", "#6c4628", "#4e3220"),
    "extra": {"y": hx("#d6ac4a")},
}
TOQUE_FRONT = {
    0: (14, "ooo.oooooo"),
    1: (13, "oppoopppppqoo"),
    2: (12, "oppppppppppqqqo."),
    3: (12, "opppppppppqqqqro"),
    4: (12, "opppppppppqqqqro"),
    5: (12, "oqpppppppqqqqrro"),
    6: (13, "oqqqqqqqqqqrro"),
    7: (13, "orqqqqqqqqrrro"),
    8: (12, "oopppppppppqqroo"),
    9: (11, "oppppppppppppqqro"),
    10: (11, "opppppppppppqqqro"),
    11: (11, "oqqqqqqqqqqqqqrro"),
    12: (11, "orrrrrrrrrrrrrrro"),
}
TOQUE_SIDE = {r: (x + 2, t) for r, (x, t) in TOQUE_FRONT.items()}
COOK_APRON = {
    28: (15, "oddddeeeeo"),
    29: (15, "odeeeeeeef"),
    30: (15, "odeeeeeeef"),
    31: (15, "odeeeeeeef"),
    32: (15, "odeeeeeeef"),
    33: (14, "oddeeeeeeefo"),
    34: (13, "oddeeeeeeeeefo"),
    35: (13, "odeeeeeeeeeefo"),
    36: (13, "odeeffffffeefo"),
    38: (13, "odeeeeeeeeeefo"),
    39: (12, "oddeeeeeeeeeefo"),
    40: (12, "odeeeeeeeeeeeefo"),
    41: (12, "offffffffffffffo"),
    42: (13, "oooooooooooooo"),
}


def cook(stage, img, view, phase, dy, pal):
    if stage == "torso":
        if view == "down":
            put(img, COOK_APRON, pal, dy=dy)
            put(img, {38: (17, "fffff"), 39: (17, "f...f"), 40: (17, "f...f")}, pal, dy=dy)  # pocket
        elif view == "up":
            put(img, {26 + k: (14 + k, "d") for k in range(10)}, pal, dy=dy)  # apron straps cross the back
            put(img, {26 + k: (25 - k, "e") for k in range(10)}, pal, dy=dy)
            put(img, {36: (18, "odeo"), 37: (17, "odeefo"), 38: (18, "offo")}, pal, dy=dy)
        else:
            put(img, {r: (23, "deeef") for r in range(28, 37)}, pal, dy=dy)
            put(img, {38: (23, "deeefo"), 39: (23, "deeeefo"), 40: (23, "deeeefo"), 41: (23, "ffffffo"), 42: (23, "oooooo")}, pal, dy=dy)
    elif stage == "head":
        if view == "side":
            put(img, TOQUE_SIDE, pal, dy=dy)
            put(img, {r: (x, "q") for r in range(2, 8) for x in (17, 21, 25)}, pal, dy=dy)  # pleats
        else:
            put(img, TOQUE_FRONT, pal, dy=dy)
            put(img, {r: (x, "q") for r in range(2, 8) for x in (15, 19, 23)}, pal, dy=dy)  # pleats


TARGETS = [(SMITH, smith, "npc/sprites/npc_sprite.png"), (GUARD, guard, "npc/sprites/npc_sprite_02.png"),
           (COOK, cook, "npc/sprites/npc_sprite_03.png")]


def rp(path):
    return os.path.join(ROOT, path)


if __name__ == "__main__":
    if len(sys.argv) > 1:          # preview mode: write all sheets stacked to a scratch path
        o = Image.new("RGBA", (600, 64 * len(TARGETS)))
        for row, (P, fn, _path) in enumerate(TARGETS):
            o.paste(build_sheet(P, fn), (0, 64 * row))
        o.save(sys.argv[1])
        print("✅ wrote preview", sys.argv[1])
    else:
        for P, fn, path in TARGETS:
            sheet = build_sheet(P, fn)
            assert sheet.size == (600, 64)
            sheet.save(rp(path))
            dup = path.replace("npc/sprites/", "gui/dialog_system/sprites/")
            shutil.copyfile(rp(path), rp(dup))
            print("✅ wrote", path, "and copied to", dup)
