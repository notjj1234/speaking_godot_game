# Boss Stages: Design

**Date:** 2026-11-27
**Status:** draft, waiting for approval
**Plan:** `docs/superpowers/plans/2026-11-27-boss-stages.md`

## Problem

Endless Horde never ends a block on a high point. Each 20-stage block has its own arena (Meadow, Stone Ruins, Ashen Camp, Frozen Hollow), but stage 20 plays exactly like stage 19, and the arena change at 21 happens without any build-up. The game already reserves a boss hook, but it is dead code.

The user wants:
- a final boss at the end of every 20-stage block, unique to that block's arena
- a fight won by speaking (several speech challenges), not by grinding down a big HP bar
- a win that sends the player to the campfire camp the way a death does, but recorded as a victory, with extra rewards and "Fight on" resuming at the stage after the boss

## Current behaviour (verified)

| What | Where |
|---|---|
| Boss hook is dead: `BOSS_EVERY := 10`, and `is_boss_stage()` always returns false | `levels/endless_horde/horde_curve.gd:8`, `:88-90` |
| Arena block: `ARENA_STAGE_SPAN := 20`, `ARENA_COUNT := 4`, `arena_index_for(stage) = ((max(stage,1)-1)/20) % 4`. Stage 20 is still arena 0 | `horde_curve.gd:101-111` |
| Phrase difficulty band: 0-3, and 3 for every stage from 10 on | `horde_curve.gd:114-121` |
| Stage quota and enemy kinds | `horde_curve.gd:15-19` (`retry_quota`), `:48-85` (`kind_for`) |
| Horde startup reads `horde_resume_stage()` and starts there (0 means practice) | `levels/endless_horde/horde_waves.gd:57-77` |
| Stage loop: the clear pause runs out, then `_begin_stage(_stage + 1)` | `horde_waves.gd:97-101` |
| `_begin_stage` sets the quota, the WordTracker stage and the label | `horde_waves.gd:327-349` |
| `_on_stage_cleared` records the clear, flushes, and arms `_clear_pause` | `horde_waves.gd:352-361` |
| `_spawn_one_enemy` scales HP before `add_child` and turns splits off for every kind except beetle | `horde_waves.gd:364-401` (HP at `:371-374`, splits at `:381-391`) |
| Set-if-present tuning of state-node exports (`Chase.chase_speed`, `Wander.wander_speed`) | `horde_waves.gd:404-410` |
| Wave label `"Stage %d - %s"` | `horde_waves.gd:595-599` |
| `Enemy._ready` copies `hp` into `max_hp`; the health bar counter-scales against the enemy's scale | `enemies/scripts/enemy.gd:90`, `:95` |
| HP 0: pause, then pick a phrase with `get_speech_challenge_for_stage(stage)` | `enemy.gd:312-353` (pick at `:341-350`) |
| Challenge pass: record the kill, then emit `enemy_destroyed`, wait 0.45 s, resume | `enemy.gd:444-470` (emit at `:456`) |
| 3 tries per challenge; the last fail heals to `max_hp` and shows "the enemy recovers" | `enemy.gd:67`, `:473-499`, `:519-533` |
| Web: re-listens on errors and silence and never fails on silence; typed and speak-button fallback | `enemy.gd:374-385`, `:638-647`, `:815-856` |
| Process-always grace timer pattern (used by split children) | `enemy.gd:277-293` |
| Split children: `spawn_split_children` instances the enemy's own scene at `scale * split_scale` | `enemy.gd:199-237` |
| `enemy_destroyed` starts EnemyStateDestroy: the destroy animation, then `queue_free`; drops spawn on enter | `enemies/scripts/states/enemy_state_destroy.gd:21-39`, `:55-61`, `:69-84` |
| Death route: `record_horde_death(stage)`, then `GameOver.show_defeat()`, which loads the camp | `player/Scripts/player.gd:96-116`, `gui/game_over/game_over.gd:21-31` |
| Camp `_ready`: revive, convert gems to points, one `SaveManager.save_game()` | `levels/endless_horde/camp/camp.gd:14-21` |
| Camp fire actions: Fight on loads the horde, which reads `resume_stage` | `camp.gd:36-53`, `camp_fire.gd:29-36` |
| `record_horde_death` sets `resume_stage`, `stuck_stage`, `deaths_on_stage`, and on the 2nd death `short_retry` / `warmup` | `00_globals/progress_tracker.gd:221-240` |
| `note_stage_cleared` resets `resume_stage` only when `stuck_stage == stage` | `progress_tracker.gd:209-218` |
| `horde_run` defaults merge into old saves | `progress_tracker.gd:298-315` |
| Warm-up lowers the band by 1 on the stuck stage | `00_globals/global_word_tracker.gd:160-203` (`:168-173`) |
| Gems become `PlayerManager.bonfire_points` | `00_globals/global_player_manager.gd:26`, `:145-157` |
| HUD notices: `show_practice_notice()` has its text hard-coded; no general notice exists | `gui/player_hud/player_hud.gd:597` |

