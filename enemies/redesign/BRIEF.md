# BRIEF.md — Bandit / Skeleton / Orc identity rework

Mission: replace three palette-swapped Goblin copies with three unmistakably distinct
creatures and fights. Pass bar: at 1x, sprites filled solid black must be separable;
after one encounter, each fight rhythm is describable in one sentence. No recolor,
no scale-up, no "Goblin with a hat."

Method note: `GenerateImage` is not configured in this environment, so art uses the
authorized **Pillow fallback** (`artlib.py` + `build_<enemy>.py`): the project's own
Goblin frames are the pose/timing base; silhouettes, heads, and gear are structurally
replaced and every color ramp is rebuilt. No external art was traced or downloaded.

Frame order (unchanged, all sheets): 0-3 down walk, 4-7 up walk, 8-11 side walk,
12-15 down chase, 16-19 up chase, 20-23 side chase. Idle/stun/destroy reuse cells
0/4/8. Sheet 512x192, 8x3, 64px cells, transparent, feet on Goblin's per-direction
baseline (down 56, up 48, side 50, ±2px).

---

## Bandit — "The Exit Strategy"

**Identity:** a human opportunist already planning his escape. He fights like a
mugger, not a soldier: keep range, circle, nick you, be gone.

- **Body plan:** human proportions, upright, *narrow* shoulders (Goblin is broad and
  hunched). Head-to-body ratio human (head ≈ 1/4 of height vs Goblin's huge 1/3 dome).
- **Silhouette feature (all directions):** oxblood hood with a scarf tail that
  flutters behind; no ears anywhere.
- **Palette:** hood oxblood `#7e3236`/`#5c2326`, umber leather `#7a5230`/`#54371e`,
  cold steel `#9fb0bd`, bone face-wrap `#d8c9a8`; outline dark umber `#2a1c14`. No green.
- **Gear:** slim stiletto (reverse grip, crossguard — not the Goblin club), round
  buckler strapped to the off forearm, tall boots. No loincloth (short leather jack).
- **Motion:** springy. Walk 0.48 s (keys 0/.12/.24/.36), chase 0.36 s (0/.09/.18/.27) —
  fastest cadence of the cast. Scarf tail offsets per frame for follow-through.
- **Stats:** HP 2, move 38, chase 55, weapon damage 2, contact 1. Fastest enemy.
- **Signature loop:** orbits the player at 52-64 px, strafing; every 1.6-2.4 s darts
  straight in for a quick slash, then darts back out to orbit. No telegraph — the read
  is his circling.
- **Drops:** gem (always), potion 40% chance. (Stolen loot.)
- **Audio/FX:** hit pitch 1.35 + amber flash tint `#ffae42`; destroy puff tinted warm.
- **Why not a Goblin:** no ears/tusks/loincloth, human narrow-shoulder build, hooded
  head shape, buckler + stiletto gear set, oxblood/umber family, 0.48/0.36 s timing,
  orbit-and-dart AI, 2 HP / 2 dmg profile. Nothing in the silhouette traces to Goblin
  beyond the shared leg poses of the base sheet.

## Skeleton — "Still Holding the Line"

**Identity:** a spearman who forgot he died. Still guards the spot, still pokes
anything that comes close. Tall, stiff, patient.

- **Body plan:** tallest of the cast; ultra-thin limbs, narrow ribcage torso —
  the opposite of Goblin's compact bulk. Head-to-body reads as a bare skull.
- **Silhouette feature (all directions):** rusty kettle helm (wide brim over a skull)
  plus a big round shield — shield on the arm in down/side, slung on the back in up.
- **Palette:** bone ivory `#e8e2cf`/`#c9c2a8`/`#968f78`, cold blue-grey `#7e8b99`,
  rust `#8a4a2c`, faded crimson tabard `#8c3a3a`; outline slate `#232c38`. No green, no flesh.
- **Gear:** spear (long shaft, leaf tip — not the Goblin club), kettle helm, round
  shield, ragged crimson tabard. No loincloth.
- **Motion:** marionette. Walk 1.0 s with *uneven* keys 0/.18/.55/.8; chase 0.7 s
  (0/.2/.42/.62). Idle shield-fidget is sold by the shield-on-back/arm read.
- **Stats:** HP 2, move 18, chase 26, weapon damage 4, contact 1. Slowest walker,
  longest reach, hardest single hit.
- **Signature loop:** holds spear range at 40-48 px — advances if you retreat,
  *backs off if you crowd him*, and every ~1.8 s makes a long straight thrust (lunge
  pulse). You fight a hinge, not a hunter.
- **Drops:** stone 1-2 (always), gem 60% 1-2. (A soldier's worthless kit.)
- **Audio/FX:** hit pitch 0.8 (dry rattle) + pale blue flash `#9fc4ff`.
- **Why not a Goblin:** vertical bone-thin build, skull + sockets instead of a faced
  head, brimmed helm silhouette, shield disc in every direction, spear, tabard instead
  of loincloth, ivory/blue-grey/rust family, 1.0 s uneven gait, retreat-and-thrust AI.

## Orc — "The Siege Engine"

**Identity:** a living battering ram with a bad temper. He does not chase you; he
picks a lane and becomes it.

- **Body plan:** trapezoid torso (wide shoulders, narrow waist — inverted from
  Goblin's pear shape), huge forearms, deliberately small head under a topknot,
  forward lean. Largest body in the cast.
- **Silhouette feature (all directions):** iron pauldron on one shoulder + topknot;
  the cleaver is visible in every direction.
- **Palette:** charcoal-olive skin `#4e5238`/`#6a6e4a`, iron `#6e7278`, ochre war
  paint `#c98a2e`, rust accents; outline near-black olive `#1e1a12`. Not Goblin's
  yellow-green — darker, greyer, desaturated.
- **Gear:** heavy cleaver (rectangular blade, dragged in walk — not the Goblin club),
  single iron pauldron, jagged leather war-skirt, topknot. No loincloth.
- **Motion:** heavy. Walk 1.2 s (0/.3/.6/.9) with shoulder sway; chase-stalk 0.9 s
  (0/.225/.45/.675). Slowest cadence.
- **Stats:** HP 5, move 16, stalk 22, charge 110 px/s, weapon damage 5, contact 2.
  Shortest vision cone (72 px). Max single hit 5 = respects the 6 HP player floor.
- **Signature loop:** stalks slowly toward you; at 56-88 px he **stops, plants, and
  telegraphs** (0.7 s shake + flash), then charges in a straight line; a wall or your
  shield stops him into a 0.9 s stagger. Then he does it again. You fight a door.
- **Drops:** apple 1-2 (always), gem (always 1), sword 8% chance. (Looted provisions.)
- **Audio/FX:** hit pitch 0.62 (deep thud) + deep crimson flash `#c2202a`;
  destroy puff tinted grey-green.
- **Why not a Goblin:** inverted trapezoid mass, small head vs Goblin's oversized
  dome, pauldron + topknot silhouette, cleaver, war-skirt vs loincloth, charcoal-olive
  family, 1.2/0.9 s stomp, telegraph-charge-stagger AI, 5 HP tank profile.

## Shared technical contract

- Scenes keep root `CharacterBody2D` (layer 256, mask 16), node names, `Sprite2D`
  at (0,-14) hframes=8 vframes=3, AnimationPlayer autoplay `idle_down`, state machine
  with `Idle` first, `VisionArea`, `AttackHurtBox` under Sprite2D, SFX-bus audio.
- `enemy.gd` gains only additive, default-preserving hooks: `uses_state_velocity`
  (default false) + `state_velocity`, `chaos_pauses_enabled` (default true),
  `slide_bounce_enabled` (default true). Goblin/Slime/Beetle behavior unchanged.
- New chase states subclass `EnemyStateChase` and call `super()` in overrides;
  exported `vision_area`/`attack_area`/`next_state` paths keep working.
- One-sentence rhythm check: **Bandit** circles you and darts in for nicks; the
  **Skeleton** keeps you at spear's length and pokes; the **Orc** stops, winds up,
  and charges like a door coming off its hinges.

## Rulings (decisions made beyond the brief)

- Ruling: art via Pillow fallback — `GenerateImage` is not configured in this
  environment; the brief authorizes fallback method 2. Cost if wrong: n/a (only
  available method).
- Ruling: new per-enemy hit/destroy WAVs are synthesized programmatically
  (enemies/<enemy>/hit_*.wav) because the project shares two slime WAVs across all
  enemies; scope allows new files inside enemy folders. Cost if wrong: audio files can
  be re-pointed at shared WAVs by editing one ext_resource line per scene.
