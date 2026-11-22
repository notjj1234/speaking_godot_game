"""build_scenes.py — rebuild bandit.tscn / skeleton.tscn / orc.tscn from the
current (Goblin-copy) files via exact, asserted string surgery.

Keeps each scene's own uid, texture ext_resource uid/path, and root node name.
Reused ids: 6_q0lai/7_0n355 now point at per-enemy hit/die WAVs, so the audio
tracks embedded in the stun/destroy animations need no edits. load_steps is
recomputed from the final resource counts.
"""
import re
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from artlib import rp

ENEMIES = {
    "bandit": dict(
        chase_script="res://enemies/scripts/states/enemy_state_chase_bandit.gd",
        hp=2, move_speed=38.0, wander_speed=30.0,
        chase_speed=55.0, contact_damage=1, weapon_damage=2,
        body_radius=10.0, capsule=(5.0, 18.0),
        walk=(0.48, (0.0, 0.12, 0.24, 0.36)),
        chase=(0.36, (0.0, 0.09, 0.18, 0.27)),
        attack=dict(kind="circle", r=9.0,
                    down=((0, 11), (0, 11), (0, 18), (0, 11)),
                    side=((4, 7), (4, 7), (14, 7), (4, 7)),
                    up=((0, -4), (0, -4), (0, -10), (0, -4))),
        flash="Color(1, 0.62, 0.1, 1)",
        tint="Color(1.3, 0.95, 0.7, 1)",
        vision="-16, 0, 16, 0, 138, 110, -138, 110",
        item_swap={"15_j3imk": "res://items/potion.tres"},
        drop_ext_keep=["14_t3vbn", "15_j3imk"],
        drops=[("14_t3vbn", 100.0, 1, 1), ("15_j3imk", 40.0, 1, 1)],
        chase_extra="",
    ),
    "skeleton": dict(
        chase_script="res://enemies/scripts/states/enemy_state_chase_skeleton.gd",
        hp=2, move_speed=18.0, wander_speed=18.0,
        chase_speed=26.0, contact_damage=1, weapon_damage=4,
        body_radius=9.0, capsule=(5.0, 24.0),
        walk=(1.0, (0.0, 0.18, 0.55, 0.8)),
        chase=(0.7, (0.0, 0.2, 0.42, 0.62)),
        attack=dict(kind="capsule", r=3.0, h=22.0,
                    down=((0, 8), (0, 8), (0, 22), (0, 8)),
                    side=((4, 7), (4, 7), (22, 7), (4, 7)),
                    up=((0, -4), (0, -4), (0, -18), (0, -4)),
                    side_rotation=1.5708),
        flash="Color(0.55, 0.75, 1, 1)",
        tint="Color(0.85, 0.95, 1.3, 1)",
        vision="-11, 0, 11, 0, 84, 156, -84, 156",
        item_swap={"15_j3imk": "res://items/stone.tres"},
        drop_ext_keep=["14_t3vbn", "15_j3imk"],
        drops=[("15_j3imk", 100.0, 1, 2), ("14_t3vbn", 60.0, 1, 2)],
        chase_extra="",
    ),
    "orc": dict(
        chase_script="res://enemies/scripts/states/enemy_state_chase_orc.gd",
        hp=5, move_speed=16.0, wander_speed=16.0,
        chase_speed=22.0, contact_damage=2, weapon_damage=5,
        body_radius=15.0, capsule=(8.0, 24.0),
        walk=(1.2, (0.0, 0.3, 0.6, 0.9)),
        chase=(0.9, (0.0, 0.225, 0.45, 0.675)),
        attack=dict(kind="circle", r=13.0,
                    down=((0, 11), (0, 11), (0, 20), (0, 11)),
                    side=((4, 7), (4, 7), (16, 7), (4, 7)),
                    up=((0, -4), (0, -4), (0, -12), (0, -4))),
        flash="Color(0.8, 0.08, 0.12, 1)",
        tint="Color(0.9, 1.05, 0.9, 1)",
        vision="-14, 0, 14, 0, 58, 58, -58, 58",
        item_swap={},
        drop_ext_keep=["14_t3vbn", "15_j3imk", "18_sword"],
        drops=[("15_j3imk", 100.0, 1, 2), ("14_t3vbn", 100.0, 1, 1),
               ("18_sword", 8.0, 1, 1)],
        chase_extra="",
    ),
}


