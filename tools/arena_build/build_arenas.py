"""build_arenas.py — ASCII arena maps -> levels/endless_horde/arenas/arena_0N.tscn

    python3.13 tools/arena_build/build_arenas.py           # validate, then write the 4 scenes
    python3.13 tools/arena_build/build_arenas.py --check   # validate + confirm committed scenes are current

Sources: tools/arena_build/maps/arena_0N.txt (20x15 grid + legend). Built-in
characters: '#' wall (cliff ring, auto-picked by position), '.' grass,
':' dirt (blob-autotiled with the tileset's own 47-tile "Path" terrain).
Every other character is a prop from build_props.PROPS via the map's legend.

TileMapLayer data format (verified against all maps in this repo):
    out = bytearray(b"\\x00\\x00")
    for x, y, ax, ay in cells: out += struct.pack("<HHHHHH", x, y, 0, ax, ay, 0)
    tile_map_data = PackedByteArray("<base64>")

The generator REFUSES to write any map that misses the design bar:
  * 20x15 grid, sealed perimeter (no open cell on the border),
  * open ratio 68-82 %, 100 % of open cells reachable from the centre,
  * no corridor narrower than 2 tiles (every open cell sits in an open 2x2),
  * obstacles free-standing (not touching the perimeter, <= 2x2, never a maze),
  * >= 3 tiles of clear ground around SpawnPoint and no blocker within 96 px (+ half a tile),
  * top 56 px (WaveLabel band) quiet: rows 0-1 hold no props/dirt, no prop art reaches above y=56,
  * the practice start pad cells (10..11, 10..11) are free of props.
"""
from __future__ import annotations

import base64
import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from build_props import PROPS  # noqa: E402

W, H, TILE = 20, 15, 32
MAPS = [os.path.join(HERE, "maps", f"arena_0{i}.txt") for i in range(1, 5)]
SCENES = [os.path.join(ROOT, "levels", "endless_horde", "arenas", f"arena_0{i}.tscn") for i in range(1, 5)]
STATS = os.path.join(HERE, "arenas.json")
CENTRE = (10, 7)
PAD_CELLS = {(10, 10), (11, 10), (10, 11), (11, 11)}
SPAWN_RING = 96.0
WAVE_BAND = 56

# ---- tileset facts (read from tile_maps/grass-01.tscn) -----------------------
TSCN = open(os.path.join(ROOT, "tile_maps", "grass-01.tscn")).read()
PHYS = {(int(a), int(b)) for a, b in re.findall(r"^(\d+):(\d+)/0/physics_layer_0/polygon_0/points", TSCN, re.M)}
DEFINED = {(int(a), int(b)) for a, b in re.findall(r"^(\d+):(\d+)/0 = 0$", TSCN, re.M)}
_AB = {"top_side": "N", "right_side": "E", "bottom_side": "S", "left_side": "W",
       "top_left_corner": "NW", "top_right_corner": "NE", "bottom_left_corner": "SW", "bottom_right_corner": "SE"}
_bits = {}
for a, b, bit in re.findall(r"^(\d+):(\d+)/0/terrains_peering_bit/(\w+) = 0$", TSCN, re.M):
    _bits.setdefault((int(a), int(b)), set()).add(_AB[bit])
TERRAIN = {(int(a), int(b)) for a, b in re.findall(r"^(\d+):(\d+)/0/terrain = 0$", TSCN, re.M)}
BLOB = {frozenset(_bits.get(t, ())): t for t in TERRAIN}
assert len(BLOB) == 47, "expected the 47-tile Path terrain"
APPROX = []   # (x, y, wanted bits, used bits) where the tileset has no exact piece


def blob_tile(bits, where=None):
    """Exact peering match, else the closest piece (sides weigh 4, corners 1).
    The tileset's 47 pieces are not the textbook blob set (e.g. no inner
    corner with three corners filled), so a few concave spots approximate."""
    key = frozenset(bits)
    if key in BLOB:
        return BLOB[key]
    sides = {"N", "E", "S", "W"}
    best = min(BLOB.items(), key=lambda kv: (4 * len((kv[0] ^ key) & sides) + len((kv[0] ^ key) - sides), sorted(kv[1])))
    APPROX.append((where, sorted(key), sorted(best[0])))
    return best[1]

