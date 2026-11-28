# Feedback Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every interaction gives clear feedback. Camp options are tapped, then spoken. Generated
sounds mark taps and speech results. Boss phase passes are obvious. Slime King minions get their own
look and chase the player.

**Architecture:**
- A `Sfx` autoload plays offline-generated WAVs, hooked at central points (`UiInputRouter`,
  `PlayerHud`, `DialogSystem`, `CampConversation`, `Enemy`, horde).
- `CampConversation` gains a pending-choice step; `DialogSystem` renders it as a Say-it box.
- `EnemyHealthBar` learns phase pips.
- Split children take an optional sheet and a runtime Chase state from the boss profile.

**Tech Stack:** Godot 4.7.1 GDScript; Python 3.13 stdlib (sound script); pixrig and Pillow (the
existing art script).

**Spec:** `docs/superpowers/specs/2026-11-27-feedback-pass-design.md`

## Global Constraints

- On-screen text ASCII only. Logs use ✅/❌/⚠️ prefixes. Access autoloads via the name or `/root/NAME`.
- Every button goes through `UiInputRouter.bind_button`. One press is one action and one click.
- Don't touch `State.player`. No new dependencies. Don't commit unless asked.
- The goblin and slime art, and the base sheets, stay byte-identical. pixrig defaults stay unchanged.
- Web challenges and the Say-it box never fail on silence.
- Never weaken, skip or delete tests. Intended behaviour changes update their assertion and say so in
  the ledger.
- Test recipe: `bash $SCRATCH/run_test.sh <scene>.tscn` (a fresh rsync copy each run). Godot is at
  `~/Downloads/Godot.app/Contents/MacOS/Godot`.

## Review Focus

1. **Tap, then switch chip:** tapping B while A's Say-it box is open retargets the box to B. Speaking
   A's phrase then must not buy A.
2. **Leave or Esc with the box open:** this closes the conversation, and no stale pending choice
   survives into the next `start()`.
3. **A late STT result after Cancel:** it is treated as free speech, not as the cancelled choice.
4. **The mic fails mid-box** (error streak leads to tap mode): the box hides and chips act on tap.
5. **One router press gives exactly one `click`,** including keyboard/Esc paths that call handlers
   directly. Those paths play no click, which is acceptable.

Tests for 1 to 4 live in Task 3. Test 5 lives in Task 1.

---

### Task 1: Generated sounds and the Sfx autoload

**Files:**
- Create: `tools/audio_build/build_sfx.py`, `audio/sfx/*.wav` (generated), `audio/sfx_player.gd`
- Modify: `project.godot` (autoload `Sfx="*res://audio/sfx_player.gd"` after UiInputRouter),
  `default_bus_layout.tres` (bus `SFX`, send `Master`), `00_globals/ui_input_router.gd:261` (play
  click where `region.handler.call()` runs)
- Test: `tools/tests/test_sfx.gd` + `.tscn`

**Interfaces:**
- Produces:
  - `Sfx.CUES: PackedStringArray`, which equals
    `["click","accept","correct","wrong","error","listen","purchase","phase","victory"]`
  - `Sfx.play(cue: StringName) -> void`
  - `Sfx.last_cue: StringName`
  - `Sfx.count(cue: StringName) -> int`
  - `Sfx.reset_counts() -> void`

- [ ] **Step 1:** Write `test_sfx.gd`. Cases:
  - Every cue in `Sfx.CUES` has `res://audio/sfx/<cue>.wav` loadable as `AudioStreamWAV`, and is
    shorter than 0.6 s except `victory`, which must be under 1.2 s.
  - `play("correct")` sets `last_cue == "correct"` and `count("correct") == 1`.
  - `play("nope")` does not crash and does not change `last_cue`.
  - The bus `SFX` exists.
  - Router check: build a Button bound via `UiInputRouter.bind_button`, then drive one press through
    `tools/ui_qa/pointer_driver.gd` (same as `test_input_router`). Expect `count("click") == 1` and
    the handler called once.
