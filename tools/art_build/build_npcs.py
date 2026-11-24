"""build_npcs.py — two distinct NPC walk sheets (600x64 = 15 frames of 40x64).

Frame map (npc/npc.tscn, unchanged): 0 idle_down, 1 idle_up, 2 idle_side,
3-6 walk_down, 7-10 walk_up, 11-14 walk_side. Side frames face right
(npc.gd flips them for left). Feet baseline (bbox bottom, exclusive) = 54.

* Daniel Devito — tutorial guide, civilian: stout build, mustard flat cap,
  rust shirt, cream apron, leather satchel on the hip with a chest strap,
  moustache. Warm palette.          -> npc/sprites/npc_sprite.png
* Stefano — patrol guard: narrower and taller, steel cap with nasal guard and
  a blue plume, blue tabard with a silver emblem, mail sleeves, spear carried
  upright. Cool palette.            -> npc/sprites/npc_sprite_02.png

Each sheet is copied byte-for-byte into gui/dialog_system/sprites/.
"""
from __future__ import annotations

import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pixrig import Mat, Rig, m_ellipse, m_limb, m_line, m_poly, m_rect, rp, sheet  # noqa: E402
from humanoid import Pose  # noqa: E402

OUT = "#150918"
EYE = "#24161a"

DANIEL = {
    "skin": Mat("#f4c9a0", "#d99a6c", "#a8653f"),
    "hair": Mat("#9a5a32", "#6b3b1f", "#432313"),
    "cap": Mat("#e8b64a", "#b88328", "#7a5216"),
    "shirt": Mat("#de7840", "#ad5228", "#6f321a"),
    "apron": Mat("#f6ecd0", "#d2c096", "#958160"),
    "bag": Mat("#b07c44", "#80562c", "#50341a"),
    "legs": Mat("#74603f", "#53432c", "#35291b"),
}
STEFANO = {
    "skin": Mat("#eab792", "#c48866", "#8c573c"),
    "hair": Mat("#4a3a34", "#30241f", "#1c1412"),
    "steel": Mat("#d2dde6", "#93a3b3", "#586777"),
    "tabard": Mat("#5a8ad0", "#3a62a0", "#223f70"),
    "leather": Mat("#7a6a5e", "#54483f", "#342c27"),
    "legs": Mat("#66718a", "#474f62", "#2e3442"),
    "wood": Mat("#a8805a", "#755638", "#4a3522"),
}


class NPose(Pose):
    def __init__(self, d, phase, walking):
        super().__init__(d, phase, False)
        self.g = 52
        if not walking:
            self.bob, self.s = 0, 0
        self.walking = walking

    def front_feet(self):
        if not self.walking:
            return (0, 0)
        return {0: (0, 2), 1: (0, 1), 2: (2, 0), 3: (1, 0)}[self.p]

    def side_feet(self):
        if not self.walking:
            return (1, 0, -1, 0)
        return {0: (4, 0, -4, 0), 1: (0, 0, 1, 3), 2: (-4, 0, 4, 0), 3: (1, 3, 0, 0)}[self.p]


FRAMES = [("down", 0, False), ("up", 0, False), ("side", 0, False)] + \
         [("down", p, True) for p in range(4)] + [("up", p, True) for p in range(4)] + [("side", p, True) for p in range(4)]


# ------------------------------------------------------------ shared body ---
def legs_front(r, P, cx, M, legmat, shoemat, gap=3):
    lr, rr = P.front_feet()
    for lx, raise_ in ((cx - gap, lr), (cx + gap, rr)):
        fy = P.g - raise_
        r.part(m_rect(lx - 2, int(P.y(10)), lx + 1, fy - 2), legmat)
        r.part(m_rect(lx - 2, fy - 2, lx + 2 if lx > cx else lx + 1, fy), shoemat)


def legs_side(r, P, cx, legmat, shoemat):
    ndx, nr, fdx, frs = P.side_feet()
    r.part(m_limb(cx, P.y(10), cx + fdx, P.g - frs - 2, 4), legmat, tone="lo")
    r.part(m_rect(cx + fdx - 1, P.g - frs - 2, cx + fdx + 3, P.g - frs), shoemat, tone="lo")
    r.part(m_limb(cx, P.y(10), cx + ndx, P.g - nr - 2, 4), legmat)
    r.part(m_rect(cx + ndx - 1, P.g - nr - 2, cx + ndx + 3, P.g - nr), shoemat)


