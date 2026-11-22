# RESEARCH.md — Bandit / Skeleton / Orc identity rework

Research for principles only — no external art was traced, downloaded, or reused.
All pixel art in this rework is derived from the project's own Goblin sheet via
deliberate structural edits (see `BRIEF.md` and the `artlib.py` / `build_*.py`
tooling in this folder).

## Bandit (hooded opportunist, dagger + buckler)

- https://www.summerengine.com/asset-store/player-rogue-pixel-art-sheet-revision-57fe0ccc —
  Top-down hooded rogue with dagger, 16-bit pixel style. **Borrowed:** the hood as the
  primary silhouette feature and the "dagger held low and ready" read at top-down angle.
  **Rejected:** hero-adventurer styling; our bandit is a cowardly opportunist, not a dungeon-crawler protagonist.
- https://opengameart.org/content/roguelite — Small top-down roguelike sprite set. **Borrowed:**
  proof that a hood + weapon blob reads as "human rogue" even at tiny sizes; confirmed the
  face-wrap/eye-slit is the cheapest way to read "masked human" (not a goblin) from above.
  **Rejected:** the set's flat single-shade hoods; we keep a 3-tone oxblood ramp with outline.

## Skeleton (kettle helm, spear, round shield)

- https://craftpix.net/product/top-down-pixel-skeletons-character-sprite-pack/ —
  Top-down pixel skeleton warriors with walk/run/attack. **Borrowed:** the pairing of a
  kettle-helm brim + round shield as an instantly readable "dead soldier" silhouette from above;
  also confirmed bone-tone bodies must keep a dark outline or they vanish on light floors.
  **Rejected:** horned/royal helmet variants (too boss-like) and their busy 4-direction rigs.
- https://www.summerengine.com/asset-store/skeleton-spear-hero-sprite-sheet-36eec384 —
  64x64 top-down skeleton spearman with shield-block poses. **Borrowed:** the vertical spear
  held at the shield side, and the "shield reads as a disc on the arm/back" convention at 64x64.
  **Rejected:** friendly-hero proportions; ours is a stiff, marionette-walking corpse.

## Orc (siege engine, cleaver, pauldron)

- https://www.sprite-ai.art/gallery/16x16-pixel-art-orc-with-weapon-2cdd —
  16x16 limited-palette orc. **Borrowed:** the discipline that an orc silhouette must be
  carried by a bulky torso + oversized weapon even when almost all detail is stripped.
  **Rejected:** 16x16 scale itself — our 64x64 cells can afford a pauldron, war paint, and cleaver.
- https://preview.simplepixelart-preview.pages.dev/arts/orc — Gallery of orc pixel art. **Borrowed:**
  the recurring topknot + underbite + single big shoulder-armor motif as "this is an orc, not a goblin"
  shorthand at any size. **Rejected:** most examples reuse the yellow-green goblin family;
  ours moves to charcoal-olive skin with iron + ochre accents.

## Shared principles (silhouette, telegraphing, rhythm)

- https://www.creatuneagency.com/en/blog/character-silhouette-and-readability/ —
  Character must read in solid black; for top-down cameras, enlarge head/shoulders/weapon and
  cut interior detail. **Borrowed:** this is the pass-bar test our three sheets must survive at 1x.
  **Rejected:** n/a (principle article, no art to reuse).
- https://coartist.net/blog/character-design-readability-silhouette-shape-language-contrast —
  Shape language: organized silhouette + contrast hierarchy beats detail. **Borrowed:** one
  signature feature per enemy (hood / shield+helm / pauldron+topknot) instead of many small ones.
- http://www.chaoticstupid.com/enemy-attacks-and-telegraphing/ — Enemy attacks must ask the
  player a question with a readable wind-up. **Borrowed:** the Orc's explicit telegraph-then-charge
  loop and the Skeleton's hold-range thrust rhythm; the Bandit's dart-in reads as the opposite
  (no telegraph, fast small commitment).

## Pages that could not be opened / weak sources

- The orc-specific searches returned mostly marketplace listings (GraphicRiver, Vecteezy) with
  no readable design content; they were not used beyond confirming the topknot/pauldron convention
  already captured above.
- `file_structure.txt` at repo root is a stale UTF-16 snapshot (per AGENTS.md) and was not used.
