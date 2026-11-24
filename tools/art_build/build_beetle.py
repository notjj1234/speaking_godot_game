"""build_beetle.py — rebuild enemies/beetle/Beetle.png (1024x128, 16x2 of 64 px).

Frame map (unchanged, consumed by enemies/beetle/beetle.tscn):
  0-2 idle down, 3-5 idle up, 6-8 idle side,
  9-11 walk down, 12-14 walk up, 15-17 walk side,
  18-20 stun down, 21-23 stun up, 24-26 stun side  (destroy reuses stun + walk).
Feet baseline (bbox bottom, exclusive): down 54, up 53, side 53.
Target art size: 28-34 px wide, 24-30 px tall at scale 1.0.

Design: an indigo rhinoceros beetle — 3-tone violet shell with a cool rim
light on the right edge, umber legs (six, always readable), amber horn and
mandibles thrust forward in the down view, shell seam + no face from behind,
dome profile with all near-side legs visible in the side view.
"""
from __future__ import annotations

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pixrig import Mat, Rig, m_ellipse, m_limb, m_line, m_poly, m_rect, rp, sheet, shift  # noqa: E402

SHELL = Mat("#9c80e2", "#6449b2", "#382670", rim="#b4ecff")
LEG = Mat("#8a5e3c", "#5a3a26", "#2e1c14")
HORN = Mat("#f2d88a", "#c8963e", "#7a5424")
EYE = "#ff5f3f"
OUT = "#150918"

BASE = {"down": 54, "up": 53, "side": 53}


def legs_down(r, base, phase, splay=0, up=False):
    """Six legs from under the shell. Alternating tripods (L1 R2 L3 / R1 L2 R3)
    swing +/-2 px per walk phase; the planted front foot holds the baseline."""
    cx = 32
    if not up:
        spec = [(7, base - 10, 12, base - 1), (10, base - 15, 14, base - 12), (8, base - 20, 13, base - 25)]
    else:
        spec = [(7, base - 9, 12, base - 1), (10, base - 13, 14, base - 11), (8, base - 18, 13, base - 23)]
    for k, (hx_, hy, fx, fy) in enumerate(spec):
        for side in (-1, 1):
            tri = (k + (0 if side < 0 else 1)) % 2
            d = phase if tri == 0 else -phase
            fx2 = fx + splay - (1 if d < 0 and k == 0 else 0)
            fy2 = fy - (3 if d < 0 else 0) if k == 0 else fy + 3 * d
            fy2 = min(fy2, base - 1)
            kx = cx + side * (hx_ + (fx2 - hx_) * 0.6 + 1)
            ky = (hy + fy2) / 2.0 - (2 if k else 0)
            r.part(m_limb(cx + side * hx_, hy, kx, ky, 2) | m_limb(kx, ky, cx + side * fx2, fy2, 2, 1), LEG)