## Proposed design

### 1. Detection

- `HordeCurve.BOSS_EVERY := ARENA_STAGE_SPAN` (20). It moves below `ARENA_STAGE_SPAN` in the file.
- `is_boss_stage(stage) = stage > 0 and stage % BOSS_EVERY == 0`. This brings the dead hook to life.
- `retry_quota(stage, short)` returns 1 on a boss stage. The boss is the whole stage, and short-retry doesn't apply.
- `kind_for(stage, index)` returns the boss's base kind on a boss stage. The boss goes through the existing `_begin_stage`, then `_spawn_one_enemy`, then `Enemy` path. There is no second spawner.

### 2. Boss roster

`HordeCurve.BOSSES` is a constant array with one row per arena, indexed by `arena_index_for(stage)`. Stage 100 is therefore the Slime King again, scaled by the normal stage curve. The user said "repeat and tougher for the time being, more will be added later", so adding a boss means adding a row.

| Stage | Arena | Boss | Base scene | Tint | Signature move, sharpened on each phase change |
|---|---|---|---|---|---|
| 20 | Meadow | Slime King | slime | gold | Spawns 2 small slimes (existing `spawn_split_children`, `split_scale 0.5`, so they sit at net scale 1.0); `Wander.wander_speed` x1.15 |
| 40 | Stone Ruins | Bone Captain | skeleton | pale blue | `Chase.thrust_cooldown` x0.75, `Chase.thrust_speed` x1.15 |
| 60 | Ashen Camp | Orc Warlord | orc | ember red | `Chase.telegraph_duration` x0.8, `Chase.charge_speed` x1.15, `Chase.charge_cooldown` x0.8 |
| 80 | Frozen Hollow | Frost Bandit | bandit | ice blue | `Chase.dart_cooldown` x0.75, `Chase.dart_speed` x1.15 |

Each row has these fields: `name`, `kind`, `sheet: String`, `adds: int`, and `tune: {"State/prop": factor}`. Tuning uses the same set-if-present pattern as `horde_waves.gd:404-410`, so a missing property is skipped and doesn't crash.

**Look (revised 2026-11-27, user: "do it properly"):** the boss uses its base scene at `BOSS_SCALE := 2.0`, so hitboxes, attack boxes and animation keys all scale with it. Its art is a sheet of its own (`enemies/bosses/*.png`, built by `tools/art_build/build_bosses.py`), drawn at 2x resolution in the base sheet's frame layout. It's shown on a `BossSprite` child of the base `Sprite2D` at scale 0.5, so one art pixel is one screen pixel, with the same 1px outline as the player. The base sprite's own pixels are hidden (`self_modulate.a = 0`), but its flip, position keys and modulate flashes carry over to the child. The first version scaled the base art 2x with a tint, which doubled the outlines and pixel size, against the user's pixel-density bar. Each boss has its own palette and mark: a crowned violet slime, a captain's bicorne and coat, a horned helm, and an ice crown with a fur-trimmed hood.

### 3. Phases and challenges

- `BOSS_PHASES := 3`. Each phase is one health bar of `boss_phase_hp(stage) = maxi(4, roundi(3.0 * hp_multiplier(stage)))`: 10 at stage 20, 17 at 40, 24 at 60, 31 at 80. Base kind HP is ignored, so the Orc Warlord is not 3x tankier than the Slime King.
- When a bar reaches 0, the boss runs the **existing** challenge path unchanged: pause, STT, 3 tries, typed fallback, and on web partial matching plus phoneme forgiveness at 75 or above, with no fail on silence.
- **Phrase difficulty rises each phase:** `BOSS_PHASE_BANDS := [2, 3, 3]` (a short phrase, then a sentence, then a sentence).
  - `get_speech_challenge_for_stage(stage, band_override)` takes the band.
  - The existing warm-up (two deaths on this boss stage) still lowers it by 1.
