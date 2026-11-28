# Boss Stages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** End every 20-stage Endless Horde block (stages 20, 40, 60, 80, and so on) with an arena-specific boss. The boss has 3 phases, and each phase ends in a real speech challenge. Beating it sends the player to the campfire camp as a victory: growing gem reward, no death recorded, and "Fight on" resumes at the next stage.

**Architecture:**
- `HordeCurve` owns detection and the boss data table: `is_boss_stage` is live and `BOSS_EVERY = ARENA_STAGE_SPAN`.
- `horde_waves.gd` spawns the boss through the existing `_begin_stage` → `_spawn_one_enemy` path. It calls `Enemy.make_boss(...)` before `add_child`.
- `Enemy` gains a boss phase counter. A non-final challenge pass advances the phase instead of emitting `enemy_destroyed`. The final pass and every fail use today's code.
- On a cleared boss stage the horde records the victory in `ProgressTracker` and loads the camp through `LevelManager`.
- The camp claims the pending reward in the same save it already makes.

**Tech Stack:** Godot 4.7, GDScript, existing autoloads (`LevelManager`, `PlayerManager`, `ProgressTracker`, `SaveManager`, `WordTracker`, `STTManager`, `PlayerHud`).

**Spec:** `docs/superpowers/specs/2026-11-27-boss-stages-design.md`

## Global Constraints
- **Text:** all new on-screen text is ASCII only (pixel font). New strings: `"Stage %d - %s"`, `"%s %d/%d"`, `"Boss defeated!"`, `"Boss beaten! +%d gems"`, and the boss names in the spec.
- **Logging:** new runtime logs use ✅/❌/⚠️ prefixes.
- **Autoloads** are reached through `/root/NAME` or their global name, as the touched file already does. Level changes go only through `LevelManager.load_new_level`.
- **No new combat system, framework, scene or art.** Bosses are existing enemy scenes, scaled by `HordeCurve.BOSS_SCALE` (2.0, a whole number, which keeps the pixel grid) and tinted.
- **Speech:** every boss phase uses the unchanged `Enemy._start_speech_challenge` path (pause, STT, 3 tries, typed fallback). Web must never fail on silence. Don't touch `enemy.gd:374-385`, `:615-662` or `:794-856`.
- **Victory** never calls `GameOver.show_defeat()` or `ProgressTracker.record_horde_death()`.
- **Off limits:**
  - Don't touch `State.player` (a static var).
  - Don't change the save `VERSION`. New fields arrive through `_empty_horde_run` defaults, so old saves keep loading.
- **Commits:** none unless the user asks. A "Checkpoint" step means: stop and show the diff.
- **Running a `tools/tests` scene.** The Godot binary is at `~/Downloads/Godot.app/Contents/MacOS/Godot`. Always run on a fresh throwaway copy, one copy per test file, because `user://save.sav` leaks between tests:
  ```bash
  run_test() { T=$(mktemp -d); rsync -a --exclude .git --exclude build --exclude graphify-out ./ "$T/p"; \
    sed -i '' "s/config\/name=\"[^\"]*\"/config\/name=\"bosstest-$(basename "$T")\"/" "$T/p/project.godot"; \
    G=~/Downloads/Godot.app/Contents/MacOS/Godot; "$G" --headless --path "$T/p" --import >/dev/null 2>&1; \
    "$G" --headless --path "$T/p" "res://tools/tests/$1" --quit-after 6000 2>&1 | grep -E "^(PASS|FAIL|RESULT)|SCRIPT ERROR|Parse Error"; }
  ```
  If the binary is missing, mark the runtime check `[verify in editor]` and don't claim it passed. `tools/ui_qa` scenes run with `python3.13 tools/ui_qa/run_headless_tests.py`.
- **Test file style:** follow `tools/tests/test_challenge_exit.gd`:
  - a `Node` or `Node2D` scene with `process_mode = PROCESS_MODE_ALWAYS`
  - `PASS name` / `FAIL name — detail` lines, then a final `RESULT passes=N failures=M`, then `get_tree().quit(1 if failures else 0)`
  - STT is faked by swapping `STTManager.provider` for `preload("res://tools/tests/fake_stt_provider.gd").new()` and restoring it afterwards
  - answers are driven with `PlayerHud.fallback_submitted.emit(PlayerHud.target_sentence)` (pass) or `.emit("zzzz wrong")` (miss)
  - every test that writes progress saves `ProgressTracker.snapshot()` first and restores it with `load_from_save` at the end

