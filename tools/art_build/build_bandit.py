"""build_bandit.py — rebuild enemies/bandit/bandit.png (512x192, 8x3 of 64 px, scale 0.75).

"The Exit Strategy" (enemies/redesign/BRIEF.md): human proportions, narrow
shoulders, oxblood hood with a scarf tail that flutters behind, bone face-wrap,
short umber leather jack, tall boots, slim stiletto in a reverse grip and a
round steel buckler strapped to the off forearm. No green. Outline #2a1c14.

Connected rig: the buckler sits on the forearm (it is the forearm's end), the
stiletto's crossguard is inside the fist, the hood wraps the head and flows
into the scarf, which is anchored at the neck.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pixrig import Mat, Rig, m_ellipse, m_limb, m_line, m_poly, m_rect, rp  # noqa: E402
from humanoid import Pose, build_sheet  # noqa: E402

# Match the player's sheet: solid outline, finer shading (tools/art_build/style_check.py).
PLAYER_STYLE = {"outline_mode": "dark", "detail": True}

HOOD = Mat("#a8494d", "#7e3236", "#531f20")
LEATHER = Mat("#a06e44", "#7a5230", "#4c3119")
STEEL = Mat("#d6e0e6", "#9fb0bd", "#5f6e7a")
WRAP = "#d8c9a8"
OUT = "#2a1c14"


def scarf(r, x0, y0, dirx, phase, length=9, chase=False):
    """Scarf tail anchored at (x0,y0) streaming towards dirx; wave follows the step."""
    wave = (0, 1, 0, -1)[phase]
    pts = set()
    for k in range(length):
        x = x0 + dirx * k
        yy = y0 + k * (0.35 if chase else 0.7) + (wave if k > length // 2 else 0)
        pts |= m_rect(int(x), int(yy), int(x), int(yy) + (2 if k < length - 3 else 1))
    r.part(pts, HOOD)


def front(P: Pose, back: bool):
    r = Rig(outline=OUT)
    y = P.y
    cx = 32
    lr, rr = P.front_feet()
    ls, rs = P.arm_swing()
    crouch = 1 if P.chase else 0
    yy = lambda h: y(h) + (crouch if h > 10 else 0)
    # scarf tail behind the body (viewer-left from the front)
    if not back:
        scarf(r, cx - 4, yy(30), -1, P.p, 10, P.chase)
    # legs + tall boots
    for lx, raise_ in ((cx - 3, lr), (cx + 3, rr)):
        fy = P.g - raise_
        r.part(m_limb(lx, yy(16), lx, fy - 6, 4), LEATHER, tone="lo")
        r.part(m_rect(lx - 2, fy - 7, lx + 1, fy), LEATHER)
        r.part(m_rect(lx - 2, fy, lx + 2, fy), LEATHER, tone="lo")
    # short leather jack: narrow shoulders
    torso = m_poly([(cx - 5, yy(15)), (cx + 5, yy(15)), (cx + 6, yy(26)), (cx + 4, yy(29)), (cx - 4, yy(29)), (cx - 6, yy(26))])
    r.part(torso, LEATHER)
    r.part(m_rect(cx - 5, int(yy(17)), cx + 5, int(yy(16))), HOOD, tone="lo")      # sash belt
    if not back:
        r.dot(m_line(cx, int(yy(27)), cx, int(yy(18))), LEATHER.lo)                 # jack lacing
    # hood (covers the head; peak on top) + face-wrap and eye slit
    hy = yy(34)
    hood = m_ellipse(cx, hy, 6, 6) | m_poly([(cx - 3, hy - 5), (cx + 3, hy - 5), (cx + 1, hy - 9), (cx - 1, hy - 9)])
    r.part(hood, HOOD)
    r.part(m_poly([(cx - 7, hy + 4), (cx + 7, hy + 4), (cx + 5, hy + 7), (cx - 5, hy + 7)]), HOOD)  # cowl on shoulders
    if not back:
        r.part(m_rect(cx - 3, int(hy) - 1, cx + 3, int(hy) + 3), LEATHER, tone="hi", sep=False)
        r.dot(m_rect(cx - 3, int(hy) + 1, cx + 3, int(hy) + 3), WRAP)
        r.dot({(cx - 2, int(hy)), (cx + 2, int(hy))}, OUT)
    else:
        r.dot(m_line(cx, int(hy - 6), cx, int(hy + 3)), HOOD.lo)                    # hood seam
        scarf(r, cx + 1, yy(28), 0, P.p, 7, P.chase)
    # off arm: buckler strapped to the forearm (viewer-right from the front)
    bx = cx + 7 if not back else cx - 7
    bs = rs if not back else ls
    r.part(m_limb(bx - (1 if not back else -1), yy(27), bx, yy(19) + bs, 3), LEATHER)
    r.part(m_ellipse(bx + (1 if not back else -1), yy(18) + bs, 4, 4), STEEL)
    r.dot({(bx + (1 if not back else -1), int(yy(18) + bs))}, STEEL.lo)
    # knife arm: stiletto in reverse grip, blade along the forearm
    kx = cx - 7 if not back else cx + 7
    ks = ls if not back else rs
    if not P.chase:
        hand = (kx, yy(16) + ks)
        r.part(m_line(hand[0], int(hand[1]) + 1, hand[0], int(hand[1]) + 7), STEEL, tone="hi")      # blade points down
        r.part(m_rect(hand[0] - 1, int(hand[1]) + 1, hand[0] + 1, int(hand[1]) + 1), STEEL, tone="lo")
    else:
        hand = (kx - (1 if not back else -1), yy(24))
        r.part(m_line(hand[0], int(hand[1]) - 7, hand[0], int(hand[1]) - 1), STEEL, tone="hi")      # raised to strike
        r.part(m_rect(hand[0] - 1, int(hand[1]) - 1, hand[0] + 1, int(hand[1]) - 1), STEEL, tone="lo")
    r.part(m_limb(kx + (1 if not back else -1), yy(27), hand[0], hand[1], 3), LEATHER)
    r.part(m_rect(hand[0] - 1, int(hand[1]) - 1, hand[0] + 1, int(hand[1])), LEATHER, tone="hi")
    return r.render(**PLAYER_STYLE)


def side(P: Pose):
    r = Rig(outline=OUT)
    y = P.y
    cx = 31
    crouch = 1 if P.chase else 0
    yy = lambda h: y(h) + (crouch if h > 10 else 0)
    lean = 2 if P.chase else 0
    ndx, nr, fdx, frs = P.side_feet()
    # scarf streams behind (left)
    scarf(r, cx - 3 + lean, yy(30), -1, P.p, 10 if P.chase else 8, P.chase)
    r.part(m_limb(cx, yy(16), cx + fdx, P.g - frs - 6, 4), LEATHER, tone="lo")
    r.part(m_rect(cx + fdx - 2, P.g - frs - 7, cx + fdx + 1, P.g - frs), LEATHER, tone="lo")
    # far arm with buckler, held forward
    r.part(m_ellipse(cx + 5 + lean, yy(19), 2, 4), STEEL, tone="lo")
    r.part(m_limb(cx + 1, yy(16), cx + ndx, P.g - nr - 6, 4), LEATHER, tone="lo")
    r.part(m_rect(cx + ndx - 2, P.g - nr - 7, cx + ndx + 1, P.g - nr), LEATHER)
    r.part(m_rect(cx + ndx, P.g - nr, cx + ndx + 2, P.g - nr), LEATHER, tone="lo")
    torso = m_poly([(cx - 3, yy(15)), (cx + 3, yy(15)), (cx + 4 + lean, yy(27)), (cx + 2 + lean, yy(29)), (cx - 3 + lean, yy(29)), (cx - 4, yy(26))])
    r.part(torso, LEATHER)
    r.part(m_rect(cx - 3, int(yy(17)), cx + 3, int(yy(16))), HOOD, tone="lo")
    hx_, hy = cx + 1 + lean, yy(34)
    r.part(m_ellipse(hx_, hy, 5, 6) | m_poly([(hx_ - 4, hy - 4), (hx_, hy - 6), (hx_ + 4, hy - 8), (hx_ + 3, hy - 4)]), HOOD)
    r.part(m_poly([(hx_ - 5, hy + 4), (hx_ + 5, hy + 4), (hx_ + 4, hy + 7), (hx_ - 4, hy + 7)]), HOOD)
    r.part(m_rect(hx_ + 2, int(hy) - 1, hx_ + 5, int(hy) + 3), LEATHER, tone="hi", sep=False)
    r.dot(m_rect(hx_ + 2, int(hy) + 1, hx_ + 5, int(hy) + 3), WRAP)
    r.dot({(hx_ + 4, int(hy))}, OUT)
    # near arm + stiletto
    if not P.chase:
        hand = (cx + 2 - P.s * 2, yy(17))
        r.part(m_line(hand[0], int(hand[1]) + 1, hand[0] - 2, int(hand[1]) + 5), STEEL)
    else:
        stab = 3 if P.p in (1, 2) else 0
        hand = (cx + 6 + lean + stab, yy(22))
        r.part(m_line(hand[0] + 1, int(hand[1]), hand[0] + 6, int(hand[1]) - 1), STEEL)
    r.part(m_limb(cx, yy(27), hand[0], hand[1], 3), LEATHER)
    r.part(m_rect(hand[0] - 1, int(hand[1]) - 1, hand[0] + 1, int(hand[1])), LEATHER, tone="hi")
    return r.render(**PLAYER_STYLE)


def draw(P: Pose):
    if P.d == "side":
        return side(P)
    return front(P, back=(P.d == "up"))


if __name__ == "__main__":
    dst = sys.argv[1] if len(sys.argv) > 1 else rp("enemies/bandit/bandit.png")
    build_sheet(draw).save(dst)
    print("✅ wrote", dst)