- **Passing a phase that isn't the last** does not emit `enemy_destroyed`, so there is no destroy state, no drops and no `queue_free`. Instead `_advance_boss_phase()`:
  - moves to the next phase and refills the bar (`hp = max_hp`, health bar updated)
  - applies the row's `tune` factors once more, and spawns `adds` (Slime King)
  - emits `boss_phase_changed(phase, phases)`; the wave label shows `"Slime King 2/3"`
  - gives 1.25 s of process-always invulnerability (the split-grace pattern), so a swing already in flight can't chain straight into the next challenge
- **Passing the last phase** runs today's path: record the kill, then `enemy_destroyed`, then the destroy animation and drops.
- **Art:** the shadow and death-smoke sprites still scale 2x (they are soft effects, not character art). The boss sheets pass every `style_check.py` bar (outline, region, thickness, net scale). At 2x the base shapes alone left flat-region scores of 4.6-5.3 against the 4.0 bar; the user chose hand detail over a separate bar, so each boss carries its own detail pass in `build_bosses.py` (creases, plate seams, rivets, straps, bracers, war paint, epaulettes) plus a 2-row checker on wide tone boundaries. Scores now 3.8-3.9.

### 4. Fail penalty

The user asked for "Whatever that will challenge the user but not overly frustrate them".

- **Out of tries:** the **current bar** refills and the phase stays the same. `_host_challenge_fail` already does `hp = max_hp`, and `max_hp` is one phase bar, so this needs no code.
- **Dying to the boss:** the normal death route. The camp offers "Fight on", which resumes at the boss stage with a fresh boss.
- **Stuck on a boss:** after two deaths on the same boss stage, the existing warm-up drops every phase's phrase band by one.

### 5. Victory route

1. The last phase passes. The boss is destroyed, and its drops and any adds are cleared and collected through the normal stage-clear check at `horde_waves.gd:117-127`.
2. `_on_stage_cleared()` still calls `record_stage_cleared(stage)` (stats, plus the stuck reset). On a boss stage it then:
   - calls `ProgressTracker.record_boss_cleared(stage)` and `request_flush()`
   - sets the label to `"Boss defeated!"`, `_boss_exit = true`, and `_clear_pause = BOSS_CLEAR_PAUSE` (1.5 s)
3. When the pause ends, `_process` calls `_go_to_camp()` instead of `_begin_stage(_stage + 1)`.
   - It does nothing if `_leaving` is already set or `LevelManager.is_loading` is true.
   - Otherwise it sets `PlayerManager.player_spawned = false` and calls `LevelManager.load_new_level(CAMP_PATH, "", Vector2.ZERO)`.
   - If the camp scene is missing, it logs a ⚠️ and continues to the next stage.
4. Victory never calls `GameOver.show_defeat()` or `ProgressTracker.record_horde_death()`.

### 6. Rewards

- **Gems:** `boss_reward_gems(stage) = 10 + 5 * (stage / BOSS_EVERY - 1)`, so stage 20 gives 10, 40 gives 15, 60 gives 20, 80 gives 25 and 100 gives 30. The user picked gems that grow. The gems are added straight to `bonfire_points`, on top of any gems collected during the fight.
- **Granting:** the camp grants the reward (section 7).
- **Victory message:** the camp shows a HUD notice, `"Boss beaten! +10 gems"` (ASCII).

### 7. Persistence and reward-once

**New `horde_run` fields** (defaults in `_empty_horde_run`, so `_merge_horde_run` gives old saves zeros):
- `boss_cleared_stage: int`: the highest boss stage ever beaten.
- `boss_reward_stage: int`: the boss stage whose reward hasn't been granted yet (0 means none).

**New ProgressTracker API:**
- `record_boss_cleared(stage)`:
  - sets `resume_stage = stage + 1`
  - clears `stuck_stage`, `deaths_on_stage`, `short_retry` and `warmup`
  - raises `boss_cleared_stage`
  - sets `boss_reward_stage = stage`, then marks dirty
- `claim_boss_reward() -> int`: returns `boss_reward_stage`, sets it to 0, and marks dirty.
- `boss_cleared_stage() -> int`.

**Stale resume fix:** `note_stage_cleared(stage)` also resets `resume_stage` when it equals the cleared stage. Without this, clearing stage 21 after a victory would leave `resume_stage = 21` forever. Death behaviour doesn't change, because there `stuck_stage == resume_stage` and both reset already.

