"""render_arenas.py — composite each arena (tiles + props) to PNG for review.

    python3.13 tools/arena_build/render_arenas.py --all        # all four arenas
    python3.13 tools/arena_build/render_arenas.py 2            # just arena_02

Writes tools/arena_build/preview/arena_0N.png (1x, 640x480) and
arena_0N_3x.png, plus overview.png (all four at 1x). Each render mimics
the game: ground tinted by the arena's ground_tint (TileMapLayer modulate),
props y-sorted by their node position, a player and a goblin dropped in for
scale (player on the SpawnPoint), the WaveLabel text in its real band
(y 56-84), and a faint outline of the 96 px spawn ring.
"""
from __future__ import annotations

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_arenas as B  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

ROOT = B.ROOT
OUT_DIR = os.path.join(HERE, "preview")


def tint(img, t):
    r, g, b, a = img.split()
    f = lambda ch, k: ch.point(lambda v: min(255, int(v * k + 0.5)))
    return Image.merge("RGBA", (f(r, t[0]), f(g, t[1]), f(b, t[2]), a))


def render(i, with_refs=True, with_label=True, with_ring=True):
    m = B.parse(B.MAPS[i])
    lay, errs = B.layout(m, i)
    assert lay, errs
    atlas = Image.open(os.path.join(ROOT, "tile_maps", "sprites", "Grass-01.png")).convert("RGBA")
    props = Image.open(os.path.join(ROOT, "props", "Sprites", "Props.png")).convert("RGBA")
    ground = Image.new("RGBA", (640, 480), (0, 0, 0, 255))
    for x, y, ax, ay in lay["cells"]:
        ground.alpha_composite(atlas.crop((ax * 32, ay * 32, ax * 32 + 32, ay * 32 + 32)), (x * 32, y * 32))
    canvas = tint(ground, m["tint"])
    draws = []    # (sort_y, image, (x, y))
    for p in lay["props"]:
        f = p["frame"]
        art = props.crop(((f % 16) * 64, (f // 16) * 64, (f % 16) * 64 + 64, (f // 16) * 64 + 64))
        cx = p["x"] * 32 + p["w"] * 16
        if p["flat"]:
            pos_y, centre_y = p["y"] * 32, p["y"] * 32
        else:
            pos_y, centre_y = p["y"] * 32 + 16, p["y"] * 32
        draws.append((pos_y, art, (int(cx - 32), int(centre_y - 32))))
    if with_refs:
        player = Image.open(os.path.join(ROOT, "player", "Sprites", "PlayerSprite02.png")).convert("RGBA").crop((0, 0, 64, 64))
        gob = Image.open(os.path.join(ROOT, "enemies", "goblin", "goblin.png")).convert("RGBA").crop((0, 0, 64, 64))
        sx, sy = m["spawn"]
        # player Sprite2D sits ~20 px above its feet (feet at row 54 of the 64 cell)
        draws.append((sy, player, (int(sx - 32), int(sy - 54))))
        gx, gy = sx + 150, sy + 60
        draws.append((gy, gob, (int(gx - 32), int(gy - 56))))
    for _y, art, at in sorted(draws, key=lambda d: d[0]):
        canvas.alpha_composite(art, at)
    d = ImageDraw.Draw(canvas)
    if with_ring:
        sx, sy = m["spawn"]
        d.ellipse((sx - 96, sy - 96, sx + 96, sy + 96), outline=(255, 255, 255, 90))
    if with_label:
        try:
            font = ImageFont.truetype(os.path.join(ROOT, "gui", "fonts", "Abaddon Bold.ttf"), 18)
        except OSError:
            font = ImageFont.load_default()
        text = f"Stage {1 + 20 * i} - {m['name']}"
        tw = d.textlength(text, font=font)
        tx, ty = 320 - tw / 2, 60
        for ox in (-2, -1, 0, 1, 2):
            for oy in (-2, -1, 0, 1, 2):
                d.text((tx + ox, ty + oy), text, font=font, fill=(0, 0, 0, 255))
        d.text((tx, ty), text, font=font, fill=(255, 255, 255, 255))
    return canvas.convert("RGB")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    which = range(4) if "--all" in sys.argv or not args else [int(a) - 1 for a in args]
    shots = []
    for i in which:
        img = render(i)
        p1 = os.path.join(OUT_DIR, f"arena_0{i + 1}.png")
        p3 = os.path.join(OUT_DIR, f"arena_0{i + 1}_3x.png")
        img.save(p1)
        img.resize((1920, 1440), Image.NEAREST).save(p3)
        shots.append(img)
        print("✅ wrote", os.path.relpath(p1, ROOT), "and", os.path.relpath(p3, ROOT))
    if len(shots) == 4:
        ov = Image.new("RGB", (1290, 970), (20, 20, 20))
        for k, img in enumerate(shots):
            ov.paste(img, ((k % 2) * 650, (k // 2) * 490))
        ov.save(os.path.join(OUT_DIR, "overview.png"))
        print("✅ wrote", os.path.relpath(os.path.join(OUT_DIR, "overview.png"), ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
