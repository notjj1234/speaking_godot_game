"""verify_assets.py — static verification for the enemy identity rework.

Run with the project venv python (Pillow): /tmp/loqui_venv/bin/python verify_assets.py

Checks:
  A. Sheets: 512x192, 8x3 grid of 64x64 RGBA cells, transparent corners, <=24
     opaque colors, all 24 cells non-empty, feet within 2px of Goblin baseline.
  B. Differentiation: mean pixel difference vs Goblin (flag <25%), palette
     overlap with Goblin (flag >60%).
  C. Scenes: unique texture path / root name / hp / move speed / chase script /
     chase speed / attack damage / body radius / vision polygon / drop table /
     audio pair / flash tint across the three scenes; every ext_resource path
     exists on disk; animation names are from the fixed 16-name set; the
     vision_area / attack_area / next_state NodePaths resolve; load_steps is
     consistent; no 'Goblin' node names remain; structural contract intact
     (collision_layer=256/mask=16, Sprite2D at (0,-14) with 8x3 frames,
     autoplay idle_down, Idle first in the state machine, SFX bus).
  D. Untouched: goblin / slime / beetle scenes, PNGs, and enemy.gd match the
     recorded baseline shasums (enemy.gd is expected to have changed: the
     baseline check for it lives in the final report instead).
"""
import collections
import hashlib
import os
import re
import sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TARGETS = ["bandit", "skeleton", "orc"]
ALLOWED_ANIMS = {"RESET", "idle_down", "idle_side", "idle_up",
                 "walk_down", "walk_side", "walk_up",
                 "chase_down", "chase_side", "chase_up",
                 "stun_down", "stun_side", "stun_up",
                 "destroy_down", "destroy_side", "destroy_up"}

failures = []
passes = []


def check(ok, label):
    (passes if ok else failures).append(label)
    print(f"{'PASS' if ok else 'FAIL'}  {label}")


def cell_bbox(img):
    px = img.load()
    minx, miny, maxx, maxy = 99, 99, -1, -1
    for y in range(img.height):
        for x in range(img.width):
            if px[x, y][3]:
                minx, miny, maxx, maxy = min(minx, x), min(miny, y), max(maxx, x), max(maxy, y)
    return (minx, miny, maxx, maxy) if maxx >= 0 else None


