"""build_bosses.py — the four block bosses (enemies/bosses/*.png).

    python3.13 tools/art_build/build_bosses.py            # writes all four sheets
    python3.13 tools/art_build/build_bosses.py --preview DIR  # also writes 2x on-grass previews

A boss is twice the size of its base enemy on screen. Scaling the base sheet
2x would double every pixel (2 px outlines, chunky shading), which breaks the
player's pixel density (tools/art_build/style_check.py). So each boss sheet is
drawn at 2x resolution instead: 128 px cells in the base sheet's frame layout,
1 px outline, player-matched shading. The game shows it at sprite scale 0.5
inside the 2x boss (enemy.gd make_boss), so one art pixel is one screen pixel.

Bone Captain, Orc Warlord and Frost Bandit re-run their base builder
(build_skeleton / build_orc / build_bandit) through a 2x geometry layer: the
builder's 64 px coordinates are scaled before rasterising, so curves stay
smooth and only the outline/shading are drawn at the finer grid. Each boss
then swaps the palette and adds its own mark (captain's hat, horned helm,
ice crown). The Slime King has no base builder (Slime.png is hand drawn) and
is drawn directly at 128 px in Slime.png's 16x2 layout.

Base sheets are never written here; they stay byte-identical.
"""
from __future__ import annotations

import importlib
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pixrig import Mat, Rig, m_ellipse, m_limb, m_line, m_poly, m_rect, rp, sheet  # noqa: E402
from humanoid import Pose, frame_table  # noqa: E402

K = 2
CELL = 64 * K
PLAYER_STYLE = {"outline_mode": "dark", "detail": True}
OUT_DIR = "enemies/bosses"


# ------------------------------------------------------- 2x geometry layer ---

class Hi(tuple):
    """A point already in boss (2x) space. Plain tuples from a builder are
    64 px points and get lifted to a KxK block (eyes, studs, war paint)."""


def _hi(pts) -> set:
    return {Hi(p) for p in pts}


def _c(v: float) -> float:
    """Centre of a 64 px pixel in 2x space."""
    return v * K + (K - 1) / 2.0


def h_rect(x0, y0, x1, y1):
    xa, xb = sorted((int(x0), int(x1)))
    ya, yb = sorted((int(y0), int(y1)))
    pts = _hi(m_rect(xa * K, ya * K, xb * K + K - 1, yb * K + K - 1))
    _rects.append(pts)
    return pts


def h_ellipse(cx, cy, rx, ry):
    _note_ellipse(cx, cy, rx, ry)
    return _hi(m_ellipse(_c(cx), _c(cy), rx * K + (K - 1) / 2.0, ry * K + (K - 1) / 2.0))


def h_poly(pts):
    return _hi(m_poly([(_c(x), _c(y)) for x, y in pts]))


def h_line(x0, y0, x1, y1, w=1):
    o = K - 1
    return _hi(m_line(x0 * K + o, y0 * K + o, x1 * K + o, y1 * K + o, w * K))


def h_limb(x0, y0, x1, y1, w0, w1=None):
    w1 = w0 if w1 is None else w1
    pts = _hi(m_limb(_c(x0), _c(y0), _c(x1), _c(y1), w0 * K, w1 * K))
    _limbs.append((pts, (_c(x0), _c(y0), _c(x1), _c(y1), w0 * K, w1 * K)))
    return pts


def px_line(x0, y0, x1, y1):
    """A 1 px line given directly in 2x space (trim, seams)."""
    return _hi(m_line(x0, y0, x1, y1, 1))


def _lift(pts):
    out = set()
    for p in pts:
        if isinstance(p, Hi):
            out.add((p[0], p[1]))
        else:
            x, y = int(p[0]), int(p[1])
            out |= {(x * K + i, y * K + j) for i in range(K) for j in range(K)}
    return out


# Ellipses and limbs a builder draws, so a boss mark can find the head (and
# forearms) on each frame.
_ellipses: list = []
_limbs: list = []      # (mask, (x0, y0, x1, y1, w0, w1) in 2x space)
_rects: list = []      # rect masks (blades, belts, boots)
_dither_mats: tuple = ()   # materials whose mid/mid_lo boundary gets a checker row


def _note_ellipse(cx, cy, rx, ry):
    _ellipses.append((cx, cy, rx, ry))


FORCED_TONE_MAX = 40
_shift_cache: dict = {}


def _shifted(mat: Mat, tone: str) -> Mat:
    key = (id(mat), tone)
    if key not in _shift_cache:
        h = lambda c: "#%02x%02x%02x" % c[:3]
        if tone == "lo":
            m = Mat(h(mat.mid), h(mat.mid_lo), h(mat.lo))
        else:
            m = Mat(h(mat.hi), h(mat.mid_hi), h(mat.mid))
        m.grain = mat.grain
        _shift_cache[key] = (mat, m)   # keep mat alive so id() stays unique
    return _shift_cache[key][1]


_accessory = None   # callable(rig, pose) set per boss
_pose = None


class ScaledRig(Rig):
    GRAIN_DENSITY = 4    # 1 in N; 2x art has bigger flat areas, so denser than pixrig's 1 in 7

    def __init__(self, w=64, h=64, outline="#150918"):
        super().__init__(w * K, h * K, outline)

    def part(self, pts, mat, tone=None, shade="auto", sep=True, rim=False, band=1):
        limb = next((geo for mask, geo in _limbs if mask is pts), None)
        if tone in ("lo", "hi") and len(_lift(pts)) >= FORCED_TONE_MAX:
            # A forced tone (far limb in shadow, lit trim) is a thin strip at
            # 64 px but a flat block at 2x: shade it on a ramp shifted that way.
            mat, tone = _shifted(mat, tone), None
        is_rect = any(mask is pts for mask in _rects)
        idx = super().part(_lift(pts), mat, tone, shade, sep, rim, band)
        self.parts[idx]["limb"] = limb
        self.parts[idx]["rect"] = is_rect
        return idx

    def dot(self, pts, color):
        super().dot(_lift(pts), color)

    def erase(self, pts):
        super().erase(_lift(pts))

    def _grain_hit(self, x, y) -> bool:
        # Scrambled hash: pixrig's xor hash forms diagonal lines at small moduli.
        h = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
        h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
        return (h ^ (h >> 16)) % self.GRAIN_DENSITY == 0

    def render(self, outline_mode="selective", detail=False):
        if _accessory is not None:
            _accessory(self, _pose)
        img = super().render(**PLAYER_STYLE)
        if _dither_mats:
            _dither(img, self, _dither_mats)
        return img