**Reward-once:** `Camp._ready` runs these steps, then makes its existing single `SaveManager.save_game()` call:
1. Claim the reward.
2. Add the gems.
3. Convert the collected gems.

The zeroed claim and the added points are written in the same save, so either both persist or neither does.

| Case | Result |
|---|---|
| Camp re-entered later (death, or `load_new_level`) | The claim returns 0, so +0 |
| `SaveManager.load_game()` while in the camp | The save already has the claim zeroed, so +0 |
| Reload between the victory flush and the camp | The save has the horde scene and `resume_stage = 21`, with the reward still pending. It is granted at the next camp visit, still exactly once |
| Beating the same boss again on a new run | A new victory, so a new reward (intended) |

### 8. The camp knows it was a victory

- `Camp.victory_gems: int` is set in `_ready` when a reward was claimed, and `Camp.is_victory() -> bool` returns `victory_gems > 0`.
- The HUD notice comes from a new `PlayerHud.show_notice(text)`, extracted from `show_practice_notice()`. Practice keeps its exact text and its `PracticeNotice` label, so `test_hud_layout` still finds it.
- The fire's lines stay the same: "Fight on" now resumes at stage 21 (Stone Ruins).

### 9. Wave label

- On a boss stage, `_stage_label(stage)` returns `"Stage %d - %s" % [stage, boss.name]`, for example `"Stage 20 - Slime King"`.
- Phase changes show `"%s %d/%d"`.
- `tools/tests/test_horde_arenas.gd:58-64` currently expects `"Stage 20 - Meadow"`, so it must be updated. This is an intended behaviour change, and the arena checks for stage 20 (still Meadow) stay.

## Alternatives considered and rejected

- **A new Boss scene or class per boss:** it needs new art, new scenes and a copy of the challenge code. A boss flag on `Enemy` reuses everything.
- **One big HP bar:** that's a damage sponge, which the brief rules out.
- **A dedicated boss spawner:** the brief forbids a parallel spawner, and `_spawn_one_enemy` already does the scaling.
- **Routing the victory through `GameOver.show_defeat()` with a flag:** it mixes victory into the death state, and `record_horde_death` would arm stuck and warm-up.
- **Granting the reward when the boss dies:** a reload before the camp could lose it or grant it twice. Claiming it inside the camp's existing save is atomic.
- **Resetting to phase 1 on a final fail:** too punishing ("not overly frustrate").
- **A reloaded horde redirecting itself to the camp when a reward is pending:** that nests a level load inside `SaveManager.load_game()`. Granting at the next camp visit is safe.
- **New boss moves now (projectiles, slams):** that would be a new combat system. The bosses reuse each kind's existing signature move, sharpened each phase.
- **A non-integer boss scale (1.5 or 1.6):** it breaks the pixel grid the user just had fixed.

## Risks

- **2x body in tight arenas:** the bigger collision box might clip props. `_unstick_enemy` (`horde_waves.gd:455-460`) checks only one point. [verify in editor]
- **Slime King adds:** they count as alive enemies, so the stage clears only when they're dead. This is intended, since it means more speaking. They spawn invulnerable with the existing split grace.
- **Spawn TTS and journal kill counts** use the base kind ("slime"). This is acceptable for v1; a boss kind in the journal is a follow-up.
- **The web path can't run headless** (`OS.has_feature("web")` is false). Bosses reuse `_start_speech_challenge` unchanged, but check in a browser that silence never fails and that the typed fallback and phoneme pass work in a boss phase. [verify in browser]
- **Tuning:** phase HP, reward size and the tune factors are first guesses. They are all constants in `HordeCurve`.

## Decisions to confirm

1. **Fail penalty:** refill the current bar and keep the phase. This is my reading of "challenge but not overly frustrate".
2. **Roster names, boss palettes/marks and tune factors** (section 2) are my calls.
3. **Phase phrase bands:** [2, 3, 3].
4. **Phase bar HP:** `maxi(4, roundi(3 * hp_multiplier(stage)))`.
5. **Victory pause** 1.5 s, **phase grace** 1.25 s.
6. **A reward left pending by a mid-flow reload** is granted at the next camp visit, not by bouncing the player into the camp.
7. **No new dev key:** `Shift+0` jumps to stage 10, and `]` steps one stage at a time to 20. Tests call `_jump_to_stage(20)` directly.

## Optional follow-ups (not in this plan)

- Boss sprites and boss-only moves.
- A boss kind in the journal's kill counts.
- A distinct boss health bar with phase pips.
- More bosses after stage 80.