def fnum(x):
    s = f"{x:g}"
    return s if "." in s or "e" in s else s + ".0"


def anim_block(rid, name, length, times, frames, attack_pos, rotation=None):
    t = ", ".join(fnum(v) for v in times)
    fr = ", ".join(str(v) for v in frames)
    pos = ", ".join(f"Vector2({p[0]}, {p[1]})" for p in attack_pos)
    lines = [
        f'[sub_resource type="Animation" id="{rid}"]',
        f'resource_name = "{name}"',
        f'length = {fnum(length)}',
        'loop_mode = 1',
        'step = 0.05',
        'tracks/0/type = "value"',
        'tracks/0/imported = false',
        'tracks/0/enabled = true',
        'tracks/0/path = NodePath("Sprite2D:frame")',
        'tracks/0/interp = 1',
        'tracks/0/loop_wrap = true',
        'tracks/0/keys = {',
        f'"times": PackedFloat32Array({t}),',
        f'"transitions": PackedFloat32Array(1, 1, 1, 1),',
        '"update": 1,',
        f'"values": [{fr}]',
        '}',
        'tracks/1/type = "value"',
        'tracks/1/imported = false',
        'tracks/1/enabled = true',
        'tracks/1/path = NodePath("Sprite2D/AttackHurtBox:position")',
        'tracks/1/interp = 1',
        'tracks/1/loop_wrap = true',
        'tracks/1/keys = {',
        f'"times": PackedFloat32Array({t}),',
        '"transitions": PackedFloat32Array(1, 1, 1, 1),',
        '"update": 0,',
        f'"values": [{pos}]',
        '}',
    ]
    if rotation is not None:
        lines += [
            'tracks/2/type = "value"',
            'tracks/2/imported = false',
            'tracks/2/enabled = true',
            'tracks/2/path = NodePath("Sprite2D/AttackHurtBox/CollisionShape2D:rotation")',
            'tracks/2/interp = 1',
            'tracks/2/loop_wrap = true',
            'tracks/2/keys = {',
            f'"times": PackedFloat32Array({t}),',
            '"transitions": PackedFloat32Array(1, 1, 1, 1),',
            '"update": 1,',
            f'"values": [{rotation}, {rotation}, {rotation}, {rotation}]',
            '}',
        ]
    return "\n".join(lines)


def replace_block(text, rid, new_block):
    pat = re.compile(rf'\[sub_resource type="Animation" id="{rid}"\].*?(?=\n\[sub_resource|\n\[node)', re.DOTALL)
    new_text, n = pat.subn(new_block, text)
    assert n == 1, f"block {rid}: replaced {n}"
    return new_text


def sub(text, old, new, count=1):
    n = text.count(old)
    assert n == count, f"expected {count}x, found {n}: {old[:70]!r}"
    return text.replace(old, new)


def restore_original(name, scene_uid, tex_uid):
    """Reconstruct the pre-rework target scene (a Goblin copy with its own uid,
    texture reference, and root name) so build() is idempotent."""
    with open(rp("enemies/goblin/goblin.tscn")) as f:
        text = f.read()
    text = sub(text, '[gd_scene load_steps=45 format=3 uid="uid://brq0jk6yaiu12"]',
               f'[gd_scene load_steps=45 format=3 uid="{scene_uid}"]')
    text = sub(text, '[ext_resource type="Texture2D" uid="uid://cs38gt1x6hvq3" path="res://enemies/goblin/goblin.png" id="5_hvprn"]',
               f'[ext_resource type="Texture2D" uid="{tex_uid}" path="res://enemies/{name}/{name}.png" id="5_hvprn"]')
    text = sub(text, '[node name="Goblin" type="CharacterBody2D"]',
               f'[node name="{name.capitalize()}" type="CharacterBody2D"]')
    with open(rp(f"enemies/{name}/{name}.tscn"), "w") as f:
        f.write(text)


ORIGINALS = {
    "bandit": ("uid://lczsksyz2747o", "uid://b4xunkwf1vnse"),
    "skeleton": ("uid://yevuomgz0nuj1", "uid://gwud7wjhra2u"),
    "orc": ("uid://9ri8j8dvn0x8m", "uid://5137dp2wmrye"),
}