- [ ] **Step 2:** Run it. Expected: FAIL (`Sfx` is not declared).
- [ ] **Step 3:** Write `build_sfx.py`.
  - stdlib only: `wave`, `struct`, `math`, `random.Random(7)`. 22050 Hz, 16-bit mono.
  - Helpers: `tone(freq, dur, wave="square"|"triangle", vol)` with a 4 ms attack and an exponential
    decay; `noise(dur, vol)`; `seq(*parts)`.
  - Write each cue to `audio/sfx/<cue>.wav`:

  | Cue | Recipe |
  |---|---|
  | click | 1.2 kHz, 25 ms |
  | accept | 660 Hz then 990 Hz |
  | correct | C6, E6, G6 arpeggio |
  | wrong | 330 Hz then 220 Hz |
  | error | two 110 Hz buzzes with noise |
  | listen | soft 1.6 kHz triangle ping |
  | purchase | B5, E6 chime |
  | phase | noise thump, then a rising chord |
  | victory | 4-note fanfare |

  Peak at most -3 dBFS. Run it. Then run the Godot `--import` on a copy, through the run_test recipe.
- [ ] **Step 4:** Write `sfx_player.gd`.
  - `extends Node`, process mode always.
  - A pool of 6 `AudioStreamPlayer` on bus `SFX`. Preload streams from `CUES`.
  - Unknown cue: `print("⚠️ Sfx: unknown cue %s")`.
  - Add the autoload and the bus. Add the click in the router.
- [ ] **Step 5:** Run `test_sfx.tscn`, `test_input_router.tscn` (ui_qa) and
  `python3.13 tools/ui_qa/input_audit.py`. Expected: all PASS / RESULT failures=0.

### Task 2: Battle challenge cues

**Files:**
- Modify: `gui/player_hud/player_hud.gd`
  - `show_feedback` plays `correct` / `wrong`
  - `show_enemy_recovered` plays `error`
  - `set_stt_state` plays `listen` only on a transition into `STT_LISTENING`
- Modify: `enemies/scripts/enemy.gd`: play `error` once when the STT error streak reaches
  `STT_ERRORS_BEFORE_TYPED_FALLBACK`
- Test: `tools/tests/test_boss_fight.gd` (extend)

**Interfaces:** Consumes `Sfx.count`, `Sfx.reset_counts`, `Sfx.last_cue` from Task 1.

- [ ] **Step 1:** In `test_boss_fight`, around the existing pass/fail paths, assert:
  - after a failed attempt, `Sfx.count("wrong") == 1`
  - after 3 fails (enemy recovers), `count("error") >= 1`
  - after a pass, `count("correct") == 1`
  - the challenge start shows a listen ping: `count("listen") >= 1`
  - repeated `set_stt_state(LISTENING)` calls don't add pings
- [ ] **Step 2:** Run it. Expected: FAIL on the new checks.
- [ ] **Step 3:** Add the four hooks.
- [ ] **Step 4:** Run `test_boss_fight.tscn`, `test_challenge_exit.tscn`, `test_hud_layout.tscn` and
  `test_voice_only_fail_open.tscn`. Expected: green. The pre-existing hud F29 failure stays as
  before and is reported.

### Task 3: Tap-then-say camp options

**Files:**
- Modify: `gui/dialog_system/scripts/dialog_system.gd` (Say-it box, built in code in
  `_build_conversation_controls`)
- Modify: `npc/conversation/camp_conversation.gd`
- Test: `tools/tests/test_camp_conversation.gd` (extend), `tools/ui_qa/test_camp_dialog.gd` (box
  layout fits the 640x480 design)

**Interfaces:**
- Consumes: `Sfx.play`.
- Produces:
  - In `DialogSystem`: `show_say_box(letter: String, phrase: String) -> void`, `hide_say_box()`,
    `set_say_feedback(text: String)`, `is_say_box_open() -> bool`, `say_phrase() -> String`, and
    `say_box: PanelContainer`.
  - In `CampConversation`: `pending_choice() -> String`.
  - Each entry from `_choices()` is `{"id", "label", "say"}`, and labels are prefixed with
    `"A  "`, `"B  "`, ...

