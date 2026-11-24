# Horde art pass — 2026-11-24 (branch `art/horde-art-pass`)

Beetle / orc / skeleton / bandit sprite sheets rebuilt, two distinct NPCs with
blink/talk portraits, four Endless Horde arenas that swap every 20 stages, and
the tooling that builds and checks all of it. No Godot editor was available:
art is deterministic Pillow (`python3.13`), levels are generated `.tscn` text,
and everything below was verified statically. Speech/STT/scoring, save data,
`horde_curve.gd` difficulty numbers and every enemy/NPC `.tscn` are untouched.

Commits: `44c5718` art · `2b9a132` arenas · tooling + report (this commit).

## 1. Sprites — before / after (measured, `tools/art_qa/verify_sheets.py`)

| asset | art w × h (px) before → after | colours | min walk Δ | silhouette vs goblin | palette ∩ goblin |
|---|---|---|---|---|---|
| beetle `Beetle.png` 1024×128 | 19-29 × 21-32 → **31-34 × 24-30** | 9 → 12 | 27% → 28% | 56% → 55% | 0% → 0% |
| orc `orc.png` 512×192 | 29-40 × 37-47 → 27-37 × 43-48 | 12 → 12 | **0%** → 44% | 45% → 52% | 0% → 0% |
| skeleton `skeleton.png` 512×192 | 24-42 × 37-53 → 21-39 × 45-52 | 13 → 13 | 17% → 36% | 45% → 60% | 8% → 0% |
| bandit `bandit.png` 512×192 | 28-49 × 37-47 → 20-30 × 44-47 | 14 → 11 | **4%** → 41% | 47% → 53% | 7% → 0% |

(The old orc had identical consecutive walk frames; the old bandit barely moved.)

What changed in each, all as connected part rigs (head overlaps shoulders, fist
wraps grip, shield/buckler caps the forearm — contact shadows, no gaps):

* **Beetle** — indigo rhinoceros beetle: 3-tone violet shell + cool rim light,
  six umber legs on alternating tripods, amber horn + mandibles forward (down),
  shell seam and no face (up), dome profile with near/far legs (side), elytra
  flare open in the stun frames.
* **Orc** — trapezoid torso, huge forearms, small head + topknot, iron pauldron
  on the cleaver shoulder, rectangular cleaver in every direction (dragged in
  walk, raised in chase), jagged war-skirt, ochre war paint.
* **Skeleton** — tall bone-thin build, skull under a wide-brim rusty kettle
  helm, leaf-tip spear (upright in walk, levelled in chase), round shield on the
  arm (down/side) and slung on the back (up), ragged crimson tabard.
* **Bandit** — narrow-shouldered human, oxblood hood + scarf tail that follows
  the step, bone face-wrap with eye slit, short leather jack, tall boots, steel
  buckler on the off forearm, reverse-grip stiletto.

Contracts kept exactly: sheet sizes, grids, 64 px cells, frame maps, the 16 / 13
animation names, feet baselines (bbox bottom: down 56 / up 48 / side 50; beetle
54 / 53 / 53, all frames within ±1), 0% pure black, 10-20 opaque colours.

## 2. NPCs

| | before | after |
|---|---|---|
| `npc_sprite.png` (Daniel Devito) | 22-28 × 45-47, feet 52-54, 29 colours | 26-28 × 45-46, feet 54, 23 colours |
| `npc_sprite_02.png` (Stefano) | same body recoloured, 29 colours | 27-29 × 48, feet 54, 22 colours |
| sheet-to-sheet pixel difference | 62% (recolour only, same silhouette) | **97%** |
| portraits 01 vs 02 | 39% (same face, recoloured) | **96%** |

* **Daniel** — tutorial guide, civilian, warm palette: stout build, mustard flat
  cap, rust shirt, cream apron, leather satchel on the hip with a chest strap,
  moustache. Portrait on a warm sky with hills.
