"""build_skeleton.py — rebuild enemies/skeleton/skeleton.png (512x192, 8x3 of 64 px, scale 0.75).

"Still Holding the Line" (enemies/redesign/BRIEF.md): tallest of the cast,
bone-thin limbs, narrow ribcage, bare skull under a rusty kettle helm with a
wide brim, long spear with a leaf tip, big round shield (on the arm in
down/side, slung on the back in up), ragged crimson tabard.
Outline: slate #232c38.

Connected rig: the shield disc caps the forearm, the fist wraps the shaft,
the skull sits on the neck vertebrae and the helm brim overlaps the skull.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pixrig import Mat, Rig, m_ellipse, m_limb, m_line, m_poly, m_rect, rp  # noqa: E402
from humanoid import Pose, build_sheet  # noqa: E402

BONE = Mat("#eee8d5", "#c9c2a8", "#8f8872")
STEEL = Mat("#b4c2d0", "#7e8b99", "#505b69")
RUST = Mat("#b8703f", "#8a4a2c", "#5a2c19")
CRIMSON = Mat("#b4504c", "#8c3a3a", "#5c2222")
OUT = "#232c38"


def ragged(cx, top, bot, half, phase):
    pts = m_rect(cx - half, top, cx + half, bot)
    for x in range(cx - half, cx + half + 1):
        if (x + phase) % 2 == 0:
            pts.discard((x, bot))
        if (x + phase) % 4 == 1:
            pts.discard((x, bot - 1))
    return pts


def spear(r, x0, y0, x1, y1):
    """Shaft from butt (x0,y0) to just under the tip at (x1,y1); leaf tip beyond."""
    r.part(m_line(x0, y0, x1, y1), RUST)
    dx, dy = x1 - x0, y1 - y0
    n = max(abs(dx), abs(dy)) or 1
    ux, uy = dx / n, dy / n
    tip = (x1 + ux * 5, y1 + uy * 5)
    px, py = -uy, ux
    leaf = m_poly([(x1, y1), (x1 + ux * 2 + px * 2, y1 + uy * 2 + py * 2), tip, (x1 + ux * 2 - px * 2, y1 + uy * 2 - py * 2)])
    r.part(leaf, STEEL)


def shield(r, cx, cy, rx, ry):
    r.part(m_ellipse(cx, cy, rx, ry), STEEL)
    r.part(m_ellipse(cx, cy, rx - 1, ry - 1), CRIMSON)
    r.part(m_ellipse(cx, cy, 1, 1), STEEL, tone="hi")


def helm(r, cx, top_y, brim_y, back=False, side=False):
    if side:
        r.part(m_ellipse(cx, top_y + 3, 5, 3), RUST)
        r.part(m_rect(cx - 8, brim_y, cx + 7, brim_y + 1), RUST)
    else:
        r.part(m_ellipse(cx, top_y + 3, 5, 3), RUST)
        r.part(m_rect(cx - 8, brim_y, cx + 8, brim_y + 1), RUST)
    r.dot({(cx - 2, top_y + 1), (cx - 1, top_y + 1)}, RUST.hi)


def front(P: Pose, back: bool):
    r = Rig(outline=OUT)
    y = P.y
    cx = 32
    lr, rr = P.front_feet()
    ls, rs = P.arm_swing()
    sp = -1 if back else 1           # spear side (viewer right from the front)
    # legs: thin bones with knee knobs
    for lx, raise_ in ((cx - 3, lr), (cx + 3, rr)):
        fy = P.g - raise_
        r.part(m_line(lx, y(16), lx, fy - 1), BONE)
        r.part(m_rect(lx - 1, int(y(9)), lx, int(y(8))), BONE)
        r.part(m_rect(lx - 1, fy - 1, lx + 1, fy), STEEL)   # iron sabatons
    r.part(m_rect(cx - 4, int(y(17)), cx + 4, int(y(15))), BONE)   # pelvis
    # ribcage + tabard
    r.part(m_ellipse(cx, y(24), 5, 6), BONE)
    if not back:
        for k in range(3):
            r.dot(m_line(cx - 4, int(y(27 - 3 * k)), cx - 2, int(y(27 - 3 * k))), BONE.lo)
            r.dot(m_line(cx + 2, int(y(27 - 3 * k)), cx + 4, int(y(27 - 3 * k))), BONE.lo)
    r.part(ragged(cx, int(y(29)), int(y(12)), 2 if not back else 3, P.p), CRIMSON)
    r.part(m_line(cx, y(30), cx, y(32)), BONE)          # neck vertebrae
    # skull + helm
    hy = y(36) + P.lean
    r.part(m_ellipse(cx, hy, 5, 5), BONE)
    if not back:
        r.dot(m_rect(cx - 3, int(hy), cx - 2, int(hy) + 1) | m_rect(cx + 2, int(hy), cx + 3, int(hy) + 1), OUT)
        r.dot(m_line(cx - 2, int(hy) + 4, cx + 2, int(hy) + 4), BONE.lo)
    helm(r, cx, int(hy - 7), int(hy - 3))
    # arms
    shield_x = cx - 9 * sp
    arm_s = ls if sp > 0 else rs
    arm_w = rs if sp > 0 else ls
    if back:
        # shield slung across the back: drawn over the ribcage, under the arms
        shield(r, cx, y(22), 6, 7)
        r.part(m_line(shield_x + sp * 2, y(29), shield_x + sp * 1, y(17) + arm_s), BONE)
    else:
        r.part(m_line(cx - 5 * sp, y(29), shield_x, y(20)), BONE)
        shield(r, shield_x, y(19) + (arm_s // 2), 6, 7)
    hand_x = cx + 8 * sp
    if not P.chase:
        hand_y = y(17) + arm_w
        spear(r, hand_x, P.g - 2, hand_x, y(36 if back else 43))
        r.part(m_line(cx + 5 * sp, y(29), hand_x, hand_y), BONE)
        r.part(m_rect(hand_x - 1, int(hand_y) - 1, hand_x + 1, int(hand_y)), BONE)
    else:
        # spear levelled at you: butt high behind the shoulder, leaf tip down by the feet
        hand_y = y(20) + (P.p % 2)
        if back:
            spear(r, hand_x + sp * 2, P.g - 6, hand_x - sp * 4, y(36))
        else:
            spear(r, hand_x + sp * 3, y(34), hand_x - sp * 2, P.g - 7)
        r.part(m_line(cx + 5 * sp, y(29), hand_x, hand_y), BONE)
        r.part(m_rect(hand_x - 1, int(hand_y) - 1, hand_x + 1, int(hand_y)), BONE)
    return r.render()


def side(P: Pose):
    r = Rig(outline=OUT)
    y = P.y
    cx = 29
    ndx, nr, fdx, frs = P.side_feet()
    r.part(m_line(cx, y(16), cx + fdx, P.g - frs - 1), BONE, tone="lo")
    r.part(m_rect(cx + fdx - 1, P.g - frs - 1, cx + fdx + 1, P.g - frs), STEEL, tone="lo")
    r.part(m_line(cx, y(16), cx + ndx, P.g - nr - 1), BONE)
    r.part(m_rect(cx + ndx - 1, P.g - nr - 1, cx + ndx + 2, P.g - nr), STEEL)
    r.part(m_rect(cx - 2, int(y(17)), cx + 2, int(y(15))), BONE)
    r.part(m_ellipse(cx + 1, y(24), 4, 6), BONE)
    r.part(ragged(cx + 1, int(y(29)), int(y(12)), 2, P.p), CRIMSON)
    r.part(m_line(cx + 1, y(30), cx + 2, y(32)), BONE)
    hy = y(36) + P.lean
    hx_ = cx + 2
    r.part(m_ellipse(hx_, hy, 5, 5), BONE)
    r.part(m_rect(hx_ + 2, int(hy) + 3, hx_ + 5, int(hy) + 5), BONE)      # jaw
    r.dot(m_rect(hx_ + 2, int(hy), hx_ + 3, int(hy) + 1), OUT)
    r.dot({(hx_ + 3, int(hy) + 4), (hx_ + 5, int(hy) + 4)}, BONE.lo)
    helm(r, hx_, int(hy - 7), int(hy - 3), side=True)
    # spear: walk = carried angled up-forward; chase = levelled thrust
    if not P.chase:
        hand = (cx + 6, y(19) - P.s)
        spear(r, cx - 6, y(13), cx + 12, y(34))
    else:
        lunge = 3 if P.p in (1, 2) else 0
        hand = (cx + 7 + lunge, y(22))
        spear(r, cx - 8 + lunge, y(23), cx + 21 + lunge, y(21))
    r.part(m_line(cx + 1, y(29), hand[0], hand[1]), BONE)
    r.part(m_rect(hand[0] - 1, int(hand[1]) - 1, hand[0] + 1, int(hand[1])), BONE)
    # shield on the near arm, seen at an angle
    r.part(m_line(cx, y(29), cx - 2, y(21)), BONE)
    shield(r, cx - 2, y(20) - (P.p % 2), 4, 7)
    return r.render()


def draw(P: Pose):
    if P.d == "side":
        return side(P)
    return front(P, back=(P.d == "up"))


if __name__ == "__main__":
    dst = sys.argv[1] if len(sys.argv) > 1 else rp("enemies/skeleton/skeleton.png")
    build_sheet(draw).save(dst)
    print("✅ wrote", dst)
