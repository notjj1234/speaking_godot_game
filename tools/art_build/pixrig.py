"""pixrig.py — deterministic part-rig pixel renderer for Loqui Quest art.

No image model: every sprite is built from layered vector-ish parts (polygons,
ellipses, thick lines) rasterised onto a small grid, then shaded and outlined
with fixed rules so every frame of a creature reads the same way:

* light comes from the top-left: a part's pixels near its up/left edge take the
  ramp's light tone, pixels near its down/right edge take the dark tone;
* each material is a 3-tone ramp (light, mid, dark) plus an optional rim tone;
* where a part sits in front of a different part, the pixels of the part behind
  that touch it are darkened (that is what "connects" a hand to a grip or a head
  to a neck without a gap: parts overlap and get a contact shadow, never a hole);
* the silhouette gets a 1 px outline: the palette's darkest colour on the
  shadow side (down/right), the touching material's dark tone on the lit side
  (selective outline).

Conventions follow enemies/redesign/artlib.py (64 px cells, sets of (x, y)
points as masks) and tools/enemy_sprite_harden/PALETTE.md (outline #150918
preferred, never pure #000000 as fill).
"""
from __future__ import annotations

import math
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def rp(path: str) -> str:
    return os.path.join(ROOT, path)


def hx(h: str) -> tuple:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


class Mat:
    """A material: 3-tone ramp (+ optional rim light)."""

    def __init__(self, hi: str, mid: str, lo: str, rim: str | None = None, flat: bool = False):
        self.hi = hx(hi)
        self.mid = hx(mid)
        self.lo = hx(lo)
        self.rim = hx(rim) if rim else None
        self.flat = flat
        # detail-mode grain; turn off for faces and clean whites, which read dirty
        self.grain = True

    def tone(self, name: str):
        return {"hi": self.hi, "mid": self.mid, "lo": self.lo, "rim": self.rim or self.hi}[name]

    @property
    def mid_hi(self):
        return _mix(self.hi, self.mid)

    @property
    def mid_lo(self):
        return _mix(self.mid, self.lo)


