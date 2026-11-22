"""artlib.py — pixel-edit DSL for the enemy identity rework.

Paths resolve against the repo root (two levels up from this file) so scripts
can run from anywhere.

Starts from the project's own Goblin sheet (pose + timing base only) and applies
deliberate structural edits: silhouette reshaping, head/gear replacement, and a
full color-ramp rebuild per enemy. No external art is used.

Cell geometry (64x64), measured from the Goblin sheet:
  down (0-3,12-15): head x22-41 y16-33, ears to x18/x45, eyes (27,25),(35,25),
                    weapon shaft x21-24 y33-51 + tip x21-27 y49-58,
                    torso x25-38 y33-44, cloth x24-39 y43-50, legs y50-56
  up   (4-7,16-19): head x22-41 y14-30, weapon shaft x40-44 y18-48 + tip y13-21,
                    torso y30-43, cloth y42-48, legs y48-56
  side (8-11,20-23):head x20-33 y17-31 (nose right), eye (28,24),
                    shaft y34-38 x20-50 + tip x43-52 y30-41,
                    torso x22-35 y31-44, cloth y43-49, legs x24-36 y49-56
Feet baseline (lowest opaque pixel): down 56, up 48... measured at runtime.
"""

from PIL import Image
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def rp(path):
    return os.path.join(ROOT, path)


TRANSPARENT = (0, 0, 0, 0)

# Goblin source colors
G_OUTLINE = (46, 40, 17, 255)
G_SKIN_L = (163, 146, 99, 255)
G_SKIN_M = (113, 100, 49, 255)
G_SKIN_H = (202, 181, 145, 255)
G_BLACK = (0, 0, 0, 255)
G_CLOTH = (69, 40, 60, 255)     # loincloth purple
G_LEATHER = (113, 77, 49, 255)  # straps/brown
G_GRAY = (89, 86, 82, 255)      # weapon shaft
G_WHITE = (255, 255, 255, 255)  # tip sparkle
G_STEEL = (155, 173, 183, 255)  # steel light
G_YELLOW = (255, 201, 82, 255)  # eyes
GOBLIN_COLORS = [G_OUTLINE, G_SKIN_L, G_SKIN_M, G_SKIN_H, G_BLACK, G_CLOTH,
                 G_LEATHER, G_GRAY, G_WHITE, G_STEEL, G_YELLOW]


def load_cells(path):
    img = Image.open(rp(path)).convert("RGBA")
    cells = []
    for i in range(24):
        cx = (i % 8) * 64
        cy = (i // 8) * 64
        cells.append(img.crop((cx, cy, cx + 64, cy + 64)))
    return cells


def direction_of(idx):
    col = idx % 8
    row = idx // 8
    if col < 4:
        return "down" if row == 0 else "up"
    return "side"


def phase_of(idx):
    return idx % 4


class Cell:
    def __init__(self, img):
        self.img = img
        self.px = img.load()

    def get(self, x, y):
        if 0 <= x < 64 and 0 <= y < 64:
            return self.px[x, y]
        return TRANSPARENT

    def set(self, x, y, c):
        if 0 <= x < 64 and 0 <= y < 64:
            self.px[x, y] = c

    def is_empty(self, x, y):
        return self.get(x, y)[3] == 0

    def remap(self, table):
        for y in range(64):
            for x in range(64):
                c = self.px[x, y]
                if c in table:
                    self.px[x, y] = table[c]

    def erase(self, pts):
        for x, y in pts:
            self.set(x, y, TRANSPARENT)

    # --- mask primitives (return sets of (x,y)) ---
    @staticmethod
    def m_rect(x0, y0, x1, y1):
        return {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}

    @staticmethod
    def m_disc(cx, cy, r):
        pts = set()
        for y in range(cy - r - 1, cy + r + 2):
            for x in range(cx - r - 1, cx + r + 2):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    pts.add((x, y))
        return pts

    @staticmethod
    def m_ellipse(cx, cy, rx, ry):
        pts = set()
        for y in range(cy - ry - 1, cy + ry + 2):
            for x in range(cx - rx - 1, cx + rx + 2):
                if ((x - cx) ** 2) / max(rx * rx, 1) + ((y - cy) ** 2) / max(ry * ry, 1) <= 1.0:
                    pts.add((x, y))
        return pts

    @staticmethod
    def m_poly(pts):
        """Filled polygon, even-odd scanline fill."""
        ys = [p[1] for p in pts]
        out = set()
        y_min, y_max = min(ys), max(ys)
        n = len(pts)
        for y in range(y_min, y_max + 1):
            xc = []
            for i in range(n):
                x1, y1 = pts[i]
                x2, y2 = pts[(i + 1) % n]
                if (y1 <= y < y2) or (y2 <= y < y1):
                    t = (y - y1) / (y2 - y1)
                    xc.append(x1 + t * (x2 - x1))
            xc.sort()
            for a in range(0, len(xc) - 1, 2):
                for x in range(int(xc[a] + 0.5), int(xc[a + 1] + 0.5) + 1):
                    out.add((x, y))
        return out

    @staticmethod
    def m_line(x0, y0, x1, y1, w=1):
        pts = set()
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

    @staticmethod
    def _dilate(pts):
        out = set()
        for x, y in pts:
            for ox in (-1, 0, 1):
                for oy in (-1, 0, 1):
                    out.add((x + ox, y + oy))
        return out

    def stamp(self, pts, color, outline=None):
        """Paint pts with color; if outline given, paint 1px outline only into
        currently-transparent pixels around the shape."""
        pts = {(x, y) for x, y in pts if 0 <= x < 64 and 0 <= y < 64}
        if outline is not None:
            for x, y in self._dilate(pts) - pts:
                if self.is_empty(x, y):
                    self.px[x, y] = outline
        for x, y in pts:
            self.px[x, y] = color

    def stamp_ramp(self, layers):
        """layers: list of (pts, color, outline_or_None) applied in order."""
        for pts, color, outline in layers:
            self.stamp(pts, color, outline)

    def shift_region(self, x0, y0, x1, y1, dx, dy):
        region = {}
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                c = self.get(x, y)
                if c[3]:
                    region[(x, y)] = c
        if not region:
            return
        for x, y in region:
            self.set(x, y, TRANSPARENT)
        for (x, y), c in region.items():
            self.set(x + dx, y + dy, c)

    def opaque_bbox(self):
        minx, miny, maxx, maxy = 99, 99, -1, -1
        for y in range(64):
            for x in range(64):
                if self.px[x, y][3]:
                    minx = min(minx, x)
                    miny = min(miny, y)
                    maxx = max(maxx, x)
                    maxy = max(maxy, y)
        return (minx, miny, maxx, maxy) if maxx >= 0 else None


def compose_sheet(cells):
    sheet = Image.new("RGBA", (512, 192), TRANSPARENT)
    for i, c in enumerate(cells):
        sheet.paste(c, ((i % 8) * 64, (i // 8) * 64))
    return sheet
