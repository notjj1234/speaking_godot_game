# Enemy HP Crisp Numbers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make enemy `hp/max_hp` text sharp and readable under viewport nearest-neighbor stretch.

**Architecture:** Keep the existing world-space `EnemyHealthBar` (`Node2D` + `_draw` bar). Drop the mushy Control `Label` and draw the digits with `draw_string` / `draw_string_outline` using the in-repo pixel font `m5x7`, integer positions, size 12, outline 1. Public API (`setup`, `update_bar`, `hide_bar`) and bar chrome stay unchanged; `enemy.gd` counter-scale stays untouched.

**Tech Stack:** Godot 4.x GDScript, `FontFile` (`res://gui/fonts/m5x7.ttf`)

**Spec:** `docs/superpowers/specs/2026-11-26-enemy-hp-crisp-numbers-design.md`

## Global Constraints

- Touch only `enemies/scripts/enemy_health_bar.gd` for product code (optional headless test under `tools/tests/`).
- Do not change bar width/height/colors, show-on-damage behavior, or `enemy.gd` scale compensation.
- Format remains `"%d/%d"` for current/max HP.
- No `godot` binary in this environment — automated Godot headless runs are unavailable here; verify with static checks, then ask the human to click-test in the editor/web export.
- Do not commit unless the user explicitly asks.

## Review Focus

- Double-digit HP (e.g. `10/10`, `12/12`) must still fit above the 26px bar without clipping into the sprite.
- `hp == 0` still shows `0/N` while the bar is visible (destroy flow may hide shortly after).
- Scaled split enemies keep readable text because bar counter-scale in `enemy.gd` is unchanged.
- Bar fill colors (normal / caution / critical) still update; numbers do not steal redraw.
- Hidden before first hit (`visible = false` in `_ready`) still holds.

---

## File map

| File | Role |
|------|------|
| `enemies/scripts/enemy_health_bar.gd` | Only product file to modify — font, draw path, remove Label |
| `tools/tests/test_enemy_health_bar.gd` | Optional headless assertions for format + public API (for when Godot is available) |

---

### Task 1: Crisp HP number draw path

**Files:**
- Modify: `enemies/scripts/enemy_health_bar.gd`
- Create (optional): `tools/tests/test_enemy_health_bar.gd`

**Interfaces:**
- Consumes: existing `EnemyHealthBar.setup(max_hp: int)`, `update_bar(hp: int)`, `hide_bar()` as called from `enemies/scripts/enemy.gd`
- Produces: same public methods; no new callers; text rendered via `_draw()` with `NUMBER_FONT` = `m5x7`

- [x] **Step 1: Write failing headless assertions (optional but preferred)**

Create `tools/tests/test_enemy_health_bar.gd` as a `Node` with the same `_check` / pass-fail print pattern as `tools/tests/test_phonetic_matcher.gd`. Assertions:

```gdscript
func test_format_and_api() -> void:
	var bar := EnemyHealthBar.new()
	add_child(bar)
	bar.setup(3)
	# After setup, internal display string must be "3/3" — expose via a small
	# read-only helper if needed: get_display_text() -> String
	_check("setup shows max/max", bar.get_display_text() == "3/3")
	bar.update_bar(1)
	_check("update_bar shows current/max", bar.get_display_text() == "1/3")
	_check("visible after update", bar.visible == true)
	bar.hide_bar()
	_check("hide_bar hides", bar.visible == false)
	_check("font is m5x7", str(bar.NUMBER_FONT.resource_path).ends_with("m5x7.ttf"))
```

If adding `get_display_text() -> String` feels like test-only API, keep it thin: `return "%d/%d" % [_hp, _max_hp]`.

- [x] **Step 2: Note Godot unavailable — mark test as deferred run**

AGENTS.md: no `godot` on this Mac. Do not invent a run command that fails. Record: human runs later with  
`Godot --headless --path <project> -s res://tools/tests/test_enemy_health_bar.gd`  
(or attach a `.tscn` if the project prefers scene-based tests). Proceed to implement; static verify in Step 4.

- [x] **Step 3: Implement crisp numbers in `enemies/scripts/enemy_health_bar.gd`**

Replace Abaddon Label path with draw-string path. Locked values from the approved spec:

- `NUMBER_FONT := preload("res://gui/fonts/m5x7.ttf")`
- `NUMBER_SIZE := 12`
- `OUTLINE_SIZE := 1`
- Number color white; outline near-black (`Color(0, 0, 0, 0.9)`)
- Remove `_make_number`, `_number` Label, and `@onready` Label wiring
- In `_draw()`, after the bar rects, center the string horizontally over `BAR_W`, place baseline a few pixels above the bar (e.g. y ≈ `-2`), round position to integers
- Use `draw_string_outline(...)` then `draw_string(...)`
- Keep `setup` / `update_bar` / `hide_bar` / color thresholds / bar geometry
- Add `get_display_text() -> String` returning `"%d/%d" % [_hp, _max_hp]` if Step 1’s test needs it

- [x] **Step 4: Static verification (this environment)**

Run from project root:

```bash
rg -n "Abaddon|Label|_make_number|font_size|m5x7|draw_string" enemies/scripts/enemy_health_bar.gd
```

Expected:
- `m5x7.ttf` present; `Abaddon` absent
- `Label` / `_make_number` absent
- `draw_string` and `draw_string_outline` present
- size `12`, outline `1`
- `"%d/%d"` format still present

- [x] **Step 5: Human click-test checklist (report to user; do not claim done without noting this)**

In Godot editor or web export:
1. Hit a slime once — bar appears with readable `2/3` (or whatever max is).
2. Digits are sharp (no grey mush).
3. Damage to caution/critical still recolors the fill; numbers stay white.
4. Split/scaled enemy (if available) keeps same on-screen number size.

---

## Self-review notes

- Spec goals (crisp `hp/max`, same bar, m5x7, thinner outline, integer snap) → Task 1.
- Non-goals (pips, player HUD, bigger chrome) → not in plan.
- Review Focus items covered by API/format test + human checklist (double-digit fit, zero HP, scaled enemies, colors, initial hide).