def build(name, cfg):
    restore_original(name, *ORIGINALS[name])
    path = rp(f"enemies/{name}/{name}.tscn")
    with open(path) as f:
        text = f.read()

    # --- ext resources: chase script + per-enemy audio, item path swaps ---
    text = sub(text,
               '[ext_resource type="Script" uid="uid://dxcjtp83b8j7x" path="res://enemies/scripts/states/enemy_state_chase.gd" id="16_p257j"]',
               '[ext_resource type="Script" uid="uid://dxcjtp83b8j7x" path="res://enemies/scripts/states/enemy_state_chase.gd" id="16_p257j"]\n'
               f'[ext_resource type="Script" path="{cfg["chase_script"]}" id="20_chase"]')
    text = sub(text,
               '[ext_resource type="AudioStream" uid="uid://bxpjarpvyjr83" path="res://enemies/slime/hit_01.wav" id="6_q0lai"]',
               f'[ext_resource type="AudioStream" path="res://enemies/{name}/{name}_hit.wav" id="6_q0lai"]')
    text = sub(text,
               '[ext_resource type="AudioStream" uid="uid://bsmrp2rdjf8le" path="res://enemies/slime/hit_00.wav" id="7_0n355"]',
               f'[ext_resource type="AudioStream" path="res://enemies/{name}/{name}_die.wav" id="7_0n355"]')
    for old_id, new_path in cfg["item_swap"].items():
        text = re.sub(rf'\[ext_resource type="Resource" uid="[^"]+" path="[^"]+" id="{old_id}"\]',
                      f'[ext_resource type="Resource" path="{new_path}" id="{old_id}"]', text, count=1)
    if "18_sword" not in cfg["drop_ext_keep"]:
        text = sub(text, '[ext_resource type="Resource" uid="uid://b8sworditemlq01" path="res://items/sword.tres" id="18_sword"]\n', '')

    # --- shapes ---
    text = sub(text, 'radius = 13.0384', f'radius = {fnum(cfg["body_radius"])}')
    text = sub(text, 'radius = 6.0\nheight = 20.0',
               f'radius = {fnum(cfg["capsule"][0])}\nheight = {fnum(cfg["capsule"][1])}')
    atk = cfg["attack"]
    if atk["kind"] == "circle":
        shape_block = (f'[sub_resource type="CircleShape2D" id="CircleShape2D_attack"]\n'
                       f'radius = {fnum(atk["r"])}')
    else:
        shape_block = (f'[sub_resource type="CapsuleShape2D" id="CapsuleShape2D_attack"]\n'
                       f'radius = {fnum(atk["r"])}\nheight = {fnum(atk["h"])}')
    text = sub(text, '[sub_resource type="Animation" id="Animation_mb1nb"]',
               shape_block + '\n\n[sub_resource type="Animation" id="Animation_mb1nb"]')

    # --- animation timings + attack tracks ---
    wl, wt = cfg["walk"]
    cl, ct = cfg["chase"]
    for rid, rname, frames, key in [("Animation_br225", "walk_down", [0, 1, 2, 3], "down"),
                                    ("Animation_wmll0", "walk_side", [8, 9, 10, 11], "side"),
                                    ("Animation_rqwjx", "walk_up", [4, 5, 6, 7], "up")]:
        text = replace_block(text, rid, anim_block(rid, rname, wl, wt, frames, cfg["attack"][key]))
    for rid, rname, frames, key in [("Animation_hvprn", "chase_down", [12, 13, 14, 15], "down"),
                                    ("Animation_p257j", "chase_side", [20, 21, 22, 23], "side"),
                                    ("Animation_r3i0u", "chase_up", [16, 17, 18, 19], "up")]:
        rot = None
        if "side_rotation" in cfg["attack"]:
            rot = cfg["attack"]["side_rotation"] if key == "side" else 0.0
        text = replace_block(text, rid, anim_block(rid, rname, cl, ct, frames, cfg["attack"][key], rot))

    # --- hit/death flash tint (stun + destroy tracks) ---
    text = text.replace('Color(0.957656, 0, 0.159687, 1)', cfg["flash"])

    # --- drop table ---
    drop_lines = []
    keep = {"Resource_umlv4", "Resource_8lxjo", "Resource_sword"}
    res_ids = ["Resource_umlv4", "Resource_8lxjo", "Resource_sword"]
    for i, (item_ext, prob, mn, mx) in enumerate(cfg["drops"]):
        drop_lines.append(
            f'[sub_resource type="Resource" id="{res_ids[i]}"]\n'
            f'script = ExtResource("13_ys2o2")\n'
            f'item = ExtResource("{item_ext}")\n'
            f'probability = {fnum(prob)}\n'
            f'min_amount = {mn}\n'
            f'max_amount = {mx}')
    used = {res_ids[i] for i in range(len(cfg["drops"]))}
    new_drop_block = "\n\n".join(drop_lines)
    pat = re.compile(r'(\[sub_resource type="Resource" id="Resource_umlv4"\].*?)(?=\n\[sub_resource type="Animation" id="Animation_cjcsw"\])', re.DOTALL)
    text, n = pat.subn(new_drop_block, text)
    assert n == 1, "drop block replace failed"
    drops_arr = ", ".join(f'SubResource("{r}")' for r in sorted(used))
    text = sub(text,
               'drops = Array[ExtResource("13_ys2o2")]([SubResource("Resource_umlv4"), SubResource("Resource_8lxjo"), SubResource("Resource_sword")])',
               f'drops = Array[ExtResource("13_ys2o2")]([{drops_arr}])')

    # --- node properties ---
    root = f'[node name="{name.capitalize()}" type="CharacterBody2D"]'
    text = sub(text, root + '\ncollision_layer = 256\ncollision_mask = 16\nscript = ExtResource("1_f3wku")',
               root + '\ncollision_layer = 256\ncollision_mask = 16\nscript = ExtResource("1_f3wku")\n'
               f'hp = {cfg["hp"]}\n'
               f'move_speed = {fnum(cfg["move_speed"])}\n'
               'chaos_pauses_enabled = false\n'
               'slide_bounce_enabled = false')
    if cfg["contact_damage"] != 1:
        text = sub(text, '[node name="HurtBox" parent="." instance=ExtResource("2_lvhkj")]\nposition = Vector2(0, -6)',
                   '[node name="HurtBox" parent="." instance=ExtResource("2_lvhkj")]\nposition = Vector2(0, -6)\n'
                   f'damage = {cfg["contact_damage"]}')
    text = sub(text, '[node name="AttackHurtBox" parent="Sprite2D" instance=ExtResource("2_lvhkj")]\nposition = Vector2(0, 11)\nmonitoring = false\ndamage = 3',
               '[node name="AttackHurtBox" parent="Sprite2D" instance=ExtResource("2_lvhkj")]\nposition = Vector2(0, 11)\nmonitoring = false\n'
               f'damage = {cfg["weapon_damage"]}')
    shape_id = "CircleShape2D_attack" if atk["kind"] == "circle" else "CapsuleShape2D_attack"
    text = sub(text, '[node name="CollisionShape2D" type="CollisionShape2D" parent="Sprite2D/AttackHurtBox"]\nshape = SubResource("CircleShape2D_uvnwc")',
               f'[node name="CollisionShape2D" type="CollisionShape2D" parent="Sprite2D/AttackHurtBox"]\nshape = SubResource("{shape_id}")')
    text = sub(text, 'wander_speed = 30.0', f'wander_speed = {fnum(cfg["wander_speed"])}')
    text = sub(text, 'script = ExtResource("16_p257j")', 'script = ExtResource("20_chase")')
    text = sub(text, 'next_state = NodePath("../Idle")\n',
               f'next_state = NodePath("../Idle")\nchase_speed = {fnum(cfg["chase_speed"])}\n')
    text = sub(text, 'polygon = PackedVector2Array(-16, 0, 16, 0, 128, 128, -128, 128)',
               f'polygon = PackedVector2Array({cfg["vision"]})')
    text = sub(text, '[node name="DestroyEffectSprite" type="Sprite2D" parent="."]\nvisible = false',
               '[node name="DestroyEffectSprite" type="Sprite2D" parent="."]\nvisible = false\n'
               f'modulate = {cfg["tint"]}')

    # --- load_steps = ext + sub + 1 ---
    n_ext = len(re.findall(r'^\[ext_resource', text, re.M))
    n_sub = len(re.findall(r'^\[sub_resource', text, re.M))
    text = sub(text, re.search(r'load_steps=\d+', text).group(0), f'load_steps={n_ext + n_sub + 1}')

    with open(path, "w") as f:
        f.write(text)
    print(f"[{name}] scene rebuilt: ext={n_ext} sub={n_sub} load_steps={n_ext + n_sub + 1}")


def main():
    for name, cfg in ENEMIES.items():
        build(name, cfg)


if __name__ == "__main__":
    main()
