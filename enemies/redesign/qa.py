"""qa.py — build QA montages and report sheet stats for one enemy sheet."""
import collections
import os
import sys
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from artlib import direction_of, phase_of, TRANSPARENT, rp

DIRS = ["down", "up", "side"]


def sheet_stats(sheet):
    cnt = collections.Counter(sheet.getdata())
    colors = [c for c in cnt if c[3] > 0]
    return len(colors), cnt


def cell_bbox(cell_img):
    minx, miny, maxx, maxy = 99, 99, -1, -1
    px = cell_img.load()
    for y in range(64):
        for x in range(64):
            if px[x, y][3]:
                minx = min(minx, x); miny = min(miny, y)
                maxx = max(maxx, x); maxy = max(maxy, y)
    return (minx, miny, maxx, maxy) if maxx >= 0 else None


def report(sheet, name, goblin_baselines):
    n_colors, cnt = sheet_stats(sheet)
    print(f"[{name}] colors={n_colors} (limit 24)")
    for d in DIRS:
        idxs = [i for i in range(24) if direction_of(i) == d and i < 12]
        bottoms = []
        for i in idxs:
            cx = (i % 8) * 64; cy = (i // 8) * 64
            bb = cell_bbox(sheet.crop((cx, cy, cx + 64, cy + 64)))
            bottoms.append(bb[3] if bb else None)
        gb = goblin_baselines[d]
        ok = all(b is not None and abs(b - gb) <= 2 for b in bottoms)
        print(f"[{name}] {d}: bottoms={bottoms} goblin={gb} {'OK' if ok else 'BASELINE MISS'}")
    empties = []
    for i in range(24):
        cx = (i % 8) * 64; cy = (i // 8) * 64
        if cell_bbox(sheet.crop((cx, cy, cx + 64, cy + 64))) is None:
            empties.append(i)
    print(f"[{name}] empty cells: {empties or 'none'}")
    return n_colors, empties


def montage(sheet, name, path):
    """Rows: 1x on light bg, 1x on dark bg, 4x key cells, black silhouettes 1x."""
    W = 512
    rows = []
    for bg in [(208, 208, 216, 255), (32, 32, 40, 255)]:
        row = Image.new("RGBA", (W, 64), bg)
        row.alpha_composite(sheet)
        rows.append(row)
    # 4x key cells (walk+chase per direction)
    key = [0, 8, 4, 12, 20, 16]
    z = 4
    row = Image.new("RGBA", (64 * z * len(key), 64 * z), (208, 208, 216, 255))
    for k, i in enumerate(key):
        cx = (i % 8) * 64; cy = (i // 8) * 64
        c = sheet.crop((cx, cy, cx + 64, cy + 64)).resize((64 * z, 64 * z), Image.NEAREST)
        row.paste(c, (k * 64 * z, 0))
    rows.append(row)
    # silhouettes: all 24 cells filled black
    sil = Image.new("RGBA", (W, 192), (208, 208, 216, 255))
    spx = sheet.load()
    for y in range(192):
        for x in range(512):
            if spx[x, y][3]:
                sil.putpixel((x, y), (10, 10, 12, 255))
    rows.append(sil.crop((0, 0, W, 64)))
    W_out = max([W] + [r.width for r in rows])
    H = sum(r.height + 4 for r in rows)
    out = Image.new("RGBA", (W_out, H), (255, 255, 255, 255))
    y = 0
    for r in rows:
        out.paste(r, (0, y))
        y += r.height + 4
    out.save(path)
    print(f"[{name}] montage -> {path}")


def goblin_baselines():
    g = Image.open(rp("enemies/goblin/goblin.png")).convert("RGBA")
    out = {}
    for d in DIRS:
        idxs = [i for i in range(12) if direction_of(i) == d]
        bottoms = []
        for i in idxs:
            cx = (i % 8) * 64; cy = (i // 8) * 64
            bb = cell_bbox(g.crop((cx, cy, cx + 64, cy + 64)))
            bottoms.append(bb[3])
        out[d] = max(set(bottoms), key=bottoms.count)
    return out