def face_front(r, cx, hy, skin, mouth=True):
    r.dot({(cx - 3, hy + 1), (cx + 3, hy + 1), (cx - 3, hy + 2), (cx + 3, hy + 2)}, EYE)
    r.dot({(cx - 4, hy + 4), (cx + 4, hy + 4)}, skin.lo)            # cheeks
    if mouth:
        r.dot({(cx, hy + 5), (cx + 1, hy + 5)}, skin.lo)


# ------------------------------------------------------------------ Daniel ---
def daniel(P: NPose):
    M = DANIEL
    r = Rig(40, 64, OUT)
    y = P.y
    cx = 20
    ls, rs = P.arm_swing() if P.walking else (0, 0)
    if P.d in ("down", "up"):
        back = P.d == "up"
        legs_front(r, P, cx, M, M["legs"], M["bag"])
        # satchel hangs on the viewer's left from the front (right from behind)
        bx = cx - 11 if not back else cx + 11
        # arms first so the stout torso overlaps the shoulders
        for sx, sw in ((-1, ls), (1, rs)):
            hand = (cx + sx * 10, int(y(11) + sw))
            r.part(m_limb(cx + sx * 7, y(20), hand[0], hand[1] - 1, 4, 3), M["shirt"])
            r.part(m_ellipse(hand[0], hand[1], 1.5, 1.5), M["skin"])
        torso = m_poly([(cx - 8, y(9)), (cx + 8, y(9)), (cx + 9, y(17)), (cx + 7, y(22)), (cx - 7, y(22)), (cx - 9, y(17))])
        r.part(torso, M["shirt"])
        if not back:
            r.part(m_poly([(cx - 4, y(19)), (cx + 4, y(19)), (cx + 6, y(10)), (cx + 6, y(6)), (cx - 6, y(6)), (cx - 6, y(10))]), M["apron"])
            r.dot({(cx - 2, int(y(14))), (cx + 2, int(y(14)))}, M["apron"].lo)     # pocket seams
            r.part(m_line(cx + 6, y(21), cx - 8, y(11)), M["bag"])                 # chest strap
        else:
            r.part(m_line(cx - 6, y(21), cx + 8, y(11)), M["bag"])
            r.part(m_rect(cx - 2, int(y(12)), cx + 2, int(y(10))), M["apron"])      # apron bow at the back
            r.dot({(cx, int(y(11)))}, M["apron"].lo)
        r.part(m_rect(bx - 3, int(y(14)), bx + 3, int(y(8))), M["bag"])
        r.part(m_rect(bx - 3, int(y(14)), bx + 3, int(y(12))), M["bag"], tone="hi")  # flap
        r.dot({(bx, int(y(12)))}, M["cap"].hi)                                          # brass buckle
        # head
        hy = int(y(31))
        r.part(m_ellipse(cx, hy, 8, 8), M["skin"])
        if not back:
            r.part(m_rect(cx - 8, hy - 3, cx - 7, hy + 2) | m_rect(cx + 7, hy - 3, cx + 8, hy + 2), M["hair"])  # sideburns
            face_front(r, cx, hy, M["skin"], mouth=False)
            r.part(m_rect(cx - 3, hy + 4, cx + 3, hy + 5) - {(cx - 3, hy + 5), (cx + 3, hy + 5)}, M["hair"])    # moustache
            r.dot({(cx, hy + 3)}, M["skin"].lo)
        else:
            r.part(m_ellipse(cx, hy + 1, 8, 6), M["hair"])
        # flat cap: dome + brim towards the viewer
        r.part(m_ellipse(cx, hy - 6, 9, 5), M["cap"])
        if not back:
            r.part(m_rect(cx - 8, hy - 2, cx + 8, hy - 2), M["cap"], tone="lo")
        r.dot({(cx - 3, hy - 9), (cx - 2, hy - 10)}, M["cap"].hi)
    else:
        legs_side(r, P, cx - 1, M["legs"], M["bag"])
        sw = -P.s * 3 if P.walking else 0
        r.part(m_limb(cx, y(20), cx - 2 - sw, y(12), 3), M["shirt"], tone="lo")             # far arm
        r.part(m_rect(cx - 12, int(y(15)), cx - 5, int(y(8))), M["bag"])                    # satchel behind hip
        r.part(m_rect(cx - 12, int(y(15)), cx - 5, int(y(13))), M["bag"], tone="hi")
        torso = m_poly([(cx - 6, y(9)), (cx + 5, y(9)), (cx + 7, y(16)), (cx + 4, y(22)), (cx - 5, y(22)), (cx - 7, y(16))])
        r.part(torso, M["shirt"])
        r.part(m_poly([(cx + 3, y(19)), (cx + 6, y(19)), (cx + 8, y(9)), (cx + 7, y(6)), (cx + 3, y(6))]), M["apron"])
        r.part(m_line(cx + 4, y(21), cx - 5, y(12)), M["bag"])
        hy = int(y(31))
        r.part(m_ellipse(cx + 1, hy, 7, 8), M["skin"])
        r.part(m_ellipse(cx - 2, hy + 1, 4, 5), M["hair"])
        r.part(m_rect(cx + 7, hy + 1, cx + 9, hy + 3), M["skin"])                            # nose
        r.dot({(cx + 5, hy), (cx + 5, hy + 1)}, EYE)
        r.part(m_rect(cx + 5, hy + 4, cx + 8, hy + 5), M["hair"])                           # moustache
        r.part(m_ellipse(cx, hy - 6, 8, 5), M["cap"])
        r.part(m_rect(cx + 4, hy - 2, cx + 11, hy - 2), M["cap"], tone="lo")               # brim forward
        r.dot({(cx - 2, hy - 9), (cx - 1, hy - 10)}, M["cap"].hi)
        hand = (cx + 2 + sw, int(y(11)))
        r.part(m_limb(cx + 1, y(20), hand[0], hand[1] - 1, 4, 3), M["shirt"])
        r.part(m_ellipse(hand[0], hand[1], 1.5, 1.5), M["skin"])
    return r.render()


