# Enemy HP crisp numbers

**Date:** 2026-11-26  
**Status:** approved

## Intent

Make the `current/max` HP text above enemies readable in the pixel-art viewport so players can tell exact health at a glance. The green fill bar stays; only the number treatment changes.

## Goals / non-goals

- **Goal:** Sharp, legible `hp/max_hp` digits over the existing gold-border bar.
- **Goal:** Same layout and combat behavior (show on damage, colors by fraction).
- **Non-goal:** Pips, hearts, or a redesigned bar size/chrome.
- **Non-goal:** Player HUD hearts.
- **Anti-goal:** Soft/blurred TTF mush under nearest-neighbor stretch.

## Constraints

- World-space `Node2D` bar under `Enemy` (`enemies/scripts/enemy_health_bar.gd`).
- Project: `stretch/mode=viewport`, `default_texture_filter=0` (nearest).
- Keep counter-scale in `enemy.gd` so scaled enemies (splits) keep constant on-screen bar size.
- Prefer existing assets; `gui/fonts/m5x7.ttf` is already in-repo and unused.

## Approaches considered

1. **Crisp numbers (chosen)** — Pixel font, lighter outline, integer snap / draw path. Smallest diff, keeps exact HP text.
2. **HP pips** — Clear at low max HP; weak for higher max HP; changes the fantasy of the UI.
3. **Bigger chrome** — More readable but noisier over sprites and may overlap nearby enemies.

Chose **1** because the user wants crisp numbers and exact HP, not a new indicator style.

## Design

Touch only `enemies/scripts/enemy_health_bar.gd` (and font preload path):

1. Switch number font from Abaddon Bold → `m5x7.ttf`.
2. Raise font size from 8 → ~12 (still small over the sprite; m5x7 reads at this size).
3. Cut outline from 3 → 1 (or a single dark shadow) so glyphs aren’t drowned.
4. Prefer drawing the string in `_draw()` at integer coords (or snap Label position) so nearest-neighbor doesn’t smear subpixels.
5. Keep bar geometry, colors, show/hide, and `hp/max` format.

## Left to the builder

Exact font size / outline tweaks if 12/1 still feels off in-editor; whether Label vs `draw_string` — pick whichever stays sharp under viewport stretch with the least code.