* **Stefano** — patrol guard, cool palette: narrower and taller, steel cap with
  nasal guard and blue plume, mail sleeves, blue tabard with a silver emblem,
  brass buckle, spear (upright front/back, sloped over the shoulder in profile).
  Portrait against a stone wall.
* Portraits: 400×148 = 4 frames (0 open, 1 blink, 2 talk, 3 blink + talk), the
  order `dialog_system.gd` cycles while a line plays.
* `gui/dialog_system/sprites/` copies are written by the build script with
  `shutil.copyfile` — byte-identical (checked by sha256).
* `npc/npc.tscn` and `npc/00_npcs/*.tres` unchanged (pinned sha256).

Honest note: the original NPC sheet and portrait were hand-painted with more
texture than a deterministic Pillow build reaches; the replacements trade that
detail for two clearly different characters.

## 3. Arenas

**Swap rule** — `HordeCurve.arena_index_for(stage) = int((max(stage,1) - 1) / 20) % 4`
(1-20 → 0, 21-40 → 1, 41-60 → 2, 61-80 → 3, 81+ cycles; practice → 0) and
`HordeCurve.arena_name_for(index)`. `horde_waves.gd` calls `_apply_arena(stage)`
at the top of `_begin_stage()` and in `_ready()` before anything spawns, so a
resume at stage 47 loads arena 3 (index 2) directly. It never swaps mid-stage.

| arena | stages | open | reachable | cover | motif / biome read |
|---|---|---|---|---|---|
| 1 Meadow | 1-20, practice | 70.3% | 100% | 5 pieces / 5 cells | winding dirt track, oaks, stump, mossy boulder, flowers; untinted bright grass |
| 2 Stone Ruins | 21-40 | 69.3% | 100% | 7 / 8 | broken colonnade framing a paved plaza, fallen pillar to the north; dry olive tint |
| 3 Ashen Camp | 41-60 | 68.7% | 100% | 5 / 10 | four tents round a trampled clay clearing with a fire pit, supplies, banners, scorch marks; dark ash-olive tint |
| 4 Frozen Hollow | 61-80 | 70.0% | 100% | 6 / 6 | open snowfield, ice crystals and frosted pines in a staggered diagonal, snow drifts; cold mint tint, grey cliffs |

Every arena is 20×15 cells, perimeter sealed with the tileset's cliff ring
(one-tile top edge, two-tile bottom face), no corridor under 2 tiles, all cover
free-standing (≤ 2×2, never touching the walls — chase AI has no pathfinding),
the 96 px spawn ring and ≥ 3 tiles round SpawnPoint (320, 240) clear, the
practice start-pad cells clear, nothing in rows 0-1 and no prop art above
y = 56 (WaveLabel band). Previews: `tools/arena_build/preview/arena_0N.png`
(1×, with the player on the spawn point, a goblin for scale, the stage label
and the spawn ring) plus `_3x` and `overview.png`.

**Scene shape** (`levels/endless_horde/arenas/arena_0N.tscn`, generated): root
`Arena` (Node2D, `arena.gd` / `HordeArena`: `display_name`, `ground_tint`,
`ground`, `is_blocked()`, `spawn_point()`, `nearest_open()`), `Ground` (instance
of `grass-01.tscn`, keeps `z_index -1` + `LevelTileMap`, overridden
`tile_map_data` and `modulate`), `Blockers` (StaticBody2D on layer 16 with one
rectangle per solid prop), `SpawnPoint` (Marker2D), `Decor` (Sprite2D props
using `Props.png`, hframes 16 / vframes 3).

**Swap procedure** (`horde_waves.gd:_apply_arena`): return if already loaded →
remove + free old Arena, TopBarrier and DecorLayer contents → instance, add,
`await process_frame` (camera bounds republished) → `_grass = Arena/Ground` →
reparent Decor sprites into the level's y-sorted `DecorLayer` → tint
GrassBackground → `_add_top_barrier()`, clear HordeEnemies (incl. pickups) →
player to `spawn_point()`, `_spawn_accum = spawn_interval(stage)` → label
`Stage N - <Arena Name>`.