- [ ] **Step 1:** Add `_test_tap_then_say()` and friends to `test_camp_conversation`. Assertions:
  - Voice mode at ASK: `DialogSystem.choice_row.visible`. The first chip text begins with `"A  "`,
    and the last chip is `"D  Bye"` for smith (3 offers plus bye).
  - `conv.choose("might")` in voice mode: the step is still ASK, `pending_choice() == "might"`,
    `DialogSystem.is_say_box_open()`, and `say_phrase() == "Might"`.
  - `submit_transcript("banana")`: the box stays open, the feedback is `"Not quite. Try again."`,
    `Sfx.count("wrong")` goes up by 1, and the step is still ASK.
  - `submit_transcript("might")`: the step becomes OFFER, the box is closed, `count("accept")` goes
    up by 1, and `pending_choice() == ""`.
  - In OFFER, `choose("yes")` then `submit_transcript("yes")`: the step becomes PRACTICE.
  - Retarget (RF1): `choose("might")`, `choose("crit")`, `submit_transcript("might")`. The box is
    still open on "Crit" and the step is still ASK.
  - Cancel (RF3): `choose("crit")`, then the box's Cancel handler, then `submit_transcript("crit")`.
    The step becomes OFFER through free speech, and the box is closed.
  - Leave (RF2): `choose("might")`, then `conv.leave()`, then `start("smith")`. Expect
    `pending_choice() == ""` and the box closed.
  - Tap mode (denied mic) `choose("might")`: the step becomes OFFER at once, and no box opens.
  - Error streak (RF4): open the box, emit 3 STT errors. The box is hidden, tap mode is on, and the
    chips are visible.
  - Purchase: `count("purchase")` goes up on buy. A broke refusal plays `error`.

  This changes existing assertions: none. The existing chip checks are for tap mode and still hold.
- [ ] **Step 2:** Run `test_camp_conversation.tscn`. Expected: FAIL on the new checks.
- [ ] **Step 3:** In `DialogSystem`, add the box.
  - It is a `PanelContainer` with a StyleBoxFlat copied from the HUD challenge card. Read
    `player_hud.tscn` `StyleBoxFlat_challenge` for the colours and border.
  - Children: a title Label (`"%s - say it:" % letter`), a phrase Label (font size 20), a status
    Label, and a Cancel button bound on `_input_layer` to `_on_say_cancel`. `_on_say_cancel` emits
    `say_cancelled`.
  - `set_listening` / `set_heard` also update the box's status line while it's open. `set_listening(true)` plays `listen` only on a false-to-true change.
  - `_clear_conversation` hides the box.
  - Add `signal say_cancelled`.
- [ ] **Step 4:** In `CampConversation`:
  - `_say` always sets chips.
  - `choose` branches on `_voice` as the spec describes.
  - `submit_transcript` checks the pending choice first.
    - Match: phrase contains `say`, or any of the offer's `phrases` / YES / NO / BYE for that id, or
      a web score of at least `WEB_SCORE_PASS`.
    - Then dispatch to the old tap path.
  - Connect `DialogSystem.say_cancelled` in `start`, and disconnect it in `leave`.
  - `_switch_to_tap` hides the box and plays `error`.
  - Add `Sfx.play` at purchase (`purchase`), refusal (`error`), practice miss (`wrong`) and practice
    pass (`correct`).
  - Reset `_pending_choice` in `start`, `leave` and `_back_to_ask`.
- [ ] **Step 5:** Run `test_camp_conversation`, `test_camp_flow`, `test_camp_scene`,
  `test_camp_shop`, `test_boss_flow`, ui_qa `test_camp_dialog` and `input_audit.py`. Expected: all
  green.

### Task 4: Clear boss phases

**Files:**
- Modify: `enemies/scripts/enemy_health_bar.gd`, `enemies/scripts/enemy.gd`
  (`_ready`, `_advance_boss_phase`, the challenge title), `gui/player_hud/player_hud.gd`
  (`show_speech_challenge(sentence, title := "")`), `levels/endless_horde/horde_waves.gd`
  (`victory` cue)
- Test: `tools/tests/test_enemy_health_bar.gd`, `tools/tests/test_boss_fight.gd`,
  `tools/tests/test_boss_flow.gd`

**Interfaces:**
- Produces:
  - `EnemyHealthBar.set_phases(left: int, total: int) -> void`
  - `EnemyHealthBar.phases_left() -> int`
  - `get_display_text()` returns `"Phase %d/%d" % [total - left + 1, total]` when total > 0
  - `PlayerHud.challenge_title_label: Label`

- [ ] **Step 1:** Write the tests.
  - Health bar: `set_phases(3, 3)` gives `"Phase 1/3"` and `phases_left() == 3`; `set_phases(2, 3)`
    gives `"Phase 2/3"`.
  - Boss fight: a fresh boss bar reads `"Phase 1/3"`. After the first pass it reads `"Phase 2/3"`,
    `phases_left() == 2`, `Sfx.count("phase") == 1`, and the HUD notice text is
    `"Slime King hit! Phase 2/3"`. The challenge title visible on a boss reads
    `"Slime King - phase 1/3"`. A normal enemy's challenge title is hidden.
  - Boss flow: `Sfx.count("victory") == 1` after the boss dies.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement.
  - Pips: `total` 4x3 rects under the bar at y=`BAR_H + 2`, 2 px apart, centred. Filled pips are gold
    `BORDER_COLOR`; empty ones are `BG_COLOR` with a gold edge.
  - `show_notice` is the existing HUD helper.