## Review Focus
1. **A non-final phase pass never emits `enemy_destroyed`.** Otherwise EnemyStateDestroy would `queue_free` the boss after phase 1. (Test in Task 4.)
2. **Phase grace.** A swing already in flight, or a second hit straight after resume, must not start the next challenge before the grace ends. (Test in Task 4.)
3. **Victory twice, or during a load.** Only one camp load starts. (Test in Task 5.)
4. **The reward is granted exactly once.** Camp re-entry and `SaveManager.load_game()` grant +0. (Test in Task 5.)
5. **Stale `resume_stage` after a victory.** Clearing stage 21 resets it to 0, and a death on stage 20 still resumes at 20. (Test in Task 2.)
6. **Old saves.** A `progress` dict with no boss fields loads with zeros. (Test in Task 2.)
7. **Web silence.** No new code on the web path. A boss phase is checked manually in a browser. (Task 7, `[verify in browser]`.)

---

### Task 1: Boss curve in HordeCurve

**Files:**
- Modify: `levels/endless_horde/horde_curve.gd` (header comment `:4-7`, `BOSS_EVERY` at `:8`, `retry_quota` at `:15-19`, `kind_for` at `:48`, `is_boss_stage` at `:88-90`)
- Test: `tools/tests/test_boss_curve.gd` + `.tscn`

**Interfaces:**
- Constants, placed below `ARENA_STAGE_SPAN` so they can refer to it:
  - `BOSS_EVERY := ARENA_STAGE_SPAN`
  - `BOSS_PHASES := 3`
  - `BOSS_PHASE_BANDS := [2, 3, 3]`
  - `BOSS_SCALE := 2.0`
  - `BOSS_CLEAR_PAUSE := 1.5`
  - `BOSS_PHASE_GRACE := 1.25`
  - `BOSS_REWARD_BASE := 10`
  - `BOSS_REWARD_STEP := 5`
  - `BOSSES: Array[Dictionary]`, one row per arena index, with these values:
    ```gdscript
    {"name": "Slime King",   "kind": "slime",    "tint": Color(1.0, 0.85, 0.35), "adds": 2,
     "tune": {"Wander/wander_speed": 1.15}},
    {"name": "Bone Captain", "kind": "skeleton", "tint": Color(0.75, 0.85, 1.0), "adds": 0,
     "tune": {"Chase/thrust_cooldown": 0.75, "Chase/thrust_speed": 1.15}},
    {"name": "Orc Warlord",  "kind": "orc",      "tint": Color(1.0, 0.6, 0.5),   "adds": 0,
     "tune": {"Chase/telegraph_duration": 0.8, "Chase/charge_speed": 1.15, "Chase/charge_cooldown": 0.8}},
    {"name": "Frost Bandit", "kind": "bandit",   "tint": Color(0.7, 0.9, 1.0),   "adds": 0,
     "tune": {"Chase/dart_cooldown": 0.75, "Chase/dart_speed": 1.15}},
    ```
- `static func is_boss_stage(stage: int) -> bool`: `stage > 0 and stage % BOSS_EVERY == 0`.
- `static func boss_for_stage(stage: int) -> Dictionary`: `{}` when it isn't a boss stage, otherwise `BOSSES[arena_index_for(stage) % BOSSES.size()]`.
- `static func boss_phase_hp(stage: int) -> int`: `maxi(4, roundi(3.0 * hp_multiplier(stage)))`.
- `static func boss_phase_band(phase: int) -> int`: `BOSS_PHASE_BANDS[clampi(phase, 0, BOSS_PHASE_BANDS.size() - 1)]`.
- `static func boss_reward_gems(stage: int) -> int`: `BOSS_REWARD_BASE + BOSS_REWARD_STEP * maxi(stage / BOSS_EVERY - 1, 0)`. Returns 0 when it isn't a boss stage.
- `retry_quota(stage, short)`: returns 1 first when `is_boss_stage(stage)`.
- `kind_for(stage, index)`: returns `boss_for_stage(stage).kind` first when `is_boss_stage(stage)`.

