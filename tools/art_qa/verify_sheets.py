"""verify_sheets.py — measurable art bar for Loqui Quest sprite sheets.

Every check returns (ok, message). verify_all.py runs them all and exits
nonzero on any failure. Pure Pillow, read-only (previews are written by
render_previews()).

Definitions used throughout:
* "opaque colours": distinct RGBA values with alpha > 0 (goblin = 11, slime = 10);
* "feet baseline": bottom of a cell's opaque bbox, exclusive (goblin down = 56);
* silhouette diff: |A xor B| / |A or B| of alpha masks after aligning both
  shapes on their bbox bottom-centre (so a mere offset never counts as "different");
* frame delta: share of pixels whose RGBA differs between two frames, over
  the union of their opaque pixels (raw positions: a bob counts as motion).
"""
from __future__ import annotations

import hashlib
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def rp(p):
    return os.path.join(ROOT, p)


def sha(p):
    return hashlib.sha256(open(rp(p), "rb").read()).hexdigest()


# --------------------------------------------------------------- contracts ---
MAP_8x3 = {"down": [0, 1, 2, 3, 12, 13, 14, 15], "up": [4, 5, 6, 7, 16, 17, 18, 19], "side": [8, 9, 10, 11, 20, 21, 22, 23]}
WALK_8x3 = [[0, 1, 2, 3], [4, 5, 6, 7], [8, 9, 10, 11], [12, 13, 14, 15], [16, 17, 18, 19], [20, 21, 22, 23]]
MAP_16x2 = {"down": [0, 1, 2, 9, 10, 11, 18, 19, 20], "up": [3, 4, 5, 12, 13, 14, 21, 22, 23], "side": [6, 7, 8, 15, 16, 17, 24, 25, 26]}
WALK_16x2 = [[9, 10, 11], [12, 13, 14], [15, 16, 17]]

ENEMIES = {
    # key: (png, tscn, size, cols, rows, cells_used, sprite_scale, baselines, dirmap, walks, rebuilt)
    # NOTE: the task brief listed "scale 0.75" for the 8x3 sheets; the .tscn files say the
    # 0.75 is on ShadowSprite2D — Sprite2D itself has no scale (1.0). Checked as found.
    "goblin": ("enemies/goblin/goblin.png", "enemies/goblin/goblin.tscn", (512, 192), 8, 3, 24, 1.0, {"down": 56, "up": 48, "side": 50}, MAP_8x3, WALK_8x3, False),
    "slime": ("enemies/slime/Slime.png", "enemies/slime/slime.tscn", (1024, 128), 16, 2, 27, 1.0, {"down": 56, "up": 56, "side": 56}, MAP_16x2, WALK_16x2, False),
    "beetle": ("enemies/beetle/Beetle.png", "enemies/beetle/beetle.tscn", (1024, 128), 16, 2, 27, 1.0, {"down": 54, "up": 53, "side": 53}, MAP_16x2, WALK_16x2, True),
    "orc": ("enemies/orc/orc.png", "enemies/orc/orc.tscn", (512, 192), 8, 3, 24, 1.0, {"down": 56, "up": 48, "side": 50}, MAP_8x3, WALK_8x3, True),
    "skeleton": ("enemies/skeleton/skeleton.png", "enemies/skeleton/skeleton.tscn", (512, 192), 8, 3, 24, 1.0, {"down": 56, "up": 48, "side": 50}, MAP_8x3, WALK_8x3, True),
    "bandit": ("enemies/bandit/bandit.png", "enemies/bandit/bandit.tscn", (512, 192), 8, 3, 24, 1.0, {"down": 56, "up": 48, "side": 50}, MAP_8x3, WALK_8x3, True),
}
ANIMS_8x3 = sorted(f"{a}_{d}" for a in ("idle", "walk", "chase", "stun", "destroy") for d in ("down", "side", "up"))
ANIMS_16x2 = sorted([f"{a}_{d}" for a in ("idle", "walk", "stun", "destroy") for d in ("down", "side", "up")] + ["destroy"])

NPC_SHEETS = ["npc/sprites/npc_sprite.png", "npc/sprites/npc_sprite_02.png"]
NPC_PORTRAITS = ["npc/sprites/portraits/npc_portrait_01.png", "npc/sprites/portraits/npc_portrait_02.png"]
NPC_WALKS = [[3, 4, 5, 6], [7, 8, 9, 10], [11, 12, 13, 14]]