- [ ] **Step 4:** Run `test_enemy_health_bar` (its runner), `test_boss_fight`, `test_boss_flow`,
  `test_hud_layout` and `test_challenge_exit`. Expected: green, apart from the pre-existing F29.

### Task 5: Royal minion art

**Files:**
- Modify: `tools/art_build/build_bosses.py` (add `slime_minion()` to `BOSSES`),
  `tools/art_build/style_check.py` (add the `boss_slime_minion` target and `REGION_EXEMPT` entry)
- Create: `enemies/bosses/slime_minion.png` (+ `.import` via the Godot import)

**Interfaces:** Produces `res://enemies/bosses/slime_minion.png`: 1024x128, 16x2 frames of 64 px,
the same frame order as `Slime.png`.

- [ ] **Step 1:** Add the target to `style_check.py`. Run `python3.13 tools/art_build/style_check.py`.
  Expected: FAIL (missing sheet).
- [ ] **Step 2:** Implement `slime_minion()` on a 64-px `Rig`.
  - It reuses the King's palette (`KING_BODY`, `KING_OUT`, `KING_EYE`).
  - Gumdrop dome: floor 55, rx about 13 to 17, top about 31.
  - A gold helmet: a half dome cap plus a nasal stripe, with a 2-px red `GEM` stud. It lifts on hit
    frames.
  - Eyes are 3x2 dark with a yellow pupil pixel. Same idle/walk/hit squash table as the King,
    halved.
  - Run `build_bosses.py`. Check that the King, captain, warlord and bandit sheets are unchanged
    (`shasum` before and after), and that the base sheets pass `shasum -c base_sums.txt`.
- [ ] **Step 3:** Run `style_check.py`. Expected: RESULT failures=0. Make a preview in the scratchpad
  and look at it.

### Task 6: Minions use the sheet and chase

**Files:**
- Modify: `levels/endless_horde/horde_curve.gd` (Slime King row: `"add_sheet"`, `"add_chase": true`)
- Modify: `enemies/scripts/enemy.gd` (`make_boss` stores them; `spawn_split_children` passes them;
  `_ready` swaps the texture; `_apply_split_aggro` builds the Chase state)
- Test: `tools/tests/test_boss_fight.gd`, `tools/tests/test_boss_curve.gd`

**Interfaces:**
- Consumes: the Task 5 sheet.
- Produces: `Enemy.minion_sheet: String` and `Enemy.minion_chase: bool`, both set on children before
  `add_child`.

- [ ] **Step 1:** Write the tests.
  - Curve: the Slime King profile has `add_sheet` ending `slime_minion.png` and `add_chase == true`;
    other bosses have neither.
  - Fight: after the King's first phase pass, 2 adds exist. Each one's
    `sprite.texture.resource_path` ends with `slime_minion.png`, it has hframes 16, and after 1.5 s
    its `state_machine.current_state is EnemyStateChase`. After 1 s it has moved toward the
    player: its distance to the player drops.
- [ ] **Step 2:** Run them. Expected: FAIL.
- [ ] **Step 3:** Implement.
  - The Chase state is created with `chase_speed = split_chase_speed`, `anim_name = "walk"`,
    `state_aggro_duration = 2.5` and `next_state = null`.
  - Set `enemy`/`state_machine` the way `EnemyStateMachine.Initialize` does for its children (read
    it), then call `init()`.
- [ ] **Step 4:** Run `test_boss_fight`, `test_boss_curve`, `test_boss_flow` and `test_horde_arenas`.
  Expected: green.

### Task 7: Full regression

- [ ] Run every `tools/tests/*.tscn` on fresh copies, plus `python3.13 tools/ui_qa/run_headless_tests.py`,
  `input_audit.py`, `style_check.py` and `shasum -c base_sums.txt`.
  Expected: everything green, except failures that were already failing before (named in the report).
- [ ] Update the spec status line and the ledger. Mark the manual checks [verify in browser]: web
  Say-it box with silence, typed fallback, and the listen ping during scorer capture.