def _dither(img, r, mats):
    """Soften tone boundaries on big parts with the 2-row checker pixel artists
    use for a soft turn of form: where two neighbouring ramp tones of one part
    meet and each side is at least 2 px deep, the pixels either side of the
    line swap on every other row (vertical lines) or column (horizontal lines)."""
    px = img.load()
    ids = {id(m) for m in mats}
    swaps = []
    for (x, y), i in r.lab.items():
        mat = r.parts[i]["mat"]
        if id(mat) not in ids:
            continue
        ramp = [mat.hi, mat.mid_hi, mat.mid, mat.mid_lo, mat.lo]
        at = lambda q: px[q] if r.lab.get(q) == i else None
        for (dx, dy), parity in (((0, 1), x % 2), ((1, 0), y % 2)):
            if parity:
                continue
            a, b = at((x, y)), at((x + dx, y + dy))
            if a is None or b is None or a == b or a not in ramp or b not in ramp:
                continue
            if abs(ramp.index(a) - ramp.index(b)) != 1:
                continue
            if at((x - dx, y - dy)) == a and at((x + 2 * dx, y + 2 * dy)) == b:
                swaps.append(((x, y), (x + dx, y + dy), a, b))
    done = set()
    for p, q, a, b in swaps:
        if p in done or q in done:
            continue
        px[p], px[q] = b, a
        done |= {p, q}


def _hi_jag(pts, step, deep_every, phase):
    """Notch the bottom edge of a 2x mask: a 1 px zigzag, deeper every few columns."""
    bottom = {}
    for x, y in pts:
        bottom[x] = max(bottom.get(x, y), y)
    out = set(pts)
    for x, yb in bottom.items():
        if (x + phase) % step == 0:
            out.discard(Hi((x, yb)))
            if (x + phase) % deep_every == 0:
                out.discard(Hi((x, yb - 1)))
    return {Hi(p) for p in out}


def h_jag_skirt(cx, top, bot, half_top, half_bot, sway=0):
    pts = h_poly([(cx - half_top, top), (cx + half_top, top), (cx + half_bot, bot), (cx - half_bot, bot)])
    return _hi_jag(pts, 3, 6, sway)


def h_ragged(cx, top, bot, half, phase):
    return _hi_jag(h_rect(cx - half, top, cx + half, bot), 2, 4, phase)


def load_scaled(module_name: str, **overrides):
    """Import a base builder with its geometry swapped for the 2x layer."""
    mod = importlib.import_module(module_name)
    mod.m_rect, mod.m_ellipse, mod.m_poly = h_rect, h_ellipse, h_poly
    mod.m_line, mod.m_limb, mod.Rig = h_line, h_limb, ScaledRig
    for k, v in overrides.items():
        setattr(mod, k, v)
    return mod


def humanoid_sheet(draw, accessory, dither=()):
    global _accessory, _pose, _dither_mats
    _dither_mats = dither
    cells = [None] * 24
    for i, d, ph, chase in frame_table():
        _pose = Pose(d, ph, chase)
        _ellipses.clear()
        _limbs.clear()
        _rects.clear()
        _accessory = accessory
        cells[i] = draw(_pose)
    _accessory = None
    _dither_mats = ()
    out = sheet(cells, 8, CELL, CELL)
    assert out.size == (8 * CELL, 3 * CELL)
    return out


def _parts_of(r, mat, min_size=1, shifted=True):
    """{part index: [(x, y), ...]} for every part drawn with mat (or, if `shifted`,
    its shifted ramp: far limbs in shadow, lit trims such as the bandit's face)."""
    mats = {id(mat)} | ({id(m) for (src, m) in _shift_cache.values() if src is mat} if shifted else set())
    out = {}
    for p, i in r.lab.items():
        if id(r.parts[i]["mat"]) in mats:
            out.setdefault(i, []).append(p)
    return {i: pts for i, pts in out.items() if len(pts) >= min_size}


