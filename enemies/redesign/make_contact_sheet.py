"""make_contact_sheet.py — enemies/redesign/contact_sheet.png

Per the workflow contract: rows at 1x (light + dark bg), a 4x detail row per
enemy, and a black-silhouette row per enemy (the pass-bar test).
"""
import os
import sys
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from artlib import rp

ENEMIES = ["goblin", "bandit", "skeleton", "orc"]
Z4 = 4
KEY_CELLS = [0, 8, 4, 12, 20, 16]  # down, side, up walk + chase

rows = []
for name in ENEMIES:
    sheet = Image.open(rp(f"enemies/{name}/{name}.png")).convert("RGBA")
    # 1x on light bg
    r = Image.new("RGBA", (512, 64), (208, 208, 216, 255))
    r.alpha_composite(sheet)
    rows.append((f"{name} 1x light", r))
    # 1x on dark bg
    r = Image.new("RGBA", (512, 64), (32, 32, 40, 255))
    r.alpha_composite(sheet)
    rows.append((f"{name} 1x dark", r))
    # 4x key cells
    r = Image.new("RGBA", (64 * Z4 * len(KEY_CELLS), 64 * Z4), (208, 208, 216, 255))
    for k, i in enumerate(KEY_CELLS):
        cx, cy = (i % 8) * 64, (i // 8) * 64
        c = sheet.crop((cx, cy, cx + 64, cy + 64)).resize((64 * Z4, 64 * Z4), Image.NEAREST)
        r.paste(c, (k * 64 * Z4, 0))
    rows.append((f"{name} 4x", r))
    # black silhouettes, 2x for legibility (all three sheet rows)
    Z2 = 2
    px = sheet.load()
    sil = Image.new("RGBA", (512, 192), (0, 0, 0, 0))
    sp = sil.load()
    for y in range(192):
        for x in range(512):
            if px[x, y][3]:
                sp[x, y] = (8, 8, 10, 255)
    r = Image.new("RGBA", (512 * Z2, 192 * Z2), (215, 215, 222, 255))
    r.paste(sil.resize((512 * Z2, 192 * Z2), Image.NEAREST), (0, 0))
    rows.append((f"{name} silhouettes 2x", r))

W = max(r.width for _, r in rows) + 140
H = sum(r.height + 6 for _, r in rows) + 10
out = Image.new("RGBA", (W, H), (255, 255, 255, 255))
y = 6
from PIL import ImageDraw
d = ImageDraw.Draw(out)
for label, r in rows:
    d.text((4, y + 4), label, fill=(20, 20, 30, 255))
    out.paste(r, (136, y))
    y += r.height + 6
out.save(rp("enemies/redesign/contact_sheet.png"))
print("wrote enemies/redesign/contact_sheet.png", out.size)