PLAIN = [(0, 0), (1, 0), (2, 0), (3, 0), (0, 1), (3, 1), (0, 2), (1, 2), (2, 2), (3, 2), (0, 3), (1, 3), (2, 3), (3, 3)]
SPECIAL = {0: [(1, 1)], 1: [(2, 1)], 2: [(2, 1)], 3: []}     # flowers / pebbles per biome


def wall_tile(x, y):
    """Cliff ring (atlas 10-14 x 4-7): one-tile top edge, two-tile bottom face."""
    mid = 11 + (x % 3)
    if y == 0:
        return (10, 4) if x == 0 else (14, 4) if x == W - 1 else (mid, 4)
    if y == H - 2:
        return (10, 6) if x == 0 else (14, 6) if x == W - 1 else (mid, 6)
    if y == H - 1:
        return (10, 7) if x == 0 else (14, 7) if x == W - 1 else (mid, 7)
    return (10, 5) if x == 0 else (14, 5)


def is_perimeter(x, y):
    return x in (0, W - 1) or y in (0, H - 2, H - 1)


# ---- parsing --------------------------------------------------------------------
def parse(path):
    m = {"path": path, "legend": {}, "grid": []}
    mode = None
    for raw in open(path, encoding="utf-8"):
        line = raw.rstrip("\n")
        if line.startswith("#") and mode != "map":
            continue
        if mode == "map":
            if line.strip():
                m["grid"].append(line)
            continue
        if line.strip() == "legend:":
            mode = "legend"
            continue
        if line.strip() == "map:":
            mode = "map"
            continue
        if mode == "legend" and "=" in line:
            ch, rest = line.split("=", 1)
            parts = rest.split()
            m["legend"][ch.strip()] = (parts[0], "on_dirt" in parts[1:])
            continue
        if ":" in line:
            k, v = line.split(":", 1)
            m[k.strip()] = v.strip()
    m["tint"] = tuple(float(v) for v in m["tint"].split())
    m["spawn"] = tuple(float(v) for v in m["spawn"].split())
    return m


# ---- layout -----------------------------------------------------------------------
def layout(m, index):
    errors = []
    g = m["grid"]
    if len(g) != H or any(len(r) != W for r in g):
        errors.append(f"grid must be {W}x{H}, got {len(g)} rows / widths {sorted({len(r) for r in g})}")
        return None, errors
    ch = lambda x, y: g[y][x]
    for (x, y) in ((x, y) for y in range(H) for x in range(W)):
        c = ch(x, y)
        if c not in "#.:" and c not in m["legend"]:
            errors.append(f"unknown character {c!r} at {x},{y}")
        if is_perimeter(x, y) and c != "#":
            errors.append(f"perimeter not sealed: open cell {x},{y}")
        if not is_perimeter(x, y) and c == "#":
            errors.append(f"stray wall at {x},{y} (walls are perimeter only; use props for cover)")
    if errors:
        return None, errors

    def is_dirt(x, y):
        if not (0 <= x < W and 0 <= y < H):
            return False
        c = ch(x, y)
        return c == ":" or (c in m["legend"] and m["legend"][c][1])

    props, cells = [], []
    seen = set()
    for y in range(H):
        for x in range(W):
            c = ch(x, y)
            if c in m["legend"] and (x, y) not in seen:
                name = m["legend"][c][0]
                if name not in PROPS:
                    errors.append(f"legend {c!r} -> unknown prop {name!r}")
                    continue
                frame, solid, w, flat = PROPS[name]
                span = [(x + k, y) for k in range(w)]
                if any(not (0 <= sx < W) or ch(sx, sy) != c for sx, sy in span):
                    errors.append(f"{name} at {x},{y} needs {w} cells of {c!r}")
                    continue
                seen.update(span)
                props.append({"name": name, "x": x, "y": y, "w": w, "frame": frame, "solid": solid, "flat": flat})
    for y in range(H):
        for x in range(W):
            if is_perimeter(x, y):
                ax, ay = wall_tile(x, y)
            elif is_dirt(x, y):
                n = lambda dx, dy: is_dirt(x + dx, y + dy)
                bits = {d for d, (dx, dy) in {"N": (0, -1), "E": (1, 0), "S": (0, 1), "W": (-1, 0)}.items() if n(dx, dy)}
                for d, (dx, dy), a, b in (("NE", (1, -1), "N", "E"), ("NW", (-1, -1), "N", "W"),
                                          ("SE", (1, 1), "S", "E"), ("SW", (-1, 1), "S", "W")):
                    if a in bits and b in bits and n(dx, dy):
                        bits.add(d)
                ax, ay = blob_tile(bits, (x, y))
            else:
                h = (x * 73856093 ^ y * 19349663 ^ (index + 1) * 83492791) & 0xFFFF
                pool = SPECIAL[index] if (SPECIAL[index] and h % 13 == 0) else PLAIN
                ax, ay = pool[(h >> 4) % len(pool)]
            assert (ax, ay) in DEFINED
            cells.append((x, y, ax, ay))
    tile_at = {(x, y): (ax, ay) for x, y, ax, ay in cells}
    blocked = {p for p, t in tile_at.items() if t in PHYS}
    for p in props:
        if p["solid"]:
            blocked.update((p["x"] + k, p["y"]) for k in range(p["w"]))
    return {"cells": cells, "props": props, "blocked": blocked, "tile_at": tile_at, "is_dirt": is_dirt}, errors