# ----------------------------------------------------------------- Stefano ---
BRASS = "#d6ac4a"


def spear(r, M, x, y_butt, y_tip):
    r.part(m_line(x, y_butt, x, y_tip + 3), M["wood"])
    r.part(m_poly([(x, y_tip), (x + 1.5, y_tip + 3), (x, y_tip + 5), (x - 1.5, y_tip + 3)]), M["steel"])
    r.dot({(x, y_tip + 6)}, BRASS)                                                    # brass collar


def stefano(P: NPose):
    M = STEFANO
    r = Rig(40, 64, OUT)
    y = P.y
    cx = 19
    ls, rs = P.arm_swing() if P.walking else (0, 0)
    if P.d in ("down", "up"):
        back = P.d == "up"
        legs_front(r, P, cx, M, M["legs"], M["leather"], gap=3)
        sx_sp = 1 if not back else -1                     # spear hand: viewer right from the front
        free = -sx_sp
        fw = ls if free < 0 else rs
        hand = (cx + free * 10, int(y(11) + fw))
        r.part(m_limb(cx + free * 6, y(20), hand[0], hand[1] - 1, 3), M["steel"])          # mail sleeve
        r.part(m_ellipse(hand[0], hand[1], 1.5, 1.5), M["skin"])
        torso = m_poly([(cx - 6, y(9)), (cx + 6, y(9)), (cx + 7, y(19)), (cx + 6, y(22)), (cx - 6, y(22)), (cx - 7, y(19))])
        r.part(torso, M["steel"])
        tab = m_rect(cx - 5, int(y(21)), cx + 5, int(y(4)))
        r.part(tab, M["tabard"])
        r.part(m_rect(cx - 6, int(y(12)), cx + 6, int(y(11))), M["leather"])               # belt
        if not back:
            r.dot({(cx, int(y(18))), (cx - 1, int(y(17))), (cx + 1, int(y(17))), (cx, int(y(16))), (cx, int(y(15)))}, M["steel"].hi)  # emblem
            r.dot({(cx, int(y(12))), (cx, int(y(11)))}, BRASS)                               # brass buckle
        sp_x = cx + sx_sp * 11
        sp_hand = (sp_x, int(y(16)))
        spear(r, M, sp_x, P.g - 1, 7)
        r.part(m_limb(cx + sx_sp * 6, y(20), sp_hand[0], sp_hand[1] + 1, 3), M["steel"])
        r.part(m_ellipse(sp_hand[0], sp_hand[1], 1.5, 1.5), M["skin"])
        hy = int(y(29))
        r.part(m_ellipse(cx, hy, 7, 7), M["skin"])
        if not back:
            r.part(m_rect(cx - 7, hy - 1, cx - 6, hy + 3) | m_rect(cx + 6, hy - 1, cx + 7, hy + 3), M["hair"])
            face_front(r, cx, hy, M["skin"])
        else:
            r.part(m_ellipse(cx, hy + 1, 7, 6), M["hair"])
        # steel cap with rim, nasal guard and plume
        r.part(m_ellipse(cx, hy - 3, 8, 5), M["steel"])
        r.part(m_rect(cx - 8, hy - 1, cx + 8, hy), M["steel"], tone="lo")
        if not back:
            r.part(m_rect(cx, hy, cx, hy + 3), M["steel"], tone="mid")
        r.part(m_ellipse(cx, hy - 10, 1.5, 2.5), M["tabard"])
    else:
        legs_side(r, P, cx - 1, M["legs"], M["leather"])
        sw = -P.s * 3 if P.walking else 0
        r.part(m_limb(cx, y(20), cx - 3 - sw, y(12), 3), M["steel"], tone="lo")
        torso = m_poly([(cx - 5, y(9)), (cx + 4, y(9)), (cx + 5, y(19)), (cx + 3, y(22)), (cx - 4, y(22)), (cx - 6, y(19))])
        r.part(torso, M["steel"])
        r.part(m_rect(cx - 4, int(y(21)), cx + 4, int(y(4))), M["tabard"])
        r.part(m_rect(cx - 5, int(y(12)), cx + 5, int(y(11))), M["leather"])
        r.dot({(cx + 3, int(y(12))), (cx + 3, int(y(11)))}, BRASS)
        hy = int(y(29))
        r.part(m_ellipse(cx + 1, hy, 7, 7), M["skin"])
        r.part(m_ellipse(cx - 2, hy + 1, 4, 5), M["hair"])
        r.part(m_rect(cx + 7, hy + 1, cx + 8, hy + 2), M["skin"])
        r.dot({(cx + 5, hy + 1), (cx + 5, hy + 2)}, EYE)
        r.part(m_ellipse(cx + 1, hy - 3, 8, 5), M["steel"])
        r.part(m_rect(cx - 7, hy - 1, cx + 8, hy), M["steel"], tone="lo")
        r.part(m_rect(cx + 7, hy, cx + 7, hy + 3), M["steel"], tone="mid")
        r.part(m_ellipse(cx - 1, hy - 10, 2.5, 1.5), M["tabard"])
        # spear upright in the near hand, a step ahead of the body
        # spear sloped over the shoulder: butt trailing low behind, tip forward
        b0, t0 = (cx - 9, P.g - 3), (cx + 13, 11)
        r.part(m_line(b0[0], b0[1], t0[0], t0[1]), M["wood"])
        r.part(m_poly([(t0[0], t0[1]), (t0[0] + 3, t0[1] - 1), (t0[0] + 4, t0[1] - 4), (t0[0] + 1, t0[1] - 2)]), M["steel"])
        r.dot({(t0[0] - 1, t0[1] + 1)}, BRASS)
        hy_hand = int(y(15) + (P.s if P.walking else 0))
        tt = (b0[1] - hy_hand) / (b0[1] - t0[1])
        hand = (int(round(b0[0] + tt * (t0[0] - b0[0]))), hy_hand)
        r.part(m_limb(cx + 1, y(20), hand[0] - 1, hand[1] + 1, 3), M["steel"])
        r.part(m_ellipse(hand[0], hand[1], 1.5, 1.5), M["skin"])
    return r.render()


def build(fn):
    out = sheet([fn(NPose(d, p, w)) for d, p, w in FRAMES], 15, 40, 64)
    assert out.size == (600, 64)
    return out


TARGETS = [(daniel, "npc/sprites/npc_sprite.png"), (stefano, "npc/sprites/npc_sprite_02.png")]

if __name__ == "__main__":
    if len(sys.argv) > 1:          # preview mode: write both side by side to a scratch path
        a, b = build(daniel), build(stefano)
        from PIL import Image
        o = Image.new("RGBA", (600, 128))
        o.paste(a, (0, 0)); o.paste(b, (0, 64))
        o.save(sys.argv[1])
        print("✅ wrote preview", sys.argv[1])
    else:
        for fn, path in TARGETS:
            build(fn).save(rp(path))
            dup = path.replace("npc/sprites/", "gui/dialog_system/sprites/")
            shutil.copyfile(rp(path), rp(dup))
            print("✅ wrote", path, "and copied to", dup)