- [ ] **Step 1: Write the failing test** `test_boss_curve.gd`, which asserts:
  - `is_boss_stage` is false for 0, 1, 19, 21, and true for 20, 40, 100
  - `retry_quota(20, false) == 1`, `retry_quota(20, true) == 1`, and `retry_quota(19, false) == spawn_total(19)` (unchanged)
  - `kind_for(20, 0) == "slime"`, `kind_for(40, 3) == "skeleton"`, `kind_for(60, 0) == "orc"`, `kind_for(80, 0) == "bandit"`, `kind_for(100, 0) == "slime"` (repeats)
  - `kind_for(19, 0) == "beetle"` (unchanged)
  - `boss_for_stage(19).is_empty()`, and `boss_for_stage(20).name == "Slime King"`
  - for every s in [20, 40, 60, 80], `BOSSES.find(boss_for_stage(s)) == arena_index_for(s)` (the boss matches the block's arena)
  - `boss_phase_band(0) == 2`, `boss_phase_band(1) == 3`, `boss_phase_band(2) == 3`, `boss_phase_band(9) == 3`
  - `boss_reward_gems(20) == 10`, `(40) == 15`, `(100) == 30`, `(19) == 0`
  - `boss_phase_hp(20) == 10`, and `boss_phase_hp(1) >= 4`
  - every boss name is ASCII (every `unicode_at(i) < 128`)
- [ ] **Step 2: Run** `run_test test_boss_curve.tscn`. Expected: a parse error or FAILs, because the functions don't exist yet.
- [ ] **Step 3: Implement** per the Interfaces block. Rewrite the header comment: boss every `BOSS_EVERY` stages, and the idle-DPS note stays.
- [ ] **Step 4: Run** `run_test test_boss_curve.tscn`. Expected: every line PASS and `RESULT ... failures=0`.
- [ ] **Step 5: Verify** that nothing else broke: `run_test test_horde_arenas.tscn`. Expected: `failures=0`. The label doesn't change until Task 5. If the stage-20 spawn check fails because the quota is now 1, note it here. Task 5 rewrites that row.
- [ ] **Step 6: Checkpoint.**

---

### Task 2: Boss progress fields in ProgressTracker

**Files:**
- Modify: `00_globals/progress_tracker.gd` (`note_stage_cleared` at `:209-218`, `_empty_horde_run` at `:298-305`, new functions after `horde_warmup` at `:255`)
- Test: `tools/tests/test_boss_progress.gd` + `.tscn`

**Interfaces:**
- `_empty_horde_run()` gains `"boss_cleared_stage": 0` and `"boss_reward_stage": 0`.
- `func record_boss_cleared(stage: int) -> void`:
  - returns at once when `stage <= 0`
  - otherwise sets `resume_stage = stage + 1`, `stuck_stage = 0`, `deaths_on_stage = 0`, `short_retry = false`, `warmup = false`
  - sets `boss_cleared_stage = maxi(old, stage)` and `boss_reward_stage = stage`
  - then `mark_dirty()` and a `✅` log
- `func claim_boss_reward() -> int`: reads `boss_reward_stage`. If it is above 0, sets it to 0 and calls `mark_dirty()`. Returns the value it read.
- `func boss_cleared_stage() -> int`.
- `func boss_reward_pending() -> int`: read-only; used by tests and the camp log.
- `note_stage_cleared(stage)`: before the existing `stuck_stage` check, add: `if int(run.get("resume_stage", 0)) == stage: run["resume_stage"] = 0`. The function still returns early when `stuck_stage != stage` for the other fields.

- [ ] **Step 1: Write the failing test** `test_boss_progress.gd`. Save `ProgressTracker.snapshot()` first and restore it at the end.
  - **Old save:** `load_from_save({"version": 1, "horde_run": {"resume_stage": 7}})`. Then `horde_resume_stage() == 7`, `boss_cleared_stage() == 0` and `boss_reward_pending() == 0`.
  - **Victory clears the stuck state:** `load_from_save({})`, `record_horde_death(20)` twice, then `record_stage_cleared(20)` and `record_boss_cleared(20)`. Then:
    - `horde_resume_stage() == 21`, `horde_stuck_stage() == 0`, `horde_short_retry() == false`, `horde_warmup() == false`
    - `boss_cleared_stage() == 20`, `boss_reward_pending() == 20`
  - **Claim once:** `claim_boss_reward() == 20`, then `claim_boss_reward() == 0`.
  - **Round trip:** `record_boss_cleared(40)`, then `var snap := snapshot()`, then `load_from_save(snap)`. Then `boss_reward_pending() == 40` and `boss_cleared_stage() == 40`.
  - **Stale resume:** after the round trip, `record_stage_cleared(41)`, then `horde_resume_stage() == 0`.
  - **Death unchanged:** `load_from_save({})`, then `record_horde_death(20)`. `horde_resume_stage() == 20`. Then `record_stage_cleared(20)`, and `horde_resume_stage() == 0`, `horde_stuck_stage() == 0`.
  - **Bad input:** `record_boss_cleared(0)` changes nothing (`boss_reward_pending()` unchanged).
- [ ] **Step 2: Run** `run_test test_boss_progress.tscn`. Expected: FAIL or a script error (no such method).
- [ ] **Step 3: Implement** per the Interfaces block.
- [ ] **Step 4: Run** `run_test test_boss_progress.tscn`. Expected: all PASS, `failures=0`.
- [ ] **Step 5: Verify** there are no regressions in save and camp: `run_test test_save_load.tscn` and `run_test test_camp_flow.tscn`. Expected: both `failures=0`.
- [ ] **Step 6: Checkpoint.**

---

### Task 3: Band override for the stage challenge picker

**Files:**
- Modify: `00_globals/global_word_tracker.gd` (`get_speech_challenge_for_stage` at `:160-173`)
- Test: add to `tools/tests/test_boss_curve.gd`

**Interfaces:**
- `func get_speech_challenge_for_stage(stage: int, band_override: int = -1) -> String`
  - `target_band = band_override if band_override >= 0 else HordeCurve.band_for_stage(stage)`
  - The warm-up branch subtracts 1 from `target_band`, clamped at 0, for either source.
  - The rest (harder, then easier, then any, then `"cat"`) is unchanged.
  - Existing one-argument callers (`enemy.gd:346`, `camp_conversation.gd:249`) behave exactly as before.

- [ ] **Step 1: Write the failing test**, appended to `test_boss_curve.gd`. Save and restore `ProgressTracker.snapshot()`.
  - With `load_from_save({})`: `WordTracker._band_of_phrase(WordTracker.get_speech_challenge_for_stage(20, 2)) == 2`, sampled 10 times.
  - Warm-up: `record_horde_death(20)` twice, then the same call returns band 1, sampled 10 times.
  - No override: `get_speech_challenge_for_stage(20)` returns band 2 under warm-up (3 - 1, unchanged behaviour).
- [ ] **Step 2: Run** `run_test test_boss_curve.tscn`. Expected: the override checks FAIL (an extra argument is a parse error, or the band is wrong).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `run_test test_boss_curve.tscn`. Expected: all PASS.
- [ ] **Step 5: Verify** the existing challenge behaviour: `run_test test_challenge_exit.tscn` and `run_test test_camp_conversation.tscn`. Expected: `failures=0`.
- [ ] **Step 6: Checkpoint.**

---

### Task 4: Boss phases on Enemy

**Files:**
- Modify: `enemies/scripts/enemy.gd`:
  - new signal near `:6-8`
  - boss vars near `:60`
  - `_take_damage` pick at `:341-350`
  - `_on_speech_result` success branch at `:451-469`
  - `_flash_challenge_success` at `:536-542`
  - new functions after `make_practice_dummy` at `:296-308`
- Test: `tools/tests/test_boss_fight.gd` + `.tscn`

**Interfaces:**
- `signal boss_phase_changed(phase: int, phases: int)`: `phase` is 1-based for display. It is emitted after the bar refills.
- Vars:
  - `var boss_phases: int = 0` (0 means a normal enemy)
  - `var boss_phase: int = 0` (0-based)
  - `var boss_name: String = ""`
  - `var boss_tint: Color = Color.WHITE`
  - `var _boss_tune: Dictionary = {}`
  - `var _boss_adds: int = 0`
- `func make_boss(profile: Dictionary, phase_hp: int) -> void`: must be called **before** `add_child`, because `_ready` copies `hp` into `max_hp`. It:
  - sets `boss_phases = HordeCurve.BOSS_PHASES`, `boss_phase = 0`, `hp = phase_hp`, `boss_name`, `boss_tint`, `_boss_tune`, `_boss_adds`
  - sets `scale = Vector2.ONE * HordeCurve.BOSS_SCALE`, `splits_on_destroy = false`, `split_scale = 0.5` and `split_hp = maxi(1, phase_hp / 4)`
  - sets `name = boss_name.replace(" ", "")`. The base kind still resolves through `scene_file_path` in `_progress_kill_kind`.
  - In `_ready`, apply the tint with `if is_boss(): sprite.modulate = boss_tint`.
- `func is_boss() -> bool`: `boss_phases > 0`.
- `func _advance_boss_phase() -> void`:
  1. `boss_phase += 1`, `hp = max_hp`, `health_bar.update_bar(hp)`
  2. For each `"State/prop": factor` in `_boss_tune`, find `get_node_or_null("EnemyStateMachine/" + State)`. If the property exists, multiply it (set-if-present).
  3. If `_boss_adds > 0`: `splits_on_destroy = true`, `split_count = _boss_adds`, `spawn_split_children()`. This clears `splits_on_destroy` again.
  4. `boss_phase_changed.emit(boss_phase + 1, boss_phases)`, with a `✅` log.
  5. Grace: `invulnerable = true`, `await get_tree().create_timer(HordeCurve.BOSS_PHASE_GRACE, true, false, true).timeout`, `invulnerable = false`. This is the pattern at `:290-293`.
- `_take_damage` pick: when `is_boss()` and `stage > 0`, `challenge = word_tracker.get_speech_challenge_for_stage(stage, HordeCurve.boss_phase_band(boss_phase))`. Otherwise it is unchanged.
- `_on_speech_result(true, ...)`: if `is_boss() and boss_phase < boss_phases - 1`:
  - call `word_tracker.add_spoken_word(...)` and `_flash_challenge_success()`
  - call `_advance_boss_phase()` without awaiting it, so the grace runs on in the background
  - wait 0.45 s (same timer as today), then `_resume_game_after_challenge()`
  - skip `record_kill` and `enemy_destroyed.emit`

  Otherwise the existing branch runs unchanged.
- `_flash_challenge_success`: tween to `boss_tint if is_boss() else Color.WHITE`.
- `_host_challenge_fail`: **no change**. `hp = max_hp` refills the current phase's bar, which is the spec's fail penalty.

- [ ] **Step 1: Write the failing test** `test_boss_fight.gd`.
  - **Setup:**
    - Swap in `FakeStt` and set `WordTracker.horde_stage = 20`.
    - Instance `res://enemies/slime/slime.tscn`, call `make_boss(HordeCurve.boss_for_stage(20), 10)`, `add_child`, and place it far from the player.
    - Set `Destroy.drops = []` on it so no pickups appear.
    - Count `enemy_destroyed` and `boss_phase_changed` emissions.
    - Use `killer := HurtBox.new()` with `damage = 99`, added as a child.
  - Check the scale: `boss.scale == Vector2(2, 2)`, `boss.max_hp == 10` and `boss.is_boss()`.
  - **Phase 1 band:** `boss._take_damage(killer)`, then `WordTracker._band_of_phrase(PlayerHud.target_sentence) == 2`.
  - **Phase 1 pass:**
    - `PlayerHud.fallback_submitted.emit(PlayerHud.target_sentence)`, then wait 0.7 s.
    - Expect `boss_phase == 1`, `hp == max_hp`, destroyed count 0, phase signal count 1 with args `(2, 3)`, `is_instance_valid(boss)` and `not get_tree().paused`.
  - **Grace:** straight away, `boss.invulnerable == true`. `boss._take_damage(killer)` doesn't start a challenge (`WordTracker.speech_challenge_active == false`). After 1.4 s, `invulnerable == false`.
  - **Adds:** the slime boss spawned 2 children in its parent (`Enemy` siblings count +2).
  - **Phase 2 band:** `_take_damage(killer)`, then `_band_of_phrase(PlayerHud.target_sentence) == 3`.
  - **Final fail on a phase:**
    - Send `fallback_submitted.emit("zzzz wrong")` 3 times, 0.1 s apart, then wait 2.5 s.
    - Expect `boss_phase == 1` (unchanged), `hp == max_hp` (bar refilled), destroyed count 0, and `not paused`.
  - **Phase 2 and phase 3 pass:**
    - Pass phase 2. After the grace, take damage again and pass the final phase.
    - Expect destroyed count == 1, and `ProgressTracker.lifetime().kills.slime` went up by exactly 1 across the whole fight.
  - **Tint:** after a phase pass and 0.5 s, `boss.sprite.modulate.is_equal_approx(boss.boss_tint)`.
  - **Normal enemy unchanged:** a plain slime still emits `enemy_destroyed` on its first pass.
  - Restore the provider and the progress snapshot. Free the adds.
- [ ] **Step 2: Run** `run_test test_boss_fight.tscn`. Expected: a parse error or FAIL (no `make_boss`).
- [ ] **Step 3: Implement** per the Interfaces block.
- [ ] **Step 4: Run** `run_test test_boss_fight.tscn`. Expected: all PASS, `failures=0`.
- [ ] **Step 5: Verify** the enemy suite: `run_test test_challenge_exit.tscn`, `run_test test_enemy_destroy_wall.tscn`, `run_test test_enemy_health_bar.tscn` (if it has a `.tscn`), `run_test test_voice_only_fail_open.tscn` and `run_test test_stt_suspend.tscn`. Also run `python3.13 tools/tests/test_combat_softlock_contracts.py` and `python3.13 tools/tests/test_web_stt_contracts.py`. Expected: all `failures=0` / exit 0.
- [ ] **Step 6: Checkpoint.**

---

### Task 5: Horde wiring: spawn, label, victory route

**Files:**
- Modify: `levels/endless_horde/horde_waves.gd`:
  - consts near `:3-10`
  - vars near `:36-47`
  - `_process` at `:97-101`
  - `_jump_to_stage` at `:187-195`
  - `_on_stage_cleared` at `:352-361`
  - `_spawn_one_enemy` at `:381-401`
  - `_stage_label` at `:595-599`
- Modify: `tools/tests/test_horde_arenas.gd:58-64`. The stage-20 row expects the boss label and one spawn. This is an intended behaviour change, and the arena, decor and barrier checks for stage 20 stay.
- Test: `tools/tests/test_boss_flow.gd` + `.tscn` (end to end; covers Task 6 too)

**Interfaces:**
- `const CAMP_PATH := "res://levels/endless_horde/camp/camp.tscn"`
- `var _boss_exit := false`, `var _leaving := false`
- `_spawn_one_enemy`: after the splits block (`:391`) and before choosing a position:
  ```gdscript
  var boss := HordeCurve.boss_for_stage(_stage)
  if not boss.is_empty():
      enemy.make_boss(boss, HordeCurve.boss_phase_hp(_stage))
  ```
  After `add_child` (`:399`), if it is a boss, connect `enemy.boss_phase_changed.connect(_on_boss_phase_changed.bind(enemy))`.
- `func _on_boss_phase_changed(phase: int, phases: int, boss: Enemy) -> void`: `_label.text = "%s %d/%d" % [boss.boss_name, phase, phases]`.
- `_stage_label(stage)`: if `HordeCurve.is_boss_stage(stage)`, return `"Stage %d - %s" % [stage, HordeCurve.boss_for_stage(stage).name]`. Otherwise it is unchanged.
- `_on_stage_cleared()`: the existing body runs first. Then, if `HordeCurve.is_boss_stage(_stage)`:
  - call `tracker.record_boss_cleared(_stage)` (has_method-guarded) and `tracker.request_flush()`
  - set `_label.text = "Boss defeated!"`, `_boss_exit = true`, `_clear_pause = HordeCurve.BOSS_CLEAR_PAUSE`
  - log ✅
- `_process` clear-pause branch: when `_clear_pause` reaches 0 or below, call `_go_to_camp()` if `_boss_exit`, otherwise `_begin_stage(_stage + 1)`.
- `func _go_to_camp() -> void`:
  - Return if `_leaving or LevelManager.is_loading`.
  - If `not ResourceLoader.exists(CAMP_PATH)`: ⚠️ log, `_boss_exit = false`, `_begin_stage(_stage + 1)`, return.
  - Otherwise `_leaving = true`, `PlayerManager.player_spawned = false`, `LevelManager.load_new_level(CAMP_PATH, "", Vector2.ZERO)`.
- `_jump_to_stage`: also reset `_boss_exit = false`.

- [ ] **Step 1: Write the failing tests.**
  - **(a)** In `test_horde_arenas.gd`, change the stage-20 expected label to `"Stage 20 - Slime King"`. Add `_check("stage 20 spawns exactly one boss", ...)`: one `Enemy` child with `is_boss()` and `scale == Vector2(2, 2)`.
  - **(b)** `test_boss_flow.gd`, structured like `test_camp_flow.gd` (`get_tree().current_scene = null`, `_await_scene`). Save the progress snapshot and `bonfire_points`, swap in FakeStt.
    1. `load_from_save({})`, `bonfire_points = 0`. Load the horde through `LevelManager.load_new_level(HORDE, ...)` and await `EndlessHorde`.
    2. `horde._jump_to_stage(20)`, then wait about 60 frames. Expect exactly one boss in `HordeEnemies`, and the label `"Stage 20 - Slime King"`.
    3. Set `Destroy.drops = []` on the boss. For each of the 3 phases: wait for `not boss.invulnerable`, call `boss._take_damage(killer)`, emit `fallback_submitted(PlayerHud.target_sentence)`, and kill any adds the same way. After phase 1, expect the label `"Slime King 2/3"`.
    4. Count `LevelManager.level_load_started` emissions. `await _await_scene("Camp", 10.0)`. Expect:
       - one load started
       - `GameOver._camp_requested == false`
       - `ProgressTracker.horde_stuck_stage() == 0` (no death recorded)
       - `horde_resume_stage() == 21`, `boss_cleared_stage() == 20`, `boss_reward_pending() == 0`
       - `current_scene.is_victory()` and `current_scene.victory_gems == 10`
       - `PlayerManager.bonfire_points == 10`
    5. **Double victory guard:** a separate run on a horde instance. Call `_go_to_camp()` twice in the same frame. Expect one `level_load_started`.
    6. **Re-enter the camp:** `LevelManager.load_new_level(CAMP, ...)` and await Camp. Expect `bonfire_points == 10` and `is_victory() == false`.
    7. **Reload:** `SaveManager.load_game()` and await the scene. Expect `bonfire_points == 10`.
    8. **Fight on:** `current_scene._on_fire_action("fight")`, await EndlessHorde, wait 3 frames. Expect `horde._stage == 21` and `horde._arena.display_name == "Stone Ruins"`.
    9. Restore everything, then print RESULT.
- [ ] **Step 2: Run** `run_test test_horde_arenas.tscn` and `run_test test_boss_flow.tscn`. Expected: the new checks FAIL (no boss label, no camp load).
- [ ] **Step 3: Implement** per the Interfaces block. Task 6 is needed for the camp asserts in steps 4 and 6. Implement Task 6 before step 4.
- [ ] **Step 4: Run** both again after Task 6. Expected: all PASS, `failures=0`.
- [ ] **Step 5: Verify** there are no regressions: `run_test test_camp_flow.tscn`, `run_test test_camp_scene.tscn` and `run_test test_save_load.tscn`. Expected: `failures=0`.
- [ ] **Step 6: Checkpoint.**

---

### Task 6: Camp victory and HUD notice

**Files:**
- Modify: `levels/endless_horde/camp/camp.gd` (`_ready` at `:14-21`)
- Modify: `gui/player_hud/player_hud.gd` (extract from `show_practice_notice` at `:597`)
- Test: covered by `test_boss_flow` (Task 5). `tools/tests/test_hud_layout.gd` guards the practice notice.

**Interfaces:**
- `Camp`:
  - `var victory_gems: int = 0`
  - `func is_victory() -> bool`: `victory_gems > 0`
  - `func _claim_boss_reward() -> void`: if the `/root/ProgressTracker` claim returns `stage > 0`:
    - `victory_gems = HordeCurve.boss_reward_gems(stage)` and `PlayerManager.bonfire_points += victory_gems`
    - `PlayerHud.show_notice("Boss beaten! +%d gems" % victory_gems)`
    - ✅ log
  - New order in `_ready`: `_prepare_ground()`, `super()`, `revive_for_horde()`, **`_claim_boss_reward()`**, `convert_gems_to_points()`, then `SaveManager.save_game()`. The existing single save now persists both the zeroed claim and the points.
- `PlayerHud`:
  - `func show_notice(text: String) -> void`: the body of today's `show_practice_notice()`, with the label text set from `text`. It keeps the `_practice_notice_label` node and its `PracticeNotice` name, the banner-aware placement and the tween.
  - `show_practice_notice()` becomes `show_notice("Practice — you can't die here!")`. The text is exactly as it is today.

- [ ] **Step 1: Write the failing test.** This is the camp half of `test_boss_flow` steps 4 and 6 (Task 5). Also add to `test_hud_layout.gd`: `PlayerHud.show_notice("Boss beaten! +10 gems")` puts that text on the `PracticeNotice` label.
- [ ] **Step 2: Run** `run_test test_boss_flow.tscn` and `run_test test_hud_layout.tscn`. Expected: `is_victory` and `show_notice` FAIL (missing methods). `test_hud_layout` F29 fails as it did before this work, which is pre-existing.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** both. Expected: `test_boss_flow` passes in full. In `test_hud_layout`, only the pre-existing F29 fails and the new notice check PASSes.
- [ ] **Step 5: Verify** the UI: `python3.13 tools/ui_qa/run_headless_tests.py` (exit 0) and `python3.13 tools/ui_qa/input_audit.py` (0 findings).
- [ ] **Step 6: Checkpoint.**

---

### Task 7: Full regression and manual checks

**Files:** none changed.

- [ ] **Step 1:** Run every `tools/tests/*.tscn` with `run_test`, each on a fresh copy. Expected: all `failures=0`, except the pre-existing `test_hud_layout` F29.
- [ ] **Step 2:** Run `python3.13 tools/tests/test_*.py`, `python3.13 tools/ui_qa/run_headless_tests.py`, `python3.13 tools/ui_qa/input_audit.py`, and `python3.13 tools/art_build/style_check.py` (no art changed, so expect `RESULT failures=0`). Expected: all exit 0.
- [ ] **Step 3:** Grep the diff for non-ASCII characters in new string literals. Expected: none, apart from the existing practice notice text and the emoji in logs.
- [ ] **Step 4: [verify in editor]** Play stages 19 → 20 → camp → 21 for each arena with the `]` dev key. Check:
  - the boss fits the arena without sticking in props
  - the tint and 2x size read well
  - the Slime King adds appear on each phase change
  - the camp shows "Boss beaten! +N gems"
- [ ] **Step 5: [verify in browser]** Run `python3 tools/web/play_in_browser.py --phone`. In a boss phase, check:
  - staying silent never spends a try
  - the typed fallback and the speak button work
  - a near-miss passes on a phoneme score of 75 or more
- [ ] **Step 6: Checkpoint.** Report the results. Commit only if the user asks.

## Optional follow-ups (not in this plan)
- Boss sprites and boss-only moves.
- A boss kind in the journal's kill counts and in spawn TTS.
- A boss health bar with phase pips.
- More bosses after stage 80: add rows to `HordeCurve.BOSSES` and switch the index to the block number.