def frame_down(phase=0, bob=0, mode="idle", t=0):
    r = Rig(outline=OUT)
    b = BASE["down"] - 1
    sy = -bob
    splay = 1 if mode == "stun" else 0
    legs_down(r, b, phase if mode == "walk" else 0, splay=splay)
    squash = 2 if (mode == "stun" and t == 0) else 0
    # shell (elytra) seen from above-front
    sh_cy = b - 18 + sy + squash // 2
    shell = m_ellipse(32, sh_cy, 12, 8 - squash // 2)
    if mode == "stun" and t in (1, 2):
        # elytra flare open: two halves spread, wings show between
        spread = 3 if t == 1 else 1
        wing = m_ellipse(32, sh_cy + 1, 8, 9)
        r.part(wing, SHELL, tone="rim", sep=False)
        left = {p for p in m_ellipse(32 - spread, sh_cy, 12, 8) if p[0] <= 31 - spread // 2}
        right = {p for p in m_ellipse(32 + spread, sh_cy, 12, 8) if p[0] >= 33 + spread // 2}
        r.part(left, SHELL, rim=True)
        r.part(right, SHELL, rim=True)
    else:
        r.part(shell, SHELL, shade="round", rim=True)
        r.dot(m_line(32, sh_cy - 8, 32, sh_cy + 6), SHELL.lo)      # seam
        r.dot({(26, sh_cy - 5), (27, sh_cy - 6), (28, sh_cy - 6)}, SHELL.rim)  # gloss
    # pronotum + head in front (towards viewer)
    r.part(m_ellipse(32, b - 10 + sy, 8, 3), SHELL, shade="auto")
    r.part(m_ellipse(32, b - 7 + sy, 7, 3), LEG)
    # big horn rises from the head and curls up over the shell (reads as "front")
    lean = 1 if (mode == "idle" and t == 1) else 0
    hp = m_poly([(28, b - 7 + sy), (36, b - 7 + sy), (34.5, b - 12 + sy), (33 + lean, b - 17 + sy), (31 + lean, b - 19 + sy), (30, b - 13 + sy)])
    r.part(hp, HORN)
    r.part(m_limb(31 + lean, b - 18 + sy, 29 + lean, b - 20 + sy, 2, 1), HORN)
    # mandibles thrust forward and outward
    jaw = 1 if (mode == "idle" and t == 1) or (mode == "walk" and phase == 1) else 0
    for side in (-1, 1):
        r.part(m_limb(32 + side * 4, b - 6 + sy, 32 + side * (7 + jaw), b - 2 + sy, 3, 2) |
               m_limb(32 + side * (7 + jaw), b - 2 + sy, 32 + side * (3 + jaw), b - 1 + sy, 2, 1), HORN)
    r.dot({(28, b - 8 + sy), (36, b - 8 + sy)}, EYE)
    return r.render()


def frame_up(phase=0, bob=0, mode="idle", t=0):
    r = Rig(outline=OUT)
    b = BASE["up"] - 1
    sy = -bob
    splay = 1 if mode == "stun" else 0
    # head + horn peek over the top (no face from behind)
    r.part(m_ellipse(32, b - 22 + sy, 6, 3), LEG)
    r.part(m_poly([(30, b - 22 + sy), (34, b - 22 + sy), (33, b - 25 + sy), (32, b - 27 + sy), (31, b - 25 + sy)]), HORN)
    legs_down(r, b, phase if mode == "walk" else 0, splay=splay, up=True)
    r.part(m_ellipse(32, b - 19 + sy, 8, 3), SHELL)
    squash = 2 if (mode == "stun" and t == 0) else 0
    sh_cy = b - 12 + sy + squash // 2
    if mode == "stun" and t in (1, 2):
        spread = 3 if t == 1 else 1
        r.part(m_ellipse(32, sh_cy, 8, 9), SHELL, tone="rim", sep=False)
        r.part({p for p in m_ellipse(32 - spread, sh_cy, 12, 9) if p[0] <= 31 - spread // 2}, SHELL, rim=True)
        r.part({p for p in m_ellipse(32 + spread, sh_cy, 12, 9) if p[0] >= 33 + spread // 2}, SHELL, rim=True)
    else:
        r.part(m_ellipse(32, sh_cy, 12, 9 - squash // 2), SHELL, shade="round", rim=True)
        r.dot(m_line(32, sh_cy - 8, 32, sh_cy + 8), SHELL.lo)
        r.dot({(26, sh_cy - 6), (27, sh_cy - 7), (28, sh_cy - 7)}, SHELL.rim)
        # abdomen tip under the shell rear
        r.part(m_ellipse(32, sh_cy + 8, 5, 2), LEG)
    return r.render()


def frame_side(phase=0, bob=0, mode="idle", t=0):
    r = Rig(outline=OUT)
    b = BASE["side"] - 1
    sy = -bob
    fy = b - 1
    hips = [(23, b - 8), (29, b - 7), (35, b - 8)]
    feet = [(20, fy), (28, fy), (36, fy)]
    walk = phase if mode == "walk" else 0
    # far legs (behind the body): dark tone, offset back so all six read
    for k, (hx_, hy) in enumerate(hips):
        d = (1 if k % 2 else -1) * walk
        fx, f_y = feet[k]
        fx += 2 - 2 * d
        f_y = f_y - (2 if d > 0 else 0) - (2 * (k % 2) if mode == "stun" else 0)
        kx, ky = (hx_ + 2 + fx) / 2.0 + 1, hy - 2 + sy
        r.part(m_limb(hx_ + 2, hy + sy, kx, ky, 2) | m_limb(kx, ky, fx, f_y, 1), LEG, tone="lo")
    squash = 2 if (mode == "stun" and t == 0) else 0
    r.part(m_poly([(18, b - 10 + sy), (40, b - 10 + sy), (38, b - 6 + sy), (20, b - 6 + sy)]), LEG)
    r.part(m_ellipse(41, b - 10 + sy, 5, 4), LEG)
    horn_tip = (48, b - 22 + sy) if not (mode == "idle" and t == 1) else (48, b - 23 + sy)
    r.part(m_poly([(40, b - 13 + sy), (44, b - 13 + sy), (46.5, b - 18 + sy), horn_tip, (45.5, b - 20 + sy), (42, b - 16 + sy)]), HORN)
    r.part(m_limb(44, b - 8 + sy, 48, b - 6 + sy, 2) | m_limb(48, b - 6 + sy, 46, b - 4 + sy, 2, 1), HORN)
    if mode == "stun" and t in (1, 2):
        lift = 4 if t == 1 else 2
        r.part(m_ellipse(28, b - 14 + sy, 9, 4), SHELL, tone="rim", sep=False)
        top = {p for p in m_ellipse(29, b - 12 + sy - lift, 11, 10) if p[1] <= b - 12 + sy - lift}
        r.part(top, SHELL, rim=True)
    else:
        top = {p for p in m_ellipse(29, b - 11 + sy + squash, 11, 13 - squash) if p[1] <= b - 9 + sy}
        r.part(top, SHELL, shade="round", rim=True)
        r.dot(m_line(18, b - 18 + sy + squash, 35, b - 21 + sy + squash), SHELL.lo)
        r.dot({(22, b - 20 + sy), (23, b - 21 + sy), (24, b - 21 + sy), (25, b - 22 + sy)}, SHELL.rim)
    r.dot({(43, b - 11 + sy)}, EYE)
    # near legs: knees up, feet spread so each leg is its own shape
    for k, (hx_, hy) in enumerate(hips):
        d = (1 if k % 2 == 0 else -1) * walk
        fx, f_y = feet[k]
        fx += 2 * d - 1
        f_y = f_y - (2 if d < 0 else 0) - (2 * ((k + 1) % 2) if mode == "stun" else 0)
        kx, ky = (hx_ + fx) / 2.0 - 1, hy - 2 + sy
        r.part(m_limb(hx_, hy + sy, kx, ky, 2) | m_limb(kx, ky, fx, f_y, 2, 1), LEG)
    return r.render()


def build():
    cells = []
    for fn in (frame_down, frame_up, frame_side):            # idle 0-8
        for t in range(3):
            cells.append(fn(0, 1 if t == 1 else 0, "idle", t))
    for fn in (frame_down, frame_up, frame_side):            # walk 9-17
        for t, (ph, bob) in enumerate(((1, 0), (0, 1), (-1, 0))):
            cells.append(fn(ph, bob, "walk", t))
    for fn in (frame_down, frame_up, frame_side):            # stun 18-26
        for t in range(3):
            cells.append(fn(0, 0, "stun", t))
    out = sheet(cells, 16, 64, 64)
    assert out.size == (1024, 128)
    return out


if __name__ == "__main__":
    dst = sys.argv[1] if len(sys.argv) > 1 else rp("enemies/beetle/Beetle.png")
    build().save(dst)
    print("✅ wrote", dst)