def _seam(r, pts, line, stitch):
    """A 1 px seam down the middle of a part with a stitch mark every 3 px."""
    xs = sorted(x for x, _ in pts)
    mid = xs[len(xs) // 2]
    own = set(pts)
    for x, y in sorted(p for p in pts if p[0] == mid):
        if (x, y - 1) in own and (x, y + 1) in own:
            r.dot(_hi({(x, y)}), line)
            if y % 3 == 0 and (x + 1, y) in own:
                r.dot(_hi({(x + 1, y)}), stitch)


def _head(rx, ry):
    """Last ellipse of exactly this radius drawn on the current frame (64 px space)."""
    for cx, cy, a, b in reversed(_ellipses):
        if (a, b) == (rx, ry):
            return cx, cy
    raise RuntimeError(f"no head ellipse {rx}x{ry} on frame {_pose.d}/{_pose.p}")


# ------------------------------------------------------------ hand detail ---
# 2x art has four times the pixels of its base sprite, so the same shapes read
# as big flat blocks. These add the detail a pixel artist would at that size
# (creases, plate seams, rivets, straps, wraps), always inside a part so the
# silhouette and its outline never change.

def _paint(r, pts, color):
    """Dot only where nothing is painted yet (eyes, war paint and trim win)."""
    r.dot(_hi({p for p in pts if p in r.lab and p not in r.over}), color)


def _inside(own, x, y):
    return all(q in own for q in ((x, y), (x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)))


def _box(pts):
    xs = [x for x, _ in pts]
    ys = [y for _, y in pts]
    return min(xs), min(ys), max(xs), max(ys)


def _biggest(r, mat):
    parts = _parts_of(r, mat)
    if not parts:
        return None, []
    i = max(parts, key=lambda k: len(parts[k]))
    return i, parts[i]


def _folds(r, pts, mat, step, lengths=(0.55, 0.85, 0.4), from_top=True, phase=0):
    """Hanging cloth: a dark crease with a lit edge to its left every `step` columns."""
    own = set(pts)
    cols = {}
    for x, y in pts:
        cols.setdefault(x, []).append(y)
    xs = sorted(cols)
    for k, x in enumerate(xs[3:-3]):
        if (x + phase) % step:
            continue
        top, bot = min(cols[x]) + 2, max(cols[x]) - 2
        n = int((bot - top) * lengths[(x // step) % len(lengths)])
        rows = range(top, top + n) if from_top else range(bot - n, bot + 1)
        for y in rows:
            if _inside(own, x, y):
                _paint(r, {(x, y)}, mat.lo)
                if _inside(own, x - 1, y):
                    _paint(r, {(x - 1, y)}, mat.mid_hi)


def _ring(own, inset):
    def ins(x, y, k):
        return all((x + dx, y + dy) in own for dx in range(-k, k + 1) for dy in range(-k, k + 1))
    return [p for p in own if ins(*p, inset) and not ins(*p, inset + 1)]


def _rivets(r, pts, mat, step, inset=2):
    """Rivets spaced round a plate, `inset` px in from its edge."""
    own = set(pts)
    ring = _ring(own, inset)
    if len(ring) < step:
        return
    cx = sum(x for x, _ in ring) / len(ring)
    cy = sum(y for _, y in ring) / len(ring)
    ring.sort(key=lambda p: math.atan2(p[1] - cy, p[0] - cx))
    for x, y in ring[::step]:
        _paint(r, {(x, y)}, mat.hi)
        if (x + 1, y + 1) in own:
            _paint(r, {(x + 1, y + 1)}, mat.lo)


def _seam_row(r, pts, y, mat):
    """A plate seam: a dark row with a lit row under it, inset from the sides."""
    own = set(pts)
    for x, yy in pts:
        if yy == y and _inside(own, x, y):
            _paint(r, {(x, y)}, mat.lo)
            if _inside(own, x, y + 1):
                _paint(r, {(x, y + 1)}, mat.mid_hi)


def _wrap(r, idx, mat, t0, t1, studs=None):
    """A band round a limb between fractions t0..t1 of its length (bracer, cuff)."""
    geo = r.parts[idx].get("limb")
    if not geo:
        return
    x0, y0, x1, y1, w0, w1 = geo
    a = (x0 + (x1 - x0) * t0, y0 + (y1 - y0) * t0)
    b = (x0 + (x1 - x0) * t1, y0 + (y1 - y0) * t1)
    w = int(w0 + (w1 - w0) * (t0 + t1) / 2) + 1
    band = {p for p in m_line(a[0], a[1], b[0], b[1], w) if r.lab.get(p) == idx}
    if len(band) < 6:
        return
    r.part({Hi(p) for p in band}, mat, sep=False)
    if studs:
        own = set(band)
        mid = {}
        for x, y in band:
            mid.setdefault(x, []).append(y)
        for x in sorted(mid)[1:-1:3]:
            y = sorted(mid[x])[len(mid[x]) // 2]
            if _inside(own, x, y):
                r.dot(_hi({(x, y)}), studs)


def _limb_parts(r, mat):
    return [i for i in _parts_of(r, mat) if r.parts[i].get("limb")]


def _sparkle(r, x, y, hi, mid):
    """A 5 px frost glint (a plus with a bright core)."""
    _paint(r, {(x, y)}, hi)
    _paint(r, {(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)}, mid)


# ------------------------------------------------------------ Bone Captain ---

CAPT_COAT = Mat("#5b7fd6", "#3a56a3", "#22336a")
CAPT_HAT = Mat("#625b8a", "#443d6a", "#2c2749")
GOLD = Mat("#ffe27a", "#e0a92e", "#94631a")
PLUME = Mat("#f0605a", "#c23434", "#7a1c22")


def captain_helm(r, cx, top_y, brim_y, back=False, side=False):
    """Bicorne with gold trim and a red plume, in place of the kettle helm."""
    r.part(h_ellipse(cx, top_y + 2, 6, 4), CAPT_HAT)
    if side:
        brim = h_poly([(cx - 9, brim_y + 1), (cx + 8, brim_y + 1), (cx + 6, brim_y - 2), (cx - 7, brim_y - 3)])
    else:
        brim = h_poly([(cx - 10, brim_y + 1), (cx + 10, brim_y + 1), (cx + 7, brim_y - 2), (cx - 7, brim_y - 2)])
    r.part(brim, CAPT_HAT)
    x0 = (cx - (9 if side else 10)) * K
    x1 = (cx + (8 if side else 10)) * K + 1
    r.dot(px_line(x0 + 1, (brim_y + 1) * K, x1 - 1, (brim_y + 1) * K), GOLD.mid)
    r.dot(px_line(x0 + 1, (brim_y + 1) * K + 1, x1 - 1, (brim_y + 1) * K + 1), GOLD.lo)
    tail = -1 if side else 1
    r.part(h_limb(cx + 2 * tail, top_y, cx + 7 * tail, top_y - 4, 3, 1), PLUME)
    r.part(h_ellipse(cx + 1 * tail, top_y + 1, 1, 1), GOLD)          # cockade


def captain_trim(r, P):
    """Gold placket down the coat and a gold clasp at the collar."""
    for pts in _parts_of(r, CAPT_COAT, 60).values():
        _seam(r, pts, GOLD.lo, GOLD.mid)
        top = min(y for _, y in pts)
        xs = sorted(x for x, y in pts if y == top + 2)
        if xs and P.d != "up":
            cx = xs[len(xs) // 2]
            r.dot(_hi({(cx, top + 2), (cx + 1, top + 2), (cx, top + 3), (cx + 1, top + 3)}), GOLD.hi)


def captain_detail(r, P):
    """Coat creases rising from the hem, a gold ring on the shield, a creased hat crown."""
    for pts in _parts_of(r, CAPT_COAT, 60).values():
        x0, y0, x1, y1 = _box(pts)
        if y1 - y0 > 1.6 * (x1 - x0):                 # tabard: tall strip
            _folds(r, pts, CAPT_COAT, 4, (0.5, 0.75, 0.35), from_top=False, phase=P.p)
        else:                                         # shield face
            for x, y in _ring(set(pts), 3):
                _paint(r, {(x, y)}, GOLD.mid if (x + y) % 4 else GOLD.hi)
    captain_trim(r, P)
    if P.d != "side":
        tabard = max(_parts_of(r, CAPT_COAT, 60).values(), key=lambda pts: _box(pts)[3] - _box(pts)[1])
        x0, y0, x1, _ = _box(tabard)
        for ex in (x0 - 2, x1 + 2):
            r.part(_hi(m_ellipse(ex, y0 + 2, 5, 3)), GOLD)
            for k, fx in enumerate(range(ex - 4, ex + 5)):
                _paint(r, {(fx, y0 + 6)}, GOLD.hi if k % 2 else GOLD.lo)
    for pts in _parts_of(r, CAPT_HAT, 60).values():
        _folds(r, pts, CAPT_HAT, 5, (0.6, 0.4), from_top=False)


def bone_captain():
    sk = load_scaled("build_skeleton", ragged=h_ragged, CRIMSON=CAPT_COAT, helm=captain_helm)
    return humanoid_sheet(sk.draw, captain_detail, dither=(CAPT_COAT, CAPT_HAT))


# ------------------------------------------------------------- Orc Warlord ---

WAR_SKIN = Mat("#7f8c58", "#56603a", "#333a21")
WAR_IRON = Mat("#8d929e", "#565a68", "#33353f")
HORN = Mat("#f2e6c4", "#c9b98e", "#8a7a55")
WAR_PAINT = "#d23a2c"


def warlord_horns(r, P):
    hx_, hy = _head(5, 5)
    if P.d == "side":
        r.part(h_limb(hx_ - 2, hy - 3, hx_ + 1, hy - 9, 3, 1), HORN)
        r.part(h_limb(hx_ - 4, hy - 2, hx_ - 6, hy - 8, 3, 1), HORN, tone="lo")
        r.part(h_rect(hx_ - 5, int(hy - 4), hx_ + 3, int(hy - 3)), WAR_IRON)
        return
    for s in (-1, 1):
        r.part(h_limb(hx_ + 4 * s, hy - 2, hx_ + 8 * s, hy - 5, 3, 2), HORN)
        r.part(h_limb(hx_ + 8 * s, hy - 5, hx_ + 8 * s, hy - 10, 2, 1), HORN)
    r.part(h_rect(hx_ - 5, int(hy - 4), hx_ + 5, int(hy - 3)), WAR_IRON)


WAR_STRAP = Mat("#8c5c34", "#5f3d21", "#3a2513")   # the orc's leather, as its own part
SCAR = "#a9b07c"
WAR_PAINT_LO = "#7e2219"
WAR_BAND = Mat("#a7adb3", "#6e7278", "#43464c")      # the orc's own iron, as its own part (no rivets)


def _crease(r, pts, color, lit=None):
    """A 1 px muscle line; `lit` is painted just above it (the lit side of the form)."""
    for x, y in pts:
        if (x, y) in r.lab:
            _paint(r, {(x, y)}, color)
            if lit and (x, y - 1) in r.lab:
                _paint(r, {(x, y - 1)}, lit)


def _orc_muscles(r, P, torso):
    x0, y0, x1, y1 = _box(torso)
    w, h = x1 - x0, y1 - y0
    cx = (x0 + x1) // 2
    pec_y = y0 + int(h * 0.36)
    reach = max(4, int(w * 0.34))
    dark, lit = WAR_SKIN.lo, WAR_SKIN.mid_hi
    if P.d == "side":
        _crease(r, {(cx + dx, pec_y - int((dx / reach) ** 2 * 3)) for dx in range(0, reach)}, dark, lit)
        for row in (pec_y + 6, pec_y + 11):
            _crease(r, {(cx + dx, row) for dx in range(2, reach - 1)}, dark)
        return
    if P.d == "up":
        for sgn in (-1, 1):                           # shoulder blades either side of the spine
            _crease(r, {(cx + sgn * dx, pec_y + int((dx / reach) ** 2 * 3) - 2) for dx in range(3, reach)}, dark, lit)
            lat = m_line(cx + sgn * reach, pec_y + 3, cx + sgn * 5, y1 - 4, 1)   # lats taper to the waist
            _crease(r, set(lat) & set(torso), dark)
        spine = [p for p in torso if p in r.over and r.over[p][:3] == WAR_SKIN.lo[:3] and abs(p[0] - cx) <= 3]
        for x, y in spine:                            # vertebrae: a lit knob every 3 rows
            if y % 3 == 0:
                r.dot(_hi({(x, y)}), WAR_SKIN.mid_hi)
        _chevrons(r, set(torso), cx, pec_y + 5)
        hx_, hy = _head(5, 5)                         # thick neck folds under the skull
        hcx, hcy = int(_c(hx_)), int(_c(hy))
        for k, fy in enumerate((hcy + 4, hcy + 7)):
            _crease(r, {(hcx + dx, fy) for dx in range(-5 + k, 6 - k)}, dark, lit)
        return
    for sgn in (-1, 1):
        _crease(r, {(cx + sgn * dx, pec_y - int((dx / reach) ** 2 * 3)) for dx in range(2, reach)}, dark, lit)
        for row in (pec_y + 6, pec_y + 11, pec_y + 16):
            if row < y1 - 3:
                _crease(r, {(cx + sgn * dx, row) for dx in range(2, 6)}, dark)
    _crease(r, {(cx, y) for y in range(pec_y - 5, y1 - 3)}, dark)
    _chevrons(r, set(torso), cx, pec_y + 9)


def _chevrons(r, own, cx, top):
    """Two stacked war-paint chevrons, each a red stroke over a dark-red one."""
    for vy in (top, top + 5):
        for dx in range(2, 9):
            for sgn in (-1, 1):
                p = (cx + sgn * dx, vy + (dx - 2) // 2)
                if p in own and (p[0], p[1] + 1) in own:
                    r.dot(_hi({p}), WAR_PAINT)
                    _paint(r, {(p[0], p[1] + 1)}, WAR_PAINT_LO)


def _joint(r, idx, t, half):
    """A small cupped crease across a limb at fraction t (knee, elbow), lit above."""
    x0, y0, x1, y1, _, _ = r.parts[idx]["limb"]
    jx, jy = int(x0 + (x1 - x0) * t), int(y0 + (y1 - y0) * t)
    own = {p for p, i in r.lab.items() if i == idx}
    arc = {(jx + dx, jy + (1 if abs(dx) < half else 0)) for dx in range(-half, half + 1)}
    _paint(r, arc & own, WAR_SKIN.lo)
    _paint(r, {(jx + dx, jy - 1) for dx in range(-half + 1, half)} & own, WAR_SKIN.mid_hi)


def _tooth_necklace(r, P, torso):
    """A cord of trophy fangs slung under the jaw (front and side views)."""
    if P.d == "up":
        return
    own = set(torso)
    x0, y0, x1, y1 = _box(torso)
    cx = (x0 + x1) // 2 + (3 if P.d == "side" else 0)
    neck = min((y for x, y in torso if x == cx), default=y0)    # first chest row under the jaw
    rw = max(5, int((x1 - x0) * (0.22 if P.d == "side" else 0.3)))
    sag = lambda dx: neck + 6 - int((dx / rw) ** 2 * 5)
    _paint(r, {(cx + dx, sag(dx)) for dx in range(-rw, rw + 1)} & own, WAR_STRAP.lo)
    for dx in range(-rw + 2, rw - 1, 4):
        x, y = cx + dx, sag(dx)
        for k, c in enumerate((HORN.hi, HORN.mid, HORN.lo)):
            if (x, y + 1 + k) in own:
                _paint(r, {(x, y + 1 + k)}, c)


def _stitched_scar(r, own, a, b):
    """A healed cut: a pale line with dark stitch ticks across it every 3 px."""
    line = [p for p in m_line(a[0], a[1], b[0], b[1], 1) if p in own]
    for k, (x, y) in enumerate(line):
        _paint(r, {(x, y)}, SCAR)
        if k % 3 == 1:
            _paint(r, {q for q in ((x - 1, y - 1), (x + 1, y + 1)) if q in own}, WAR_SKIN.lo)


def orc_warlord():
    orc = load_scaled("build_orc", jag_skirt=h_jag_skirt, SKIN=WAR_SKIN, IRON=WAR_IRON, OCHRE=WAR_PAINT)

    def detail(r, P):
        warlord_horns(r, P)
        ti, torso = _biggest(r, WAR_SKIN)
        for i in _limb_parts(r, WAR_SKIN):
            if r.parts[i]["limb"][5] > r.parts[i]["limb"][4]:   # arm: leather bracer, iron armband
                _wrap(r, i, WAR_STRAP, 0.62, 0.86, studs=WAR_IRON.hi)
                _wrap(r, i, WAR_BAND, 0.2, 0.3)
                _joint(r, i, 0.47, 3)                           # elbow crease
            else:
                _joint(r, i, 0.62, 4)                           # kneecap
        for cx_, cy_, a, b in _ellipses:                       # knuckles on each fist
            if (a, b) == (3, 3):
                hx2, hy2 = int(_c(cx_)), int(_c(cy_))
                for kx in range(hx2 - 3, hx2 + 4, 2):
                    _paint(r, {(kx, hy2 - 2)}, WAR_SKIN.lo)
                    _paint(r, {(kx, hy2 - 3)}, WAR_SKIN.mid_hi)
        for pts in _parts_of(r, orc.LEATHER, 20).values():     # boot straps
            x0, y0, x1, y1 = _box(pts)
            if y1 - y0 <= 6 and x1 - x0 <= 14 and y0 > 100:
                _seam_row(r, pts, y0 + 2, orc.LEATHER)
        for pts in _parts_of(r, HORN, 6).values():             # growth ridges across each horn
            for x, y in pts:
                if y % 3 == 0 and (x, y + 1) in r.lab:
                    _paint(r, {(x, y)}, HORN.lo)
        for pts in _parts_of(r, WAR_IRON).values():             # rivets along the helm band
            bx0, by0, bx1, by1 = _box(pts)
            if by1 - by0 <= 4 and bx1 - bx0 >= 12:
                for x in range(bx0 + 2, bx1 - 1, 4):
                    _paint(r, {(x, by0 + 1)}, WAR_IRON.hi)
                    _paint(r, {(x + 1, by0 + 2)}, WAR_IRON.lo)
        for pts in _parts_of(r, orc.LEATHER, 12).values():      # strands in the topknot
            kx0, ky0, kx1, ky1 = _box(pts)
            if ky1 < 50:
                for x, y in pts:
                    if (x - y) % 3 == 0 and _inside(set(pts), x, y):
                        _paint(r, {(x, y)}, orc.LEATHER.lo)
        if torso:
            _orc_muscles(r, P, torso)
            _tooth_necklace(r, P, torso)
            x0, y0, x1, y1 = _box(torso)
            sx = {"down": x0 + 4, "up": x1 - 12}.get(P.d, x0 + 6)   # across the shoulder, clear of the pauldron
            _stitched_scar(r, set(torso), (sx, y0 + 3), (sx + 5, y0 + 10))
        if P.d != "up":                                         # old cut across the left eye
            hx_, hy = _head(5, 5)
            hcx, hcy = int(_c(hx_)), int(_c(hy))
            head = {p for p, i in r.lab.items() if r.parts[i]["mat"] is WAR_SKIN and abs(p[0] - hcx) <= 11 and abs(p[1] - hcy) <= 11}
            ex = hcx - 5 if P.d == "down" else hcx + 4
            _stitched_scar(r, head, (ex - 3, hcy - 8), (ex + 2, hcy + 5))
        for i, pts in _parts_of(r, orc.LEATHER, 20).items():   # belt: the wide, short strip
            x0, y0, x1, y1 = _box(pts)
            if y1 - y0 <= 5 and x1 - x0 >= 12:
                own = set(pts)
                my = (y0 + y1) // 2
                for x in range(x0 + 2, x1 - 1, 4):            # studs along the belt
                    if _inside(own, x, my):
                        _paint(r, {(x, my)}, WAR_IRON.hi)
                        _paint(r, {(x + 1, my + 1)}, WAR_IRON.lo)
                if P.d == "up":
                    continue
                bx = (x0 + x1) // 2 if P.d == "down" else x1 - 4
                frame = m_rect(bx - 3, y0, bx + 3, y1) - m_rect(bx - 1, y0 + 1, bx + 1, y1 - 1)
                r.dot(_hi({p for p in frame if p in r.lab}), WAR_IRON.hi)
                r.dot(_hi({(bx, (y0 + y1) // 2)}), WAR_IRON.lo)
        si, skirt = _biggest(r, orc.LEATHER)
        if skirt:
            _folds(r, skirt, orc.LEATHER, 4, phase=P.p)
            sy = min(y for _, y in skirt) + 3          # running stitch under the belt
            for x, y in skirt:
                if y == sy and _inside(set(skirt), x, y) and x % 3 != 0:
                    _paint(r, {(x, y)}, orc.LEATHER.hi if x % 3 == 1 else orc.LEATHER.lo)
        for i, pts in _parts_of(r, WAR_IRON, 60).items():
            x0, y0, x1, y1 = _box(pts)
            if r.parts[i]["rect"]:                      # cleaver: a fuller groove and edge nicks
                own = set(pts)
                if y1 - y0 >= x1 - x0:
                    fx = (x0 + x1) // 2
                    _paint(r, {(fx, y) for y in range(y0 + 3, y1 - 2)} & own, WAR_IRON.lo)
                    _paint(r, {(fx + 1, y) for y in range(y0 + 3, y1 - 2)} & own, WAR_IRON.hi)
                else:
                    fy = (y0 + y1) // 2
                    _paint(r, {(x, fy) for x in range(x0 + 3, x1 - 2)} & own, WAR_IRON.lo)
                    _paint(r, {(x, fy + 1) for x in range(x0 + 3, x1 - 2)} & own, WAR_IRON.hi)
                _paint(r, {(x, y0 + 1) for x in range(x0 + 1, x1)} & own, WAR_IRON.hi)   # lit spine
                _rivets(r, pts, WAR_IRON, 9)
            else:                                       # pauldron: overlapping lames
                for frac in (0.4, 0.75):
                    _seam_row(r, pts, y0 + int((y1 - y0) * frac), WAR_IRON)
                _rivets(r, pts, WAR_IRON, 7)

    return humanoid_sheet(orc.draw, detail, dither=(WAR_SKIN, orc.LEATHER, WAR_IRON))


# ------------------------------------------------------------ Frost Bandit ---

FROST_HOOD = Mat("#a9dcf5", "#6aa8d6", "#3a6694")
FROST_LEATHER = Mat("#76859e", "#525e75", "#30384a")
FROST_STEEL = Mat("#f4fcff", "#c3e6f7", "#7eadc9")
ICE = Mat("#ffffff", "#c8f0ff", "#79b8db")


def frost_crown(r, P):
    for pts in _parts_of(r, FROST_LEATHER, 60, shifted=False).values():
        _seam(r, pts, FROST_LEATHER.lo, FROST_LEATHER.mid_hi)
    for pts in _parts_of(r, FROST_HOOD, 40).values():
        own = set(pts)
        for x, y in pts:                      # fur rim along the bottom edge of hood and cowl
            if (x, y + 1) not in own and (x, y - 1) in own:
                r.dot(_hi({(x, y)}), ICE.hi if (x // 2) % 2 else ICE.mid)
    if P.d == "side":
        hx_, hy = _head(5, 6)
        shards = ((-3, 5, 2), (0, 6, 3), (3, 4, 2))
    else:
        hx_, hy = _head(6, 6)
        shards = ((-4, 4, 2), (0, 6, 3), (4, 4, 2))
    for dx, h, w in shards:
        base_y = hy - 6 + abs(dx) // 2
        r.part(h_poly([(hx_ + dx - w // 2 - 1, base_y), (hx_ + dx + w // 2 + 1, base_y), (hx_ + dx, base_y - h)]), ICE)


FROST_STRAP = Mat("#a3b3c9", "#74849e", "#4b5770")
FUR = Mat("#f4fbff", "#cfe3f0", "#91aec4")


def frost_detail(r, P):
    """Bandolier with a steel buckle, fur cuffs, knee wraps, frost glints, a riveted buckler."""
    ti, torso = _biggest(r, FROST_LEATHER)
    if torso:
        x0, y0, x1, y1 = _box(torso)
        if P.d == "side":
            a, b = ((x0 + x1) // 2, y0 + 1), ((x0 + x1) // 2 + 2, y1 - 1)
        else:
            a, b = (x0 + 3, y0 + 1), (x1 - 3, y1 - 4)
        strap = {p for p in m_line(a[0], a[1], b[0], b[1], 4) if r.lab.get(p) == ti}
        if strap:
            r.part({Hi(p) for p in strap}, FROST_STRAP)
            if P.d == "down":                         # the buckle sits on the chest
                mx, my = (a[0] + b[0]) // 2, (a[1] + b[1]) // 2
                ring = m_rect(mx - 2, my - 2, mx + 2, my + 2) - m_rect(mx - 1, my - 1, mx + 1, my + 1)
                r.dot(_hi({p for p in ring if p in r.lab}), FROST_STEEL.mid_hi)
        for i in _limb_parts(r, FROST_LEATHER):
            lx0, ly0, lx1, ly1, w0, w1 = r.parts[i]["limb"]
            if min(ly0, ly1) >= y1 - 6:               # leg
                _wrap(r, i, FROST_STRAP, 0.4, 0.55)
            else:                                     # arm
                _wrap(r, i, FUR, 0.72, 0.9)
    frost_crown(r, P)
    hi_, hood = _biggest(r, FROST_HOOD)
    if hood:
        x0, y0, x1, y1 = _box(hood)
        own = set(hood)
        for fx, fy in ((0.28, 0.32), (0.72, 0.22), (0.55, 0.62)):
            x, y = int(x0 + (x1 - x0) * fx), int(y0 + (y1 - y0) * fy)
            if _inside(own, x, y):
                _sparkle(r, x, y, ICE.hi, ICE.mid)
    for pts in _parts_of(r, FROST_STEEL, 60).values():
        _rivets(r, pts, FROST_STEEL, 5)


def frost_bandit():
    bd = load_scaled("build_bandit", HOOD=FROST_HOOD, LEATHER=FROST_LEATHER, STEEL=FROST_STEEL,
                     WRAP="#eef7ff", OUT="#141e2b")
    return humanoid_sheet(bd.draw, frost_detail, dither=(FROST_LEATHER, FROST_HOOD))


# -------------------------------------------------------------- Slime King ---
# Slime.png layout (16x2 of 64 px): 0-2 idle down, 3-5 idle up, 6-8 idle side,
# 9-11 / 12-14 / 15-17 walk squash (flat, round, tall) down/up/side,
# 18-20 / 21-23 / 24-26 hit splash (round, peak, droplet), 27-31 unused.

KING_BODY = Mat("#c992f2", "#9455d3", "#5d2e96", rim="#e8c8ff")
KING_BODY.grain = False   # slime is smooth; grain reads as dirt
KING_OUT = "#1c0b2b"
KING_EYE = "#1c0b2b"
KING_PUPIL = "#ffe14d"
GEM = "#ff4d63"
FLOOR = 110          # lowest body row; the outline sits on 111 like Slime.png's row 55


def _dome(cx, rx, top, floor=FLOOR, tuck=7):
    """Gumdrop: a round top half, a flatter lower half tucked in toward the floor."""
    h = floor - top
    cy = top + h * 0.58
    upper = {(x, y) for x, y in m_ellipse(cx, cy, rx, h * 0.58) if y <= cy}
    lower = {(x, y) for x, y in m_ellipse(cx, cy, rx, floor - cy + tuck) if cy < y <= floor}
    return {(x, y) for x, y in upper | lower if y >= top}


def _sheen(r, cx, rx, top, floor=FLOOR):
    """Soft lit cap on the upper-left, like Slime.png's light top band."""
    h = floor - top
    cap = m_ellipse(cx - rx * 0.25, top + h * 0.28, rx * 0.55, h * 0.2)
    r.dot({p for p in cap if p in r.lab}, KING_BODY.mid_hi)


def _crown(r, cx, top, w, lift=0, tilt=0):
    base = top + 7 - lift
    half = w // 2
    band = m_rect(cx - half, base - 4, cx + half, base)
    spikes = set()
    for k, dx in enumerate((-half, 0, half)):
        tall = 9 if k == 1 else 7
        spikes |= m_poly([(cx + dx - 3, base - 3), (cx + dx + 3, base - 3), (cx + dx + tilt, base - 3 - tall)])
    r.part(band | spikes, GOLD)
    r.dot({(cx, base - 2), (cx + 1, base - 2), (cx, base - 3), (cx + 1, base - 3)}, GEM)
    for dx in (-half + 3, half - 3):
        r.dot({(cx + dx, base - 2)}, GEM)


def _face(r, cx, rx, top, view):
    eye_y = top + int((FLOOR - top) * 0.5)
    sides = (-1, 1) if view == "down" else ((1,) if view == "side" else ())
    for s in sides:
        ex = cx + (int(rx * 0.55) if view == "side" else s * max(7, rx // 3))
        d = 1 if view == "side" else s
        r.dot(m_poly([(ex - 5 * d, eye_y - 3), (ex + 4 * d, eye_y), (ex + 4 * d, eye_y + 4), (ex - 4 * d, eye_y + 3)]), KING_EYE)
        r.dot(m_rect(ex, eye_y + 1, ex + d, eye_y + 2), KING_PUPIL)


def _glint(r, cx, rx, top):
    gx, gy = cx - rx // 3, top + 6
    r.dot({(gx, gy), (gx + 1, gy), (gx, gy + 1), (gx - 1, gy), (gx, gy - 1)}, "#ffffff")


def slime_frame(view, kind, k):
    r = Rig(CELL, CELL, outline=KING_OUT)
    cx = 64 if view != "side" else 66
    lift = 0
    drop = None
    if kind == "idle":
        rx, top = (27, 28, 27)[k], (62, 63, 62)[k]
        body = _dome(cx, rx, top)
    elif kind == "walk":
        rx, top = ((33, 68), (27, 62), (21, 54))[k]
        body = _dome(cx, rx, top)
    else:   # hit splash
        rx, top = 27, 58
        body = _dome(cx, rx, top)
        if k >= 1:
            peak_x = cx - 6 if view == "side" else cx
            body |= m_poly([(peak_x - 11, top + 12), (peak_x + 2, top - 12 + 4 * (k - 1)), (peak_x + 11, top + 10)])
            lift = 8 * k
        if k == 2:
            dx = -26 if view == "side" else -8
            drop = m_ellipse(cx + dx, 34, 4, 4)
    r.part(body, KING_BODY, rim=True, band=2)
    if drop:
        r.part(drop, KING_BODY)
    _sheen(r, cx, rx, top)
    _face(r, cx, rx, top, view)
    _glint(r, cx, rx, top)
    _crown(r, cx - (2 if view == "side" else 0), top, 20 if view == "side" else 26, lift, tilt=(1 if kind == "hit" and k else 0))
    return r.render(**PLAYER_STYLE)


def slime_king():
    cells = []
    for kind in ("idle", "walk", "hit"):
        for view in ("down", "up", "side"):
            for k in range(3):
                cells.append(slime_frame(view, kind, k))
    blank = Rig(CELL, CELL).render()
    cells += [blank] * (32 - len(cells))
    out = sheet(cells, 16, CELL, CELL)
    assert out.size == (16 * CELL, 2 * CELL)
    return out


# --- Slime King minions: 64 px cells at 1x, shown at net 1.0 on split children.
MINION_CELL = 64
MINION_FLOOR = 54    # lowest body row; the outline sits on 55 like Slime.png


def _minion_helmet(r, cx, top, rx, view, lift=0):
    """Small gold guard helmet: a cap over the crown of the dome, a brim band,
    a nose guard and a red stud on the front."""
    y0 = top - lift
    brim = y0 + 5
    hw = max(6, int(rx * 0.7))
    cap = {(x, y) for x, y in m_ellipse(cx, brim, hw, 7) if y <= brim}
    band = m_rect(cx - hw - 1, brim, cx + hw + 1, brim + 1)
    r.part(cap | band, GOLD)
    if view == "up":
        return
    nose_x = cx + (hw // 2 if view == "side" else 0)
    r.dot(m_rect(nose_x, brim + 2, nose_x, brim + 4), GOLD.lo)
    stud_x = nose_x if view != "side" else cx + hw // 2 - 3
    r.dot({(stud_x, brim - 3), (stud_x + 1, brim - 3), (stud_x, brim - 2), (stud_x + 1, brim - 2)}, GEM)
    r.dot({(cx - hw // 2, brim - 4)}, GOLD.hi)


def _minion_face(r, cx, rx, top, view):
    eye_y = top + int((MINION_FLOOR - top) * 0.55)
    if view == "up":
        return
    xs = (cx + int(rx * 0.5),) if view == "side" else (cx - max(4, rx // 3) - 1, cx + max(4, rx // 3))
    for ex in xs:
        r.dot(m_rect(ex, eye_y, ex + 1, eye_y + 2), KING_EYE)
        r.dot({(ex + 1, eye_y)}, KING_PUPIL)
    mouth_x = xs[0] - 2 if view == "side" else cx
    r.dot({(mouth_x - 1, eye_y + 5), (mouth_x, eye_y + 6), (mouth_x + 1, eye_y + 5)}, KING_EYE)


def minion_frame(view, kind, k):
    r = Rig(MINION_CELL, MINION_CELL, outline=KING_OUT)
    cx = 32 if view != "side" else 33
    lift = 0
    if kind == "idle":
        rx, top = (12, 13, 12)[k], (31, 32, 31)[k]
        body = _dome(cx, rx, top, MINION_FLOOR, 4)
    elif kind == "walk":
        rx, top = ((15, 34), (12, 31), (10, 27))[k]
        body = _dome(cx, rx, top, MINION_FLOOR, 4)
    else:   # hit: a squash with a splash peak, the helmet knocked up
        rx, top = 13, 30
        body = _dome(cx, rx, top, MINION_FLOOR, 4)
        if k >= 1:
            peak_x = cx - 3 if view == "side" else cx
            body |= m_poly([(peak_x - 5, top + 6), (peak_x + 1, top - 6 + 2 * (k - 1)), (peak_x + 5, top + 5)])
            lift = 4 * k
    body_idx = r.part(body, KING_BODY, rim=True, band=1)
    _minion_helmet(r, cx - (1 if view == "side" else 0), top, rx, view, lift)
    # Sheen and glint only on slime pixels, so the helmet stays whole.
    h = MINION_FLOOR - top
    cap = m_ellipse(cx - rx * 0.25, top + h * 0.3, rx * 0.55, h * 0.18)
    r.dot({p for p in cap if r.lab.get(p) == body_idx}, KING_BODY.mid_hi)
    glint = {(cx - rx // 3 - 1, top + h // 2 - 3), (cx - rx // 3, top + h // 2 - 3)}
    r.dot({p for p in glint if r.lab.get(p) == body_idx}, "#ffffff")
    _minion_face(r, cx, rx, top, view)
    return r.render(**PLAYER_STYLE)


def slime_minion():
    cells = []
    for kind in ("idle", "walk", "hit"):
        for view in ("down", "up", "side"):
            for k in range(3):
                cells.append(minion_frame(view, kind, k))
    blank = Rig(MINION_CELL, MINION_CELL).render()
    cells += [blank] * (32 - len(cells))
    out = sheet(cells, 16, MINION_CELL, MINION_CELL)
    assert out.size == (16 * MINION_CELL, 2 * MINION_CELL)
    return out


BOSSES = {
    "slime_king": slime_king,
    "slime_minion": slime_minion,
    "bone_captain": bone_captain,
    "orc_warlord": orc_warlord,
    "frost_bandit": frost_bandit,
}


if __name__ == "__main__":
    os.makedirs(rp(OUT_DIR), exist_ok=True)
    for name, build in BOSSES.items():
        img = build()
        dst = rp(f"{OUT_DIR}/{name}.png")
        img.save(dst)
        print("✅ wrote", dst, img.size)
        if "--preview" in sys.argv:
            from preview import on_grass
            on_grass(img, 2).save(os.path.join(sys.argv[sys.argv.index("--preview") + 1], f"{name}.png"))
