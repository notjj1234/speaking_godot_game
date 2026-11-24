"""build_orc.py — rebuild enemies/orc/orc.png (512x192, 8x3 of 64 px, scale 0.75).

"The Siege Engine" (enemies/redesign/BRIEF.md): trapezoid torso, huge
forearms, small head under a topknot, iron pauldron on one shoulder, heavy
rectangular cleaver visible in every direction, jagged leather war-skirt,
charcoal-olive skin with ochre war paint. Outline: near-black olive #1e1a12.

Built as a connected part rig: the head overlaps the shoulders, the pauldron
overlaps the arm root, the fist overlaps the cleaver grip — nothing floats.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pixrig import Mat, Rig, m_ellipse, m_limb, m_line, m_poly, m_rect, rp  # noqa: E402
from humanoid import Pose, build_sheet  # noqa: E402

SKIN = Mat("#727650", "#4e5238", "#33361f")
IRON = Mat("#a7adb3", "#6e7278", "#43464c")
LEATHER = Mat("#8c5c34", "#5f3d21", "#3a2513")
OCHRE = "#d0922f"
TUSK = "#e6dcc0"
OUT = "#1e1a12"


def jag_skirt(cx, top, bot, half_top, half_bot, sway=0):
    pts = m_poly([(cx - half_top, top), (cx + half_top, top), (cx + half_bot, bot), (cx - half_bot, bot)])
    # jagged hem: notch every 3rd column
    for x in range(int(cx - half_bot), int(cx + half_bot) + 1):
        if (x + sway) % 3 == 0:
            pts.discard((x, int(bot)))
    return pts


def front(P: Pose, back: bool):
    r = Rig(outline=OUT)
    y = P.y
    cx = 32
    sway = (0, 1, 0, -1)[P.p] if not P.chase else 0
    lr, rr = P.front_feet()
    ls, rs = P.arm_swing()
    # legs + boots (feet planted on the baseline unless raised)
    for lx, raise_ in ((cx - 4, lr), (cx + 4, rr)):
        fy = P.g - raise_
        r.part(m_limb(lx, y(10), lx, fy - 2, 5, 5), SKIN)
        r.part(m_rect(lx - 3, fy - 2, lx + 2, fy), LEATHER)
    r.part(jag_skirt(cx + sway, y(15), y(7), 8, 10, P.p), LEATHER)
    # trapezoid torso: wide shoulders, narrow waist
    torso = m_poly([(cx - 7 + sway, y(15)), (cx + 7 + sway, y(15)), (cx + 12 + sway, y(27)), (cx + 8 + sway, y(30)),
                    (cx - 8 + sway, y(30)), (cx - 12 + sway, y(27))])
    r.part(torso, SKIN)
    r.part(m_rect(cx - 8 + sway, y(16), cx + 8 + sway, y(15)), LEATHER, tone="lo")   # belt
    if not back:
        for k in range(4):                      # ochre war paint chevron
            r.dot({(cx - 6 + k + sway, int(y(24 - k))), (cx + 6 - k + sway, int(y(24 - k)))}, OCHRE)
    else:
        r.dot(m_line(cx + sway, int(y(28)), cx + sway, int(y(18))), SKIN.lo)        # spine
        r.dot({(cx - 5 + sway, int(y(22))), (cx + 5 + sway, int(y(22)))}, OCHRE)
    # head (small, sunk between the shoulders) + topknot
    hy = y(31) + P.lean
    head = m_ellipse(cx + sway, hy, 5, 5)
    r.part(head, SKIN)
    r.part(m_ellipse(cx + sway, hy - 7, 2, 2), LEATHER)
    r.part(m_limb(cx + sway, hy - 9, cx + 3 + sway, hy - 11, 2, 1), LEATHER)
    r.part(m_rect(cx - 2 + sway, int(hy - 5), cx + 2 + sway, int(hy - 4)), IRON, tone="mid")  # topknot ring
    if not back:
        r.dot({(cx - 2 + sway, int(hy)), (cx + 2 + sway, int(hy))}, OCHRE)                 # eyes
        r.dot({(cx - 2 + sway, int(hy + 3)), (cx + 2 + sway, int(hy + 3))}, TUSK)          # tusks
        r.dot(m_line(cx - 3 + sway, int(hy - 2), cx - 1 + sway, int(hy - 1)), SKIN.lo)     # brow
        r.dot(m_line(cx + 3 + sway, int(hy - 2), cx + 1 + sway, int(hy - 1)), SKIN.lo)
    # arms: cleaver arm on the pauldron side
    weapon_left = back            # viewer-left from behind, viewer-right from the front
    wsx = -1 if weapon_left else 1
    free_x, w_x = cx - 11 * wsx + sway, cx + 11 * wsx + sway
    fs, ws = (rs, ls) if weapon_left else (ls, rs)
    r.part(m_limb(free_x, y(26), free_x - wsx * 2, y(13) + fs, 5, 7), SKIN)
    r.part(m_ellipse(free_x - wsx * 2, y(12) + fs, 3, 3), SKIN)
    if not P.chase:
        hand = (w_x + wsx * 2, y(13) + ws)
        # cleaver hangs from the fist, blade dragging just above the ground
        hy0 = int(hand[1])
        r.part(m_rect(hand[0], hy0 - 1, hand[0] + wsx, hy0 + 4), LEATHER)
        blade = m_rect(hand[0] - wsx, hy0 + 4, hand[0] + wsx * 5, min(P.g - 1, hy0 + 14))
        r.part(blade, IRON)
        edge_x = hand[0] + wsx * 5
        r.dot(m_line(edge_x, hy0 + 5, edge_x, min(P.g - 1, hy0 + 13)), IRON.hi)
        r.dot({(hand[0] + wsx * 2, hy0 + 6)}, IRON.lo)
        r.part(m_limb(w_x, y(26), hand[0], hand[1], 5, 7), SKIN)
        r.part(m_ellipse(hand[0], hand[1], 3, 3), SKIN)
    else:
        # cleaver raised over the shoulder, blade up behind the head
        hand = (w_x + wsx * 1, y(31) + (1 if P.p % 2 else 0))
        r.part(m_rect(hand[0], int(hand[1]) - 4, hand[0], int(hand[1]) + 1), LEATHER)
        blade = m_rect(hand[0] - 3 * wsx, int(hand[1]) - 14, hand[0] + 2 * wsx, int(hand[1]) - 4)
        r.part(blade, IRON)
        r.dot(m_line(hand[0] - 3 * wsx, int(hand[1]) - 13, hand[0] - 3 * wsx, int(hand[1]) - 5), IRON.hi)
        r.part(m_limb(w_x, y(26), hand[0], hand[1], 5, 7), SKIN)
        r.part(m_ellipse(hand[0], hand[1], 3, 3), SKIN)
    # iron pauldron over the weapon shoulder (drawn last so it caps the arm root)
    px_ = w_x - wsx * 1
    r.part(m_ellipse(px_, y(28), 5, 3), IRON)
    r.part(m_poly([(px_ - 6, y(26)), (px_ + 6, y(26)), (px_ + 5, y(23)), (px_ - 5, y(23))]), IRON)
    r.dot({(px_ - 2, int(y(29))), (px_ + 2, int(y(29)))}, IRON.hi)
    return r.render()


def side(P: Pose):
    r = Rig(outline=OUT)
    y = P.y
    cx = 30
    lean = 1 + P.lean
    ndx, nr, fdx, frs = P.side_feet()
    # far arm + far leg (behind the body)
    r.part(m_limb(cx - 1, y(9), cx + fdx, P.g - frs - 2, 5, 5), SKIN, tone="lo")
    r.part(m_rect(cx + fdx - 2, P.g - frs - 2, cx + fdx + 3, P.g - frs), LEATHER, tone="lo")
    farm = -P.s * 2
    r.part(m_limb(cx + 1 + lean, y(26), cx - 3 + farm, y(13), 5, 6), SKIN, tone="lo")
    # near leg
    r.part(m_limb(cx + 1, y(9), cx + ndx, P.g - nr - 2, 5, 5), SKIN)
    r.part(m_rect(cx + ndx - 2, P.g - nr - 2, cx + ndx + 3, P.g - nr), LEATHER)
    r.part(jag_skirt(cx, y(15), y(7), 6, 8, P.p), LEATHER)
    # torso leaning forward: broad back, chest pushed right
    torso = m_poly([(cx - 5, y(15)), (cx + 5, y(15)), (cx + 8 + lean, y(24)), (cx + 6 + lean, y(30)),
                    (cx - 6 + lean, y(30)), (cx - 8, y(24))])
    r.part(torso, SKIN)
    r.part(m_rect(cx - 6, y(16), cx + 6, y(15)), LEATHER, tone="lo")
    for k in range(3):
        r.dot({(cx + 3 + k + lean, int(y(25 - k)))}, OCHRE)
    # small head jutting forward, tusk + eye facing right
    hx_, hy = cx + 6 + lean, y(30) + P.lean
    r.part(m_ellipse(hx_, hy, 5, 5), SKIN)
    r.part(m_poly([(hx_ + 3, hy + 1), (hx_ + 7, hy + 2), (hx_ + 6, hy + 4), (hx_ + 2, hy + 4)]), SKIN)  # jaw
    r.part(m_ellipse(hx_ - 2, hy - 7, 2, 3), LEATHER)
    r.part(m_rect(hx_ - 3, int(hy - 5), hx_ - 1, int(hy - 4)), IRON, tone="mid")
    r.dot({(hx_ + 3, int(hy - 1))}, OCHRE)
    r.dot({(hx_ + 6, int(hy + 1)), (hx_ + 6, int(hy))}, TUSK)
    r.dot(m_line(hx_ + 1, int(hy - 2), hx_ + 4, int(hy - 3)), SKIN.lo)
    # near arm + cleaver
    sh = (cx + 1, y(26))
    if not P.chase:
        hand = (cx + 6 + P.s * 2, y(12))
        r.part(m_rect(hand[0], int(hand[1]) - 1, hand[0] + 4, int(hand[1])), LEATHER)          # grip
        r.part(m_rect(hand[0] + 4, int(hand[1]) - 2, hand[0] + 12, int(hand[1]) + 5), IRON)    # blade forward
        r.dot(m_line(hand[0] + 4, int(hand[1]) + 6, hand[0] + 11, int(hand[1]) + 6), IRON.lo)
    else:
        hand = (cx - 3, y(30) - (P.p % 2))
        r.part(m_rect(hand[0] - 1, int(hand[1]) - 4, hand[0], int(hand[1])), LEATHER)
        r.part(m_rect(hand[0] - 8, int(hand[1]) - 11, hand[0] - 1, int(hand[1]) - 4), IRON)    # blade cocked back
    r.part(m_limb(sh[0], sh[1], hand[0], hand[1], 5, 7), SKIN)
    r.part(m_ellipse(hand[0], hand[1], 3, 3), SKIN)
    r.part(m_ellipse(cx + 1, y(28), 5, 3), IRON)
    r.part(m_poly([(cx - 4, y(26)), (cx + 6, y(26)), (cx + 5, y(23)), (cx - 3, y(23))]), IRON)
    r.dot({(cx - 1, int(y(29)))}, IRON.hi)
    return r.render()


def draw(P: Pose):
    if P.d == "side":
        return side(P)
    return front(P, back=(P.d == "up"))


if __name__ == "__main__":
    dst = sys.argv[1] if len(sys.argv) > 1 else rp("enemies/orc/orc.png")
    build_sheet(draw).save(dst)
    print("✅ wrote", dst)