# ---- design bar ----------------------------------------------------------------------
def prop_art_tops():
    """Topmost opaque row of each prop's art inside its 64 px cell (for the WaveLabel band)."""
    from PIL import Image
    img = Image.open(os.path.join(ROOT, "props", "Sprites", "Props.png")).convert("RGBA")
    tops = {}
    for name, (frame, *_r) in PROPS.items():
        bb = img.crop(((frame % 16) * 64, (frame // 16) * 64, (frame % 16) * 64 + 64, (frame // 16) * 64 + 64)).getbbox()
        tops[name] = bb[1] if bb else 64
    return tops


def validate(m, lay):
    errs = []
    blocked = lay["blocked"]
    total = W * H
    open_cells = {(x, y) for y in range(H) for x in range(W)} - blocked
    ratio = len(open_cells) / total
    if not 0.68 <= ratio <= 0.82:
        errs.append(f"open ratio {ratio:.1%} outside 68-82%")
    if any(is_perimeter(x, y) for x, y in open_cells):
        errs.append("open cell on the border")
    if CENTRE in blocked:
        errs.append("centre cell blocked")
    seen, stack = {CENTRE}, [CENTRE]
    while stack:
        x, y = stack.pop()
        for q in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if q in open_cells and q not in seen:
                seen.add(q)
                stack.append(q)
    reach = len(seen) / max(1, len(open_cells))
    if reach < 1.0:
        errs.append(f"only {reach:.1%} of open cells reachable; sealed: {sorted(open_cells - seen)[:8]}")
    narrow = []
    for (x, y) in open_cells:
        if not any(all((x + dx + i, y + dy + j) in open_cells for i in (0, 1) for j in (0, 1))
                   for dx in (-1, 0) for dy in (-1, 0)):
            narrow.append((x, y))
    if narrow:
        errs.append(f"corridor narrower than 2 tiles at {sorted(narrow)[:8]}")
    # obstacles: free-standing components
    inner = {p for p in blocked if not is_perimeter(*p)}
    comps, todo = [], set(inner)
    while todo:
        s = todo.pop()
        comp, st = {s}, [s]
        while st:
            x, y = st.pop()
            for q in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if q in todo:
                    todo.discard(q)
                    comp.add(q)
                    st.append(q)
        comps.append(comp)
    for c in comps:
        xs = [p[0] for p in c]
        ys = [p[1] for p in c]
        if max(xs) - min(xs) > 1 or max(ys) - min(ys) > 1:
            errs.append(f"obstacle larger than 2x2 (maze risk) at {sorted(c)}")
        if any(is_perimeter(x + dx, y + dy) for x, y in c for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
            errs.append(f"obstacle touches the perimeter at {sorted(c)}")
    # spawn safety
    sx, sy = m["spawn"]
    near = [(x, y) for y in range(H) for x in range(W)
            if ((x * TILE + 16 - sx) ** 2 + (y * TILE + 16 - sy) ** 2) ** 0.5 <= SPAWN_RING + TILE / 2]
    bad = [p for p in near if p in blocked]
    if bad:
        errs.append(f"blocker inside the {SPAWN_RING:.0f}px spawn ring: {bad}")
    scx, scy = int(sx // TILE), int(sy // TILE)
    sq = [(x, y) for x in range(scx - 3, scx + 4) for y in range(scy - 3, scy + 4) if (x, y) in blocked]
    if sq:
        errs.append(f"less than 3 tiles of clear ground around SpawnPoint: {sq}")
    # quiet WaveLabel band
    tops = prop_art_tops()
    for p in lay["props"]:
        if p["y"] <= 1:
            errs.append(f"{p['name']} at {p['x']},{p['y']} sits in the WaveLabel band")
        if not p["flat"]:
            art_top = p["y"] * TILE + 16 - 16 - 32 + tops[p["name"]]
            if art_top < WAVE_BAND:
                errs.append(f"{p['name']} at {p['x']},{p['y']} reaches y={art_top} (< {WAVE_BAND})")
    if any(lay["is_dirt"](x, y) for x in range(W) for y in (0, 1)):
        errs.append("dirt inside the WaveLabel band (rows 0-1)")
    for p in lay["props"]:
        if any((p["x"] + k, p["y"]) in PAD_CELLS for k in range(p["w"])):
            errs.append(f"{p['name']} covers the practice start pad")
    stats = {"name": m["name"], "motif": m.get("motif", ""), "open_ratio": round(ratio, 4), "reachable": round(reach, 4),
             "open_cells": len(open_cells), "blocked_cells": len(blocked), "obstacle_cells": len(inner),
             "obstacles": len(comps), "props": len(lay["props"]), "solid_props": sum(1 for p in lay["props"] if p["solid"]),
             "tint": m["tint"], "spawn": m["spawn"]}
    return errs, stats


# ---- scene text ------------------------------------------------------------------------
def tile_data(cells):
    out = bytearray(b"\x00\x00")
    for x, y, ax, ay in cells:
        out += struct.pack("<HHHHHH", x, y, 0, ax, ay, 0)
    return base64.b64encode(bytes(out)).decode()


def fmt(v):
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return s if s not in ("-0", "") else "0"


def scene_text(m, lay, index):
    solids = [p for p in lay["props"] if p["solid"]]
    lines = [f"[gd_scene load_steps=6 format=3]", "",
             '[ext_resource type="Script" path="res://levels/endless_horde/arena.gd" id="1_arena"]',
             '[ext_resource type="PackedScene" uid="uid://diwmvkgtca114" path="res://tile_maps/grass-01.tscn" id="2_ground"]',
             '[ext_resource type="Texture2D" uid="uid://bpa5gsclvkekd" path="res://props/Sprites/Props.png" id="3_props"]', "",
             '[sub_resource type="RectangleShape2D" id="RectangleShape2D_w1"]', "size = Vector2(28, 24)", "",
             '[sub_resource type="RectangleShape2D" id="RectangleShape2D_w2"]', "size = Vector2(60, 24)", "",
             '[node name="Arena" type="Node2D"]', 'script = ExtResource("1_arena")',
             f'display_name = "{m["name"]}"',
             f"ground_tint = Color({', '.join(fmt(v) for v in m['tint'])}, 1)",
             f'metadata/generated_from = "tools/arena_build/maps/arena_0{index + 1}.txt (build_arenas.py) - edit the map, not this file"', "",
             '[node name="Ground" parent="." instance=ExtResource("2_ground")]',
             f"modulate = Color({', '.join(fmt(v) for v in m['tint'])}, 1)",
             f'tile_map_data = PackedByteArray("{tile_data(lay["cells"])}")', "",
             '[node name="Blockers" type="StaticBody2D" parent="."]', "collision_layer = 16", "collision_mask = 0", ""]
    for i, p in enumerate(solids):
        cx = p["x"] * TILE + p["w"] * TILE / 2
        cy = p["y"] * TILE + 16 + 2
        lines += [f'[node name="{p["name"]}_{p["x"]:02d}_{p["y"]:02d}" type="CollisionShape2D" parent="Blockers"]',
                  f"position = Vector2({fmt(cx)}, {fmt(cy)})",
                  f'shape = SubResource("RectangleShape2D_w{p["w"]}")', ""]
    sx, sy = m["spawn"]
    lines += ['[node name="SpawnPoint" type="Marker2D" parent="."]', f"position = Vector2({fmt(sx)}, {fmt(sy)})", "",
              '[node name="Decor" type="Node2D" parent="."]', ""]
    for p in lay["props"]:
        cx = p["x"] * TILE + p["w"] * TILE / 2
        if p["flat"]:
            pos, off = (cx, p["y"] * TILE), (0, 0)
        else:
            pos, off = (cx, p["y"] * TILE + 16), (0, -16)
        lines += [f'[node name="{p["name"]}_{p["x"]:02d}_{p["y"]:02d}" type="Sprite2D" parent="Decor"]',
                  f"position = Vector2({fmt(pos[0])}, {fmt(pos[1])})",
                  'texture = ExtResource("3_props")']
        if off != (0, 0):
            lines.append(f"offset = Vector2({fmt(off[0])}, {fmt(off[1])})")
        lines += ["hframes = 16", "vframes = 3", f"frame = {p['frame']}", ""]
    return "\n".join(lines)


# ---- horde_curve cross-check ------------------------------------------------------------
def arena_index_for(stage):
    return int((max(stage, 1) - 1) / 20) % 4


def check_curve(names):
    errs = []
    src = open(os.path.join(ROOT, "levels", "endless_horde", "horde_curve.gd")).read()
    if "static func arena_index_for(stage: int) -> int:" not in src or "static func arena_name_for(index: int) -> String:" not in src:
        errs.append("horde_curve.gd lacks arena_index_for / arena_name_for")
    mm = re.search(r"const ARENA_NAMES := \[([^\]]*)\]", src)
    got = re.findall(r'"([^"]+)"', mm.group(1)) if mm else []
    if got != names:
        errs.append(f"HordeCurve.ARENA_NAMES {got} != map names {names}")
    table = {0: 0, 1: 0, 20: 0, 21: 1, 40: 1, 41: 2, 47: 2, 60: 2, 61: 3, 80: 3, 81: 0, 100: 0, 101: 1, 161: 0}
    for st, want in table.items():
        if arena_index_for(st) != want:
            errs.append(f"arena_index_for({st}) = {arena_index_for(st)} != {want}")
    if "int((maxi(stage, 1) - 1) / ARENA_STAGE_SPAN) % ARENA_COUNT" not in src:
        errs.append("horde_curve.gd arena_index_for formula differs from int((max(stage,1)-1)/20) % 4")
    return errs


def main():
    check = "--check" in sys.argv
    all_errs, stats, texts = [], [], []
    for i, path in enumerate(MAPS):
        m = parse(path)
        lay, errs = layout(m, i)
        if lay:
            verrs, st = validate(m, lay)
            errs += verrs
            stats.append(st)
            texts.append(scene_text(m, lay, i))
            print(f"{'✅' if not errs else '❌'} arena_0{i + 1} {m['name']}: open {st['open_ratio']:.1%}, reachable {st['reachable']:.0%}, "
                  f"{st['obstacles']} obstacles / {st['obstacle_cells']} cells, {st['props']} props")
        for e in errs:
            print(f"   ❌ arena_0{i + 1}: {e}")
        all_errs += errs
    names = [s["name"] for s in stats]
    if check:
        for e in check_curve(names):
            print("   ❌ " + e)
            all_errs.append(e)
        for path, text in zip(SCENES, texts):
            cur = open(path).read() if os.path.exists(path) else None
            ok = cur == text + "\n"
            print(f"{'✅' if ok else '❌'} {os.path.relpath(path, ROOT)} {'matches its map' if ok else 'is missing or stale — run build_arenas.py'}")
            if not ok:
                all_errs.append("stale scene")
    if all_errs:
        print(f"\n❌ {len(all_errs)} problem(s); {'nothing written' if not check else 'check failed'}")
        return 1
    if not check:
        for path, text in zip(SCENES, texts):
            with open(path, "w") as f:
                f.write(text + "\n")
            print("✅ wrote", os.path.relpath(path, ROOT))
        with open(STATS, "w") as f:
            json.dump(stats, f, indent=2)
        print("✅ wrote", os.path.relpath(STATS, ROOT))
    else:
        print("\n✅ all arenas pass the design bar")
    return 0


if __name__ == "__main__":
    sys.exit(main())