FROZEN = {
    "enemies/goblin/goblin.png": "8860fbeb8f7d41601ba9a945042e0781fc7c90c2271e801c92873a89e4e4c61a",
    "enemies/goblin/goblin.tscn": "4bc8554034c9667b2bdfcc11ff302ace7a1e6941bc51aac4e4dd66e31f1269b9",
    "enemies/slime/Slime.png": "9891c14814914b7947b24c9f9fe0afe1f6255bd4a7b60d625057252b585fb858",
    "enemies/slime/slime.tscn": "d88f83d3574965c890efe3a6e81418a9f42b2efb83de601fbe69a1a60f7c489c",
}


# ----------------------------------------------------------------- helpers ---
def load(p):
    return Image.open(rp(p)).convert("RGBA")


def cells_of(img, cols, cw, ch, n):
    return [img.crop(((i % cols) * cw, (i // cols) * ch, (i % cols) * cw + cw, (i // cols) * ch + ch)) for i in range(n)]


def colours(img):
    return {c for c in img.get_flattened_data() if c[3] > 0}


def mask(img):
    w, h = img.size
    a = img.getchannel("A").load()
    return {(x, y) for y in range(h) for x in range(w) if a[x, y]}


def aligned(m):
    if not m:
        return set()
    xs = [p[0] for p in m]
    ys = [p[1] for p in m]
    cx = (min(xs) + max(xs)) // 2
    by = max(ys)
    return {(x - cx, y - by) for x, y in m}


def sil_diff(a, b):
    A, B = aligned(mask(a)), aligned(mask(b))
    u = A | B
    return len(A ^ B) / len(u) if u else 0.0


def frame_delta(a, b):
    pa, pb = a.load(), b.load()
    w, h = a.size
    diff = union = 0
    for y in range(h):
        for x in range(w):
            ca, cb = pa[x, y], pb[x, y]
            if ca[3] or cb[3]:
                union += 1
                if ca != cb:
                    diff += 1
    return diff / union if union else 0.0


def black_share(img):
    data = [c for c in img.get_flattened_data() if c[3] > 0]
    return sum(1 for c in data if c[:3] == (0, 0, 0)) / max(1, len(data))


def dir_of(dirmap, i):
    for d, idx in dirmap.items():
        if i in idx:
            return d
    return None


# --------------------------------------------------------------- measures ---
def measure_enemy(key):
    png, tscn, size, cols, rows, n, scale, bases, dirmap, walks, rebuilt = ENEMIES[key]
    img = load(png)
    cells = cells_of(img, cols, 64, 64, n)
    info = {"key": key, "size": img.size, "colours": len(colours(img)), "black": black_share(img), "cells": cells}
    info["bboxes"] = [c.getbbox() for c in cells]
    ws = [b[2] - b[0] for b in info["bboxes"] if b]
    hs = [b[3] - b[1] for b in info["bboxes"] if b]
    info["art_w"] = (min(ws), max(ws)) if ws else (0, 0)
    info["art_h"] = (min(hs), max(hs)) if hs else (0, 0)
    info["deltas"] = []
    for w in walks:
        seq = w + [w[0]]
        info["deltas"] += [frame_delta(cells[seq[k]], cells[seq[k + 1]]) for k in range(len(w))]
    return info


def goblin_ref_cell(gob_cells, direction, i_in_dir):
    idx = MAP_8x3[direction]
    return gob_cells[idx[i_in_dir % len(idx)]]


def check_enemy(key, gob):
    png, tscn, size, cols, rows, n, scale, bases, dirmap, walks, rebuilt = ENEMIES[key]
    res = []
    info = measure_enemy(key)
    cells = info["cells"]
    res.append((info["size"] == size, f"{key}: sheet {info['size']} == {size} ({cols}x{rows} of 64)"))
    empty = [i for i, b in enumerate(info["bboxes"]) if b is None]
    res.append((not empty, f"{key}: {n} frames non-empty" + (f" (empty: {empty})" if empty else "")))
    if not rebuilt:
        return res, info
    bad = []
    for i, b in enumerate(info["bboxes"]):
        d = dir_of(dirmap, i)
        if b and abs(b[3] - bases[d]) > 1:
            bad.append((i, d, b[3]))
    res.append((not bad, f"{key}: feet baselines {bases} within ±1 on all frames" + (f" — off: {bad}" if bad else "")))
    res.append((10 <= info["colours"] <= 20, f"{key}: opaque colours {info['colours']} in 10-20"))
    res.append((info["black"] <= 0.05, f"{key}: pure-black share {info['black']:.1%} <= 5%"))
    mind = min(info["deltas"])
    res.append((mind >= 0.08, f"{key}: walk/chase frame delta min {mind:.1%} >= 8% (mean {sum(info['deltas']) / len(info['deltas']):.1%})"))
    # silhouette vs goblin, per direction-matched frame
    diffs = []
    for d, idx in dirmap.items():
        for k, i in enumerate(idx):
            diffs.append(sil_diff(cells[i], goblin_ref_cell(gob["cells"], d, k)))
    md = sum(diffs) / len(diffs)
    res.append((md >= 0.25, f"{key}: silhouette diff vs goblin mean {md:.1%} >= 25%"))
    gcol = colours(load(ENEMIES["goblin"][0]))
    ov = len(colours(load(png)) & gcol) / max(1, info["colours"])
    res.append((ov <= 0.60, f"{key}: palette overlap with goblin {ov:.0%} <= 60%"))
    # directions separable from each other (idle frames)
    first = {d: cells[idx[0]] for d, idx in dirmap.items()}
    pairs = [("down", "up"), ("down", "side"), ("up", "side")]
    pd = {f"{a}/{b}": sil_diff(first[a], first[b]) for a, b in pairs}
    res.append((min(pd.values()) >= 0.12, f"{key}: direction silhouettes separable (min {min(pd.values()):.1%} >= 12%) {', '.join(f'{k} {v:.0%}' for k, v in pd.items())}"))
    if key == "beetle":
        okw = 28 <= info["art_w"][0] and info["art_w"][1] <= 34
        okh = 24 <= info["art_h"][0] and info["art_h"][1] <= 30
        res.append((okw and okh, f"beetle: art size w {info['art_w']} in 28-34, h {info['art_h']} in 24-30"))
    return res, info


def check_tscn(key):
    import re
    png, tscn, size, cols, rows, n, scale, bases, dirmap, walks, rebuilt = ENEMIES[key]
    t = open(rp(tscn)).read()
    res = []
    res.append((f'path="res://{png}"' in t, f"{key}.tscn: texture res://{png}"))
    spr = t[t.index('[node name="Sprite2D" type="Sprite2D"'):]
    spr = spr[:spr.index("\n[node", 1)] if "\n[node" in spr[1:] else spr
    hf = re.search(r"hframes = (\d+)", spr)
    vf = re.search(r"vframes = (\d+)", spr)
    sc = re.search(r"scale = Vector2\(([\d.]+), ([\d.]+)\)", spr)
    got_scale = float(sc.group(1)) if sc else 1.0
    res.append((hf and int(hf.group(1)) == cols and vf and int(vf.group(1)) == rows, f"{key}.tscn: hframes/vframes {cols}/{rows}"))
    res.append((abs(got_scale - scale) < 1e-6, f"{key}.tscn: Sprite2D scale {got_scale} == {scale}"))
    if cols == 8:
        sh = t[t.index('[node name="ShadowSprite2D"'):]
        sh = sh[:sh.index("\n[node", 1)]
        res.append(("scale = Vector2(0.75, 0.75)" in sh, f"{key}.tscn: ShadowSprite2D scale 0.75"))
    pos = re.search(r"position = Vector2\(([-\d.]+), ([-\d.]+)\)", spr)
    want_pos = {"beetle": "-19", "slime": None}.get(key, "-14")
    if want_pos:
        res.append((pos and pos.group(2) == want_pos, f"{key}.tscn: Sprite2D position y {pos.group(2) if pos else None} == {want_pos}"))
    names = sorted(set(re.findall(r'resource_name = "(\w+)"', t)) - {"RESET"})
    want = ANIMS_8x3 if cols == 8 else ANIMS_16x2
    res.append((all(a in names for a in want), f"{key}.tscn: {len(want)} animation names present"))
    return res


def check_npcs():
    res = []
    sheets = []
    for p in NPC_SHEETS:
        img = load(p)
        sheets.append(img)
        res.append((img.size == (600, 64), f"{p}: size {img.size} == (600, 64)"))
        cells = cells_of(img, 15, 40, 64, 15)
        bbs = [c.getbbox() for c in cells]
        res.append((all(bbs), f"{p}: 15 frames of 40x64 non-empty"))
        feet = [b[3] for b in bbs if b]
        res.append((all(abs(f - 54) <= 1 for f in feet), f"{p}: feet {min(feet)}-{max(feet)} == 54 ±1"))
        ws = [b[2] - b[0] for b in bbs if b]
        hs = [b[3] - b[1] for b in bbs if b]
        res.append((26 <= min(ws) and max(ws) <= 34 and 44 <= min(hs) and max(hs) <= 48,
                    f"{p}: content w {min(ws)}-{max(ws)} in 26-34, h {min(hs)}-{max(hs)} in 44-48"))
        nc = len(colours(img))
        res.append((22 <= nc <= 32, f"{p}: opaque colours {nc} in 22-32"))
        res.append((black_share(img) <= 0.05, f"{p}: pure-black share {black_share(img):.1%} <= 5%"))
        dl = []
        for w in NPC_WALKS:
            seq = w + [w[0]]
            dl += [frame_delta(cells[seq[k]], cells[seq[k + 1]]) for k in range(4)]
        res.append((min(dl) >= 0.08, f"{p}: walk frame delta min {min(dl):.1%} >= 8%"))
        first = {"down": cells[0], "up": cells[1], "side": cells[2]}
        pd = [sil_diff(first["down"], first["up"]), sil_diff(first["down"], first["side"]), sil_diff(first["up"], first["side"])]
        res.append((min(pd) >= 0.05, f"{p}: idle down/up/side silhouettes differ (min {min(pd):.1%} >= 5%)"))
    d = frame_delta(sheets[0], sheets[1])
    res.append((d >= 0.35, f"NPC sheets differ on {d:.1%} of pixels >= 35%"))
    for p in NPC_PORTRAITS:
        img = load(p)
        res.append((img.size == (400, 148), f"{p}: size {img.size} == (400, 148)"))
        cells = cells_of(img, 4, 100, 148, 4)
        res.append((all(c.getbbox() for c in cells), f"{p}: 4 frames non-empty"))
        blink = frame_delta(cells[0], cells[1])
        talk = frame_delta(cells[0], cells[2])
        res.append((0.002 < blink < 0.2 and 0.002 < talk < 0.2, f"{p}: blink frame differs {blink:.1%}, talk frame differs {talk:.1%} (subtle, non-zero)"))
    pdiff = frame_delta(load(NPC_PORTRAITS[0]), load(NPC_PORTRAITS[1]))
    res.append((pdiff >= 0.35, f"NPC portraits differ on {pdiff:.1%} of pixels >= 35%"))
    for p in NPC_SHEETS + NPC_PORTRAITS:
        g = p.replace("npc/sprites/", "gui/dialog_system/sprites/")
        res.append((sha(p) == sha(g), f"{g} byte-identical to {p}"))
    return res


def check_frozen():
    return [(sha(p) == h, f"frozen {p} sha256 {'OK' if sha(p) == h else 'CHANGED'}") for p, h in FROZEN.items()]


def check_contract_shas():
    """Files this pass must not touch, pinned at the start of the pass."""
    path = rp("tools/art_qa/contract_shasums.txt")
    res = []
    for line in open(path):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        h, p = line.split(None, 1)
        res.append((sha(p) == h, f"unchanged {p}"))
    return res


def check_props():
    img = load("props/Sprites/Props.png")
    res = [(img.size == (1024, 192), f"Props.png size {img.size} == (1024, 192) (16x3 of 64)")]
    bush = hashlib.sha256(img.crop((0, 0, 64, 64)).tobytes()).hexdigest()
    want = open(rp("tools/art_qa/props_bush_cell.sha256")).read().split()[0]
    res.append((bush == want, "Props.png bush cell (0,0) unchanged"))
    used = sum(1 for i in range(48) if img.crop(((i % 16) * 64, (i // 16) * 64, (i % 16) * 64 + 64, (i // 16) * 64 + 64)).getbbox())
    res.append((used >= 13, f"Props.png cells used: {used} (bush + biome props)"))
    return res


# ---------------------------------------------------------------- previews ---
GRASS = (76, 150, 64, 255)


def render_previews(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    targets = {k: v[0] for k, v in ENEMIES.items()}
    targets.update({"npc_daniel": NPC_SHEETS[0], "npc_stefano": NPC_SHEETS[1],
                    "portrait_daniel": NPC_PORTRAITS[0], "portrait_stefano": NPC_PORTRAITS[1],
                    "props": "props/Sprites/Props.png"})
    written = []
    for name, p in targets.items():
        img = load(p)
        g = Image.new("RGBA", img.size, GRASS)
        g.alpha_composite(img)
        g.save(os.path.join(out_dir, f"{name}_grass_1x.png"))
        a = img.getchannel("A").point(lambda v: 255 if v else 0)
        s = Image.new("RGBA", img.size, (235, 235, 235, 255))
        s.paste((0, 0, 0, 255), (0, 0), a)
        s.save(os.path.join(out_dir, f"{name}_silhouette_1x.png"))
        written += [f"{name}_grass_1x.png", f"{name}_silhouette_1x.png"]
    return written