def _mix(a, b):
    return ((a[0] + b[0]) // 2, (a[1] + b[1]) // 2, (a[2] + b[2]) // 2, 255)


# ----------------------------------------------------------------- masks ---

def m_rect(x0, y0, x1, y1):
    return {(x, y) for x in range(min(x0, x1), max(x0, x1) + 1) for y in range(min(y0, y1), max(y0, y1) + 1)}


def m_ellipse(cx, cy, rx, ry):
    pts = set()
    for y in range(int(math.floor(cy - ry - 1)), int(math.ceil(cy + ry + 2))):
        for x in range(int(math.floor(cx - rx - 1)), int(math.ceil(cx + rx + 2))):
            if ((x - cx) ** 2) / max(rx * rx, 0.25) + ((y - cy) ** 2) / max(ry * ry, 0.25) <= 1.0:
                pts.add((x, y))
    return pts


def m_poly(pts):
    """Filled polygon (even-odd scanline), vertices may be floats."""
    ys = [p[1] for p in pts]
    out = set()
    n = len(pts)
    for y in range(int(math.floor(min(ys))), int(math.ceil(max(ys))) + 1):
        yc = y + 0.5
        xc = []
        for i in range(n):
            x1, y1 = pts[i]
            x2, y2 = pts[(i + 1) % n]
            if (y1 <= yc < y2) or (y2 <= yc < y1):
                xc.append(x1 + (yc - y1) / (y2 - y1) * (x2 - x1))
        xc.sort()
        for a in range(0, len(xc) - 1, 2):
            for x in range(int(math.floor(xc[a] + 0.5)), int(math.floor(xc[a + 1] - 0.5)) + 1):
                out.add((x, y))
    # make sure thin polygons keep their vertices
    for x, y in pts:
        out.add((int(round(x)), int(round(y))))
    return out


def m_line(x0, y0, x1, y1, w=1):
    pts = set()
    x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
    dx = abs(x1 - x0)
    dy = -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    x, y = x0, y0
    offs = list(range(-(w // 2), w - (w // 2)))
    while True:
        for ox in offs:
            for oy in offs:
                pts.add((x + ox, y + oy))
        if x == x1 and y == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x += sx
        if e2 <= dx:
            err += dx
            y += sy
    return pts


def m_limb(x0, y0, x1, y1, w0, w1=None):
    """Tapered limb as a quad from (x0,y0) width w0 to (x1,y1) width w1."""
    w1 = w0 if w1 is None else w1
    ang = math.atan2(y1 - y0, x1 - x0)
    nx, ny = -math.sin(ang), math.cos(ang)
    h0, h1 = (w0 - 1) / 2.0, (w1 - 1) / 2.0
    quad = [(x0 + nx * h0, y0 + ny * h0), (x1 + nx * h1, y1 + ny * h1),
            (x1 - nx * h1, y1 - ny * h1), (x0 - nx * h0, y0 - ny * h0)]
    pts = m_poly(quad) | m_line(x0, y0, x1, y1, 1)
    if w0 >= 2 or w1 >= 2:
        pts |= m_line(x0, y0, x1, y1, max(1, min(w0, w1)))
    return pts


def shift(pts, dx, dy):
    return {(x + dx, y + dy) for x, y in pts}


def mirror(pts, cx2):
    """Mirror across x = cx2/2 (pass 2*centre so half-pixel centres work)."""
    return {(cx2 - x, y) for x, y in pts}


# ---------------------------------------------------------------- canvas ---

class Rig:
    def __init__(self, w=64, h=64, outline="#150918"):
        self.w, self.h = w, h
        self.outline = hx(outline)
        self.lab = {}          # (x,y) -> part index
        self.parts = []        # list of dict(mat, tone, order, shade, sep)
        self.over = {}         # (x,y) -> explicit colour painted after shading

    def part(self, pts, mat: Mat, tone: str | None = None, shade: str = "auto", sep: bool = True, rim: bool = False, band: int = 1):
        """Add a part. tone forces one ramp tone (detail strokes); shade='round'
        adds a lower-body shadow for domes; sep=False skips the contact line;
        band widens the light/dark edge bands (portrait-sized shapes)."""
        idx = len(self.parts)
        self.parts.append({"mat": mat, "tone": tone, "shade": shade, "sep": sep, "rim": rim, "band": band})
        for x, y in pts:
            if 0 <= x < self.w and 0 <= y < self.h:
                self.lab[(x, y)] = idx
        return idx

    def erase(self, pts):
        for p in pts:
            self.lab.pop(p, None)
            self.over.pop(p, None)

    def dot(self, pts, color):
        """Unshaded detail colour (eyes, rivets, glints) painted last; must sit on a part."""
        c = hx(color) if isinstance(color, str) else color
        for p in pts:
            if p in self.lab:
                self.over[p] = c

    # ------------------------------------------------------------ render ---
    def render(self, outline_mode="selective", detail=False) -> Image.Image:
        """outline_mode "selective" lets lit-side outline pixels take the part's
        dark tone; anything else draws a solid outline (the player's style).
        detail=True is the player-matched shading: two extra blended tones one
        pixel in from the lit/dark edges, a form shadow on the lower body, and
        contact lines in the part's own dark tone (never outline-dark, which
        doubles the line weight)."""
        img = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        px = img.load()
        lab = self.lab
        same = lambda p, i: lab.get(p) == i
        groups = {}
        for p, i in lab.items():
            groups.setdefault(i, []).append(p)
        for i, pts in groups.items():
            info = self.parts[i]
            mat = info["mat"]
            if info["tone"]:
                c = mat.tone(info["tone"])
                for p in pts:
                    px[p] = c
                if detail and len(pts) >= 6 and info["tone"] in ("lo", "hi"):
                    # Forced-tone parts (legs in shadow, lit trims) still get a
                    # 1 px edge band toward mid, so they don't read as flat blocks.
                    edge = _mix(c, mat.mid)
                    for (x, y) in pts:
                        if info["tone"] == "lo":
                            on_edge = not same((x - 1, y), i) or not same((x, y - 1), i)
                        else:
                            on_edge = not same((x + 1, y), i) or not same((x, y + 1), i)
                        if on_edge:
                            px[x, y] = edge
                continue
            ys = [p[1] for p in pts]
            y0, y1 = min(ys), max(ys)
            for (x, y) in pts:
                if mat.flat:
                    px[x, y] = mat.mid
                    continue
                bd = info.get("band", 1)
                lit = any(not same((x - k, y), i) or not same((x, y - k), i) for k in range(1, bd + 1))
                d_dr = 0
                while d_dr < 3 and same((x + d_dr + 1, y + d_dr + 1), i):
                    d_dr += 1
                dk = int(bd * 1.5 + 0.5) if bd > 1 else 1
                dark = any(not same((x + k, y), i) or not same((x, y + k), i) for k in range(1, dk + 1)) or d_dr == 0
                c = mat.mid
                if dark and not lit:
                    c = mat.lo
                elif lit and not dark:
                    c = mat.hi
                elif lit and dark:
                    c = mat.mid
                if info["shade"] == "round" and y1 - y0 >= 5 and y >= y0 + (y1 - y0) * 0.72 and c != mat.hi:
                    c = mat.lo
                if info["rim"] and mat.rim and not same((x + 1, y), i) and y <= y0 + (y1 - y0) * 0.6 and same((x - 1, y), i):
                    c = mat.rim
                if detail and c == mat.mid:
                    lit2 = any(not same((x - k, y), i) or not same((x, y - k), i) for k in range(1, bd + 2))
                    dark2 = any(not same((x + k, y), i) or not same((x, y + k), i) for k in range(1, dk + 2))
                    if lit2 and not dark2:
                        c = mat.mid_hi
                    elif dark2 and not lit2:
                        c = mat.mid_lo
                    elif not lit2 and not dark2 and y1 - y0 >= 6 and y >= y0 + (y1 - y0) * 0.6:
                        c = mat.mid_lo
                px[x, y] = c
        if detail:
            self._grain(px, same)
        # contact lines: a part behind something in front darkens where it touches it
        for (x, y), i in lab.items():
            info = self.parts[i]
            if not info["sep"] or info["tone"]:
                continue
            for q in ((x, y - 1), (x - 1, y), (x + 1, y), (x, y + 1)):
                j = lab.get(q)
                if j is not None and j > i and self.parts[j]["mat"] is not info["mat"]:
                    cur = px[x, y]
                    if detail:
                        px[x, y] = info["mat"].lo
                    else:
                        px[x, y] = self.outline if cur == info["mat"].lo else info["mat"].lo
                    break
        for p, c in self.over.items():
            px[p] = c
        # silhouette outline
        outs = {}
        for (x, y) in lab:
            for q in ((x, y - 1), (x - 1, y), (x + 1, y), (x, y + 1)):
                if q not in lab and 0 <= q[0] < self.w and 0 <= q[1] < self.h:
                    outs.setdefault(q, []).append((x, y))
        for (x, y), srcs in outs.items():
            lit_side = all(sx > x or sy > y for sx, sy in srcs)
            if outline_mode == "selective" and lit_side:
                m = self.parts[lab[srcs[0]]]["mat"]
                px[x, y] = m.lo
            else:
                px[x, y] = self.outline
        return img


    def _grain_hit(self, x, y) -> bool:
        """Which interior pixels take a grain step (subclasses may change density)."""
        return ((x * 73856093) ^ (y * 19349663)) % 7 == 0

    def _grain(self, px, same):
        """Sparse, deterministic one-step-darker pixels inside big parts, so long
        single-tone strips break up the way hand-shaded sprites (goblin) do."""
        for (x, y), i in self.lab.items():
            info = self.parts[i]
            mat = info["mat"]
            if mat.flat or not mat.grain or not all(same(q, i) for q in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1))):
                continue
            if not self._grain_hit(x, y):
                continue
            ramp = [mat.hi, mat.mid_hi, mat.mid, mat.mid_lo, mat.lo]
            cur = px[x, y]
            if cur in ramp[:-1]:
                px[x, y] = ramp[ramp.index(cur) + 1]
            elif cur == mat.lo:
                px[x, y] = mat.mid_lo


def sheet(cells, cols, cw, ch):
    rows = (len(cells) + cols - 1) // cols
    out = Image.new("RGBA", (cols * cw, rows * ch), (0, 0, 0, 0))
    for i, c in enumerate(cells):
        out.paste(c, ((i % cols) * cw, (i // cols) * ch))
    return out