Label uses a hyphen, not the `·` the brief asked for: `Abaddon Bold.ttf` has no
U+00B7 (its cmap was read) and the web build has no system font to fall back on.

Spawn safety: `_spawn_one_enemy` walks 16 angles round the ring while
`arena.is_blocked(pos)`, then `nearest_open()`; the practice dummy uses the same
guard. `is_blocked` = off-map, a tile with collision, or within 10 px of a
Blockers rectangle.

`endless_horde.tscn`: baked `Grass-01` node (and its ext_resource) removed,
`DecorLayer` (Node2D, y-sorted) added.

`Props.png` stays 1024×192 at the same path/uid; the bush at cell 0 is byte-for-
byte the original (checked); 22 props fill empty cells (frames 1-6 meadow,
16-20 ruins, 32-37 camp, 40-44 frozen).

## 4. Tooling

| command | what it does |
|---|---|
| `python3.13 tools/art_qa/verify_all.py` | 123 checks: sheet sizes/grids/cells, non-empty frames, baselines, colour counts, black share, walk deltas, silhouettes vs goblin + between directions, palette overlap, beetle size, NPC size/feet/colours/difference, portrait frames, byte-identical dialog copies, tscn contracts (texture path, hframes/vframes, Sprite2D scale + position, ShadowSprite2D scale, animation names), Props.png, frozen hashes, 14 pinned files unchanged. Writes `tools/art_qa/preview/*_grass_1x.png` / `*_silhouette_1x.png`. Exit 1 on any failure. |
| `python3.13 tools/arena_build/build_arenas.py [--check]` | ASCII maps → arena scenes; refuses maps that miss the design bar; `--check` also confirms the scenes match their maps and `horde_curve.gd` matches the swap rule and names. |
| `python3.13 tools/arena_build/render_arenas.py --all` | composites the previews. |
| `python3.13 tools/art_build/build_<beetle|orc|skeleton|bandit|npcs|portraits>.py`, `tools/arena_build/build_props.py` | regenerate the art (deterministic). |

The generator's refusals were exercised: gap in the perimeter, 1-tile corridor,
sealed pocket, prop in the spawn ring, 3-cell wall, prop in the label band — all
refused.

## 5. Corrections to the brief (found while checking)

* "scale 0.75" for orc/skeleton/bandit/goblin is the **ShadowSprite2D** scale;
  `Sprite2D` has no scale (1.0). Checks assert what the files say.
* The NPC sheets/portraits were a recolour of one character, not byte-identical.
* Slime has 10 colours only when semi-transparent pixels count (alpha 224); the
  colour count uses every pixel with alpha > 0.
* The path terrain's 47 tiles are not the textbook blob set (no inner corner
  with three filled corners); the autotiler picks the nearest piece — used once,
  Meadow cell (10, 7), visually fine in the preview.

## 6. Still needs an in-editor look (could not run Godot here)

1. **Scripts compile** — `arena.gd`, `horde_waves.gd`, `horde_curve.gd` were
   reviewed by hand only; open the project once so `HordeArena` registers.
2. **Camera clamp** after a swap (stage 21 via `]` dev key or Shift+number):
   bounds should stay 640×480 and the old arena should not flash.
3. **Y-sort feel** — walk behind/in front of an oak, column, tent; flat decals
   (flowers, flagstones, snow, scorch) should always be under feet.
4. **Spawn-ring feel** at stage 20+ quotas (radius up to 168 px) — enemies should
   appear round the player, never inside props.
5. **Prop occlusion / collision size** — blockers are 28×24 (60×24 for tent and
   fallen pillar); check the orc's charge stops cleanly on them, and that the new
   orc (up to 37 px wide at Sprite2D scale 1.0) feels right next to the player.