def sheet_cells(sheet):
    return [sheet.crop(((i % 8) * 64, (i // 8) * 64, (i % 8) * 64 + 64, (i // 8) * 64 + 64))
            for i in range(24)]


def goblin_baselines():
    g = Image.open(os.path.join(ROOT, "enemies/goblin/goblin.png")).convert("RGBA")
    out = {}
    for name, idxs in [("down", [0, 1, 2, 3]), ("up", [4, 5, 6, 7]), ("side", [8, 9, 10, 11])]:
        bottoms = [cell_bbox(c)[3] for c in [sheet_cells(g)[i] for i in idxs]]
        out[name] = max(set(bottoms), key=bottoms.count)
    return out


def load_sheet(name):
    return Image.open(os.path.join(ROOT, f"enemies/{name}/{name}.png")).convert("RGBA")


def check_sheet(name, baselines):
    sheet = load_sheet(name)
    check(sheet.size == (512, 192), f"{name}: sheet is 512x192")
    check(sheet.mode == "RGBA", f"{name}: sheet is RGBA")
    corners = [sheet.getpixel(p)[3] for p in [(0, 0), (511, 0), (0, 191), (511, 191)]]
    check(all(a == 0 for a in corners), f"{name}: corners transparent")
    colors = collections.Counter(c for c in sheet.getdata() if c[3] > 0)
    check(len(colors) <= 24, f"{name}: {len(colors)} opaque colors (<=24)")
    cells = sheet_cells(sheet)
    empties = [i for i, c in enumerate(cells) if cell_bbox(c) is None]
    check(not empties, f"{name}: all 24 cells non-empty {'' if not empties else empties}")
    for d, idxs in [("down", [0, 1, 2, 3]), ("up", [4, 5, 6, 7]), ("side", [8, 9, 10, 11])]:
        bottoms = [cell_bbox(cells[i])[3] for i in idxs]
        ok = all(abs(b - baselines[d]) <= 2 for b in bottoms)
        check(ok, f"{name}: {d} feet baseline {bottoms} vs goblin {baselines[d]} (+-2)")
    return sheet, colors


def check_differentiation(name, sheet, colors, goblin_sheet, goblin_colors):
    a, b = sheet.load(), goblin_sheet.load()
    diff = 0
    union = 0
    for y in range(192):
        for x in range(512):
            pa, pb = a[x, y], b[x, y]
            if pa != pb:
                diff += 1
            if pa[3] or pb[3]:
                union += 1
    raw_pct = 100.0 * diff / (512 * 192)
    union_pct = 100.0 * diff / max(1, union)
    inter = len(set(colors) & set(goblin_colors))
    overlap = 100.0 * inter / max(1, len(colors))
    # Transparent background dominates the sheet, so the raw whole-sheet number
    # is reported for transparency but the painted-area number is the gate.
    check(union_pct >= 25.0,
          f"{name}: painted-area pixel difference vs goblin {union_pct:.1f}% (>=25%) "
          f"[whole-sheet {raw_pct:.1f}%]")
    check(overlap <= 60.0, f"{name}: palette overlap with goblin {overlap:.0f}% (<=60%)")
    return raw_pct, union_pct, overlap


def parse_scene(name):
    path = os.path.join(ROOT, f"enemies/{name}/{name}.tscn")
    with open(path) as f:
        text = f.read()
    return text


def check_scene(name, text, others):
    cap = name.capitalize()
    check(f'[node name="{cap}" type="CharacterBody2D"]' in text, f"{name}: root named {cap}")
    check("collision_layer = 256" in text and "collision_mask = 16" in text,
          f"{name}: collision layer 256 / mask 16")
    check('position = Vector2(0, -14)' in text and "hframes = 8" in text and "vframes = 3" in text,
          f"{name}: Sprite2D at (0,-14) with 8x3 frames")
    check('autoplay = "idle_down"' in text, f"{name}: AnimationPlayer autoplay idle_down")
    check(re.search(r'\[node name="EnemyStateMachine".*?\n\[node name="Idle"', text, re.DOTALL),
          f"{name}: Idle is the first state machine child")
    check('bus = "SFX"' in text, f"{name}: audio on SFX bus")
    check("Goblin" not in text, f"{name}: no Goblin node names")

    tex = re.search(r'\[ext_resource type="Texture2D" uid="[^"]+" path="(res://enemies/[^"]+)"', text)
    check(tex and tex.group(1) == f"res://enemies/{name}/{name}.png", f"{name}: texture path")
    check(all(f"res://enemies/{o}/{o}.png" not in text for o in others), f"{name}: texture unique")

    hp = re.search(rf'\[node name="{cap}".*?hp = (\d+)', text, re.DOTALL)
    mv = re.search(rf'\[node name="{cap}".*?move_speed = ([\d.]+)', text, re.DOTALL)
    check(hp and mv, f"{name}: hp={hp.group(1) if hp else '?'} move_speed={mv.group(1) if mv else '?'}")
    check("chaos_pauses_enabled = false" in text and "slide_bounce_enabled = false" in text,
          f"{name}: chaos pause + slide bounce disabled")

    chase = re.search(r'\[node name="Chase".*?script = ExtResource\("([^"]+)"\).*?chase_speed = ([\d.]+)', text, re.DOTALL)
    check(chase and f"enemy_state_chase_{name}.gd" in text, f"{name}: chase script wired")
    check(chase and chase.group(2), f"{name}: chase_speed={chase.group(2) if chase else '?'}")

    dmg = re.search(r'\[node name="AttackHurtBox".*?damage = (\d+)', text, re.DOTALL)
    check(dmg, f"{name}: attack damage={dmg.group(1) if dmg else '?'}")

    radius = re.search(r'\[sub_resource type="CircleShape2D" id="CircleShape2D_uvnwc"\]\nradius = ([\d.]+)', text)
    check(radius, f"{name}: body collision radius={radius.group(1) if radius else '?'}")

    poly = re.search(r'polygon = PackedVector2Array\(([^)]+)\)', text)
    check(poly, f"{name}: vision polygon {poly.group(1) if poly else '?'}")

    drops = re.findall(r'\[sub_resource type="Resource" id="[^"]+"\]\nscript = ExtResource\("13_ys2o2"\)\nitem = ExtResource\("([^"]+)"\)\nprobability = ([\d.]+)\nmin_amount = (\d+)\nmax_amount = (\d+)', text)
    check(drops, f"{name}: drop table {[(d[0], d[1], d[2], d[3]) for d in drops]}")

    audio = re.findall(r'\[ext_resource type="AudioStream" path="(res://enemies/[^"]+)" id="(6_q0lai|7_0n355)"\]', text)
    check(sorted(p for p, _ in audio) == sorted([f"res://enemies/{name}/{name}_hit.wav",
                                                 f"res://enemies/{name}/{name}_die.wav"]),
          f"{name}: unique hit/die audio")
    tint = re.search(r'\[node name="DestroyEffectSprite".*?modulate = (Color\([^)]+\))', text, re.DOTALL)
    check(tint, f"{name}: destroy effect tint {tint.group(1) if tint else '?'}")
    flash = re.search(r'resource_name = "stun_down".*?Color\(([^)]+)\)', text, re.DOTALL)
    check(flash, f"{name}: hit flash tint Color({flash.group(1)})")

    # ext resources exist on disk
    missing = []
    for p in re.findall(r'\[ext_resource[^\]]*path="(res://[^"]+)"', text):
        if not os.path.exists(os.path.join(ROOT, p.replace("res://", ""))):
            missing.append(p)
    check(not missing, f"{name}: all ext_resource paths exist {'' if not missing else missing}")

    # animation names from the fixed set (main library only — the
    # DestroyEffectSprite has its own legitimate "destroy" smoke animation)
    lib = re.search(r'\[sub_resource type="AnimationLibrary" id="AnimationLibrary_gon52"\]\n_data = \{\n(.*?)\n\}', text, re.DOTALL)
    anims = set(re.findall(r'&"([^"]+)": SubResource\("Animation_', lib.group(1))) if lib else set()
    bad = anims - ALLOWED_ANIMS
    check(not bad, f"{name}: animation names from fixed set {'' if not bad else bad}")

    # node paths resolve
    for np_ in re.findall(r'(?:vision_area|attack_area|next_state) = NodePath\("([^"]+)"\)', text):
        node = np_.split("/")[-1]
        check(f'[node name="{node}"' in text or f'name="{node}"' in text,
              f"{name}: NodePath {np_} resolves")

    ls = re.search(r'load_steps=(\d+)', text)
    n_ext = len(re.findall(r'^\[ext_resource', text, re.M))
    n_sub = len(re.findall(r'^\[sub_resource', text, re.M))
    check(ls and int(ls.group(1)) == n_ext + n_sub + 1,
          f"{name}: load_steps={ls.group(1) if ls else '?'} == ext({n_ext})+sub({n_sub})+1")

    return dict(hp=hp.group(1) if hp else None,
                mv=mv.group(1) if mv else None,
                tex=tex.group(1) if tex else None,
                chase_script=f"enemy_state_chase_{name}.gd",
                chase_speed=chase.group(2) if chase else None,
                dmg=dmg.group(1) if dmg else None,
                radius=radius.group(1) if radius else None,
                poly=poly.group(1) if poly else None,
                drops=tuple(drops), audio=tuple(sorted(p for p, _ in audio)),
                tint=tint.group(1) if tint else None,
                flash=f"Color({flash.group(1)})" if flash else None)


def check_untouched():
    base = os.path.join(HERE, "baseline_shasums.txt")
    want = {}
    with open(base) as f:
        for line in f:
            h, p = line.split()
            want[p] = h
    for p, h in want.items():
        if p == "enemies/scripts/enemy.gd":
            continue  # intentionally extended (additively); reported separately
        with open(os.path.join(ROOT, p), "rb") as f:
            now = hashlib.sha256(f.read()).hexdigest()
        check(now == h, f"untouched: {p}")


def main():
    baselines = goblin_baselines()
    goblin_sheet = load_sheet("goblin")
    goblin_colors = collections.Counter(c for c in goblin_sheet.getdata() if c[3] > 0)
    stats = {}
    for name in TARGETS:
        sheet, colors = check_sheet(name, baselines)
        stats[name] = check_differentiation(name, sheet, colors, goblin_sheet, goblin_colors)
    scenes = {}
    for i, name in enumerate(TARGETS):
        text = parse_scene(name)
        others = TARGETS[:i] + TARGETS[i + 1:]
        scenes[name] = check_scene(name, text, others)
    keys = ["mv", "tex", "chase_script", "chase_speed", "dmg", "radius", "poly",
            "drops", "audio", "tint", "flash"]
    for k in keys:
        vals = {scenes[n][k] for n in TARGETS}
        check(len(vals) == 3, f"unique across targets: {k} {sorted(map(str, vals))}")
    # Full combat profile must be unique per enemy even when one scalar repeats
    # (the brief's own stat shape sets Bandit and Skeleton both at 2 HP).
    profiles = {(scenes[n]["hp"], scenes[n]["mv"], scenes[n]["chase_speed"],
                 scenes[n]["dmg"], scenes[n]["radius"]) for n in TARGETS}
    check(len(profiles) == 3, f"unique across targets: full stat profile {sorted(profiles)}")
    check_untouched()
    print(f"\n{len(passes)} PASS / {len(failures)} FAIL")
    if failures:
        print("FAILURES:")
        for f_ in failures:
            print(" -", f_)
        sys.exit(1)
    print("ALL CHECKS PASSED")


if __name__ == "__main__":
    main()
