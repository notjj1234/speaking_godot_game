# Feedback pass: tap-then-say NPC options, game sounds, clear boss phases, royal minion slimes

Date: 2026-11-27. Status: approved by the user in conversation ("good enough, start the process").
Implemented 2026-11-27 (plan `docs/superpowers/plans/2026-11-27-feedback-pass.md`). Builder rulings
are in `.superpowers/sdd/2026-11-27-feedback-pass/progress.md`. Added in review: the listen ping
plays once per prompt (new card, retry, new line, box opened, miss), never on web STT's silent
restarts. Still to verify by hand: [verify in browser] Say-it box with silence and typed fallback,
the ping during the scorer clip; [verify on phone] chip wrapping; [verify in editor] box and pip
looks.

## Intent

Playtesting the boss stages surfaced four problems, all about the player not knowing what happened
or what to do:

1. **NPC talk is a guessing game.** With a working mic the camp option chips are hidden
   (`camp_conversation.gd:_say` shows chips only when `_voice` is false), so the player has to guess
   what to say. The user wants quiz-style labelled options (A, B, C, D) they **tap, then say**:
   "tap first and then have the speech challenge box but designed specifically for this to say, so
   users can tap and then say what they tapped".
2. **No sound feedback.** Only hits, deaths, pickups and the chest make sounds. The user wants sounds
   that say "went through", "didn't go through", right, wrong, error, and so on. The user asked for
   them to be generated.
3. **The boss phase pass is invisible.** On a correct boss answer the bar refills to full
   (`enemy.gd:_advance_boss_phase`, `hp = max_hp`) and only the top wave label changes. The user
   thought they had failed and tried "3 more times", until it died. "I just want it to be clear."
4. **Slime King minions look like ordinary slimes.** The user wants the little slimes the King
   spawns to have "a unique design for them specifically". The original ask also said slimes
   should aggro on that stage. Slimes have no Chase state today, so the minions wander.

Success means a player always sees, and hears, whether an action landed. That covers taps, speech,
purchases and boss phases.

## Goals

- **G1, tap then say.**
  - Camp options (NPCs and the fire, in both the ASK and OFFER steps) are always visible, labelled
    `A`, `B`, `C`, `D`, and so on.
  - Tapping one opens a **Say-it box**: a parchment card like the battle challenge card, showing the
    letter, the phrase to say, and Listening / Heard status. The phrase is the option label, e.g.
    "Potion" or "Fight on".
  - Saying it confirms the choice. A miss keeps the box open with "Not quite. Try again."
  - Cancel (or Esc / Leave) closes the box.
- **G2, generated sounds.**
  - A stdlib-only Python script synthesises retro blips into `audio/sfx/*.wav`.
  - One `Sfx` autoload plays them on a new `SFX` bus.
  - They are wired at a few central points so every interaction is covered.
- **G3, clear boss phases.**
  - The boss's own health bar shows phase pips and `Phase N/M`.
  - A phase pass plays a distinct sound, flashes the boss, and shows a centre notice.
  - The challenge card names the phase.
- **G4, royal minions.**
  - Slime King adds use a new `slime_minion.png` sheet (same frame layout as `Slime.png`),
    built by `build_bosses.py` and gated by `style_check.py`.
  - The minions always chase the player.

## Non-goals

- Tutorial and playground NPCs (`npc.gd`, which shows `show_dialog` lines with no choices). Nothing
  changes there.
- Changing what offers do, prices, or the purchase practice phrase. Buying still ends in the
  existing practice step.
- Music, volume sliders and settings UI. The SFX bus follows Master. A slider is a follow-up.
- New art for the Slime King or for other enemies. Base sheets stay byte-identical.

## Anti-goals (a failure even if it "works")

- Breaking voice-first camp talk. Free speech without tapping keeps working
  (`submit_transcript("fight on")` in `test_boss_flow` and the camp tests must stay green).
- A web challenge that fails on silence, or a Say-it box that does (the existing re-listen rule).
- Sounds that double-fire: one press must give one click (the router's one-press-one-action audit).
- Weakening or deleting tests.

## Constraints

Carried from the project and the user:
- On-screen text ASCII only. Logs use ✅/❌/⚠️. Buttons go through `UiInputRouter`.
- Don't touch the `State.player` static var. No new dependencies; the sound script is stdlib Python.
- Goblin and slime art, and the base sheets, stay unchanged. pixrig defaults stay unchanged.
- No commits unless asked.
- Tests run headless on throwaway copies (scratchpad `run_test.sh`), Godot 4.7.1 at
  `~/Downloads/Godot.app/Contents/MacOS/Godot`.

## Approaches considered

**Tap then say (G1)**
- **A. Say-it box inside `DialogSystem`, driven by `CampConversation` (chosen).** The conversation
  already owns STT wiring, the web scorer and the typed fallback. A tap sets a pending choice, and
  the next transcript is checked against that choice's phrase. The box is a view.
- B. Reuse the HUD battle challenge card. That couples camp to enemy challenge state
  (`WordTracker.speech_challenge_active`, tries, warm-up label) and its pause semantics. Rejected.
- C. Show the letters only and accept "A"/"B" spoken. That is not what the user asked for (tap,
  then say the words), and single letters are poorly recognised by STT. Rejected. Saying the letter
  isn't promised.

**Sounds (G2)**
- **A. Offline generated WAVs plus a tiny autoload (chosen).** Deterministic, reviewable, no runtime
  cost, works on web.
- B. `AudioStreamGenerator` synthesis at runtime. Web audio worklet quirks, and harder to test.
  Rejected.
- C. Downloaded packs. Licensing, and the user asked for generated sounds. Rejected.

**Wiring points (G2)**: central hooks, not per-call-site sprinkling.
- `UiInputRouter` press: click.
- `PlayerHud.show_feedback`: correct or wrong.
- `PlayerHud.show_enemy_recovered`: error.
- `PlayerHud.set_stt_state` entering listening: listen.
- `DialogSystem` Say-it result: accept or wrong; `DialogSystem.set_listening(true)`: listen.
- Purchase and refusal in `CampConversation`.
- `Enemy._advance_boss_phase`: phase.
- Horde boss victory: victory.
- Mic giving up (enemy typed-fallback threshold, camp `_switch_to_tap`): error.

**Boss clarity (G3)**: pips on `EnemyHealthBar` (`set_phases(left, total)`), not a separate
boss bar scene. That is smallest, and it already follows the boss.

**Minion chase (G4)**: give split children a runtime `EnemyStateChase` (`anim_name "walk"`, no
vision area, `next_state` null, so it never leaves chase) when the profile asks for it. Not a new
slime scene, which would duplicate `slime.tscn` and its animations.

## Design

### G1 Say-it box
- `CampConversation._say` always calls `DialogSystem.set_choices(_choices(), choose)`, in both
  voice and tap modes.
  - Labels gain a letter prefix: `"A  Might (3)"`. Letters come from the index, `A` onward.
  - Each choice carries `say`: the phrase to speak. That is the offer label without the price, or
    "Yes" / "No" / the bye label.
- `choose(id)`:
  - **Voice mode:** don't act yet. Set `_pending_choice = id` and call
    `DialogSystem.show_say_box(letter, say_text)`, which keeps listening. A tap on another chip while
    the box is open retargets it.
  - **Tap mode (no STT):** act immediately, as today.
- `submit_transcript(text)` with a pending choice:
  - **Match** (`IntentMatcher.contains_phrase(heard, say)`, or any of that offer's `phrases` /
    YES / NO / BYE lists, or on web a phoneme score >= `WEB_SCORE_PASS`):
    1. play accept
    2. hide the box
    3. clear the pending choice
    4. run the same path the tap ran before (`_pick_offer`, yes/no, farewell)
  - **Miss:** play wrong, set the box feedback to "Not quite. Try again.", and listen again.
    After `FALLBACK_AFTER_MISSES` misses on web, show the existing typed fallback.
  - **Silence:** re-listen. Never fail.
- Without a pending choice, free speech goes through the existing intent matching, unchanged.
- Cancel button in the box: clear the pending choice and hide the box. Leave / Esc close the whole
  conversation, as today.
- Box layout, built in code beside the choice row in `DialogSystem`:
  - a parchment `PanelContainer` (same colours as `StyleBoxFlat_challenge`)
  - title `"B - say it:"`, the phrase in large text
  - a status line ("Listening..." / "Heard: ..." / "Not quite. Try again.")
  - a Cancel button bound through `UiInputRouter` on the dialog layer
- API: `show_say_box(letter: String, phrase: String)`, `hide_say_box()`,
  `set_say_feedback(text: String)`, `is_say_box_open() -> bool`.

### G2 Sounds
- Script: `tools/audio_build/build_sfx.py`. Python stdlib only (`wave`, `math`, `struct`).
  - Output: 16-bit mono 22050 Hz WAVs.
  - Square/triangle tones with short attack and decay envelopes. A deterministic noise seed for
    error.
- Cue names, each under 0.6 s:

| Cue | Sound |
|---|---|
| `click` | short tick |
| `accept` | rising two-note blip ("went through") |
| `correct` | bright three-note arpeggio |
| `wrong` | falling two-note buzz |
| `error` | low double buzz |
| `listen` | soft high ping |
| `purchase` | coin chime |
| `phase` | heavy hit plus rising chord |
| `victory` | short fanfare |

- Autoload: `Sfx="*res://audio/sfx_player.gd"`.
  - `play(cue: StringName)` uses a small pool of `AudioStreamPlayer`s on bus `SFX` with process
    mode always. Unknown cue: ⚠️ log, no crash.
  - `last_cue` and `played` counters, for tests.
  - The `SFX` bus is added to `default_bus_layout.tres`, sending to Master.
- Hooks: listed under Approaches. Click is played in `UiInputRouter` exactly where a bound handler
  is invoked, so one press gives one click.

### G3 Boss clarity
- `EnemyHealthBar.set_phases(left: int, total: int)` draws `total` small pips under the bar
  (filled = left) and switches the text to `"Phase %d/%d"`. The HP number is replaced, and the fill
  still shows HP.
  - `get_display_text()` returns the phase text when phases are set, so tests can read it.
- `Enemy._ready` (boss) calls `set_phases(boss_phases, boss_phases)`.
- `_advance_boss_phase` calls `set_phases(boss_phases - boss_phase, boss_phases)`, plays `phase`, and
  calls `PlayerHud.show_notice("%s hit! Phase %d/%d")`.
  - The flash already exists: `_flash_challenge_success`.
- The challenge card on a boss: `PlayerHud.show_speech_challenge` gets an optional `title` ("Slime
  King - phase 1/3") shown above "Say: ...". Callers that pass nothing are unchanged.
- Horde victory (`_on_stage_cleared`, boss branch) plays `victory`.

### G4 Royal minions
- Art: `build_bosses.py` adds `slime_minion()`.
  - 64 px cells at 1x, 16 x 2, the same frame order as `slime_king` and `Slime.png`.
  - King palette (purple body, dark outline), a small gold helmet with a red gem, and a narrower
    gumdrop.
  - Output: `enemies/bosses/slime_minion.png`.
  - `style_check.py` lists it as `boss_slime_minion` and adds it to `REGION_EXEMPT`, with the same
    reason as the other slimes. All other bars apply.
- Profile: the Slime King row gains `"add_sheet": "res://enemies/bosses/slime_minion.png"` and
  `"add_chase": true`.
- `Enemy.spawn_split_children` passes these to the child (`child._minion_sheet`,
  `child._minion_chase`) before `add_child`.
  - In `_ready` the child swaps `sprite.texture` (same hframes/vframes).
  - In `_apply_split_aggro`, if there is no `Chase` node and `_minion_chase` is set, it builds an
    `EnemyStateChase` (anim `walk`, chase speed from `split_chase_speed`) under the state machine,
    calls `init`, and switches to it.
- The King himself is unchanged (wanders).

## Risks

- **Web mic and cues:** the listen ping plays while the web scorer clip records. Browsers apply echo
  cancellation by default, and the ping is short and quiet. [verify in browser]
- **Readability:** letter-prefixed chips widen the choice row. The `HFlowContainer` wraps, but with
  four chips plus Bye on a phone it may wrap to two rows. [verify on phone]
- **Chase without vision:** minions chase forever. That's intended, and there are only 2 per phase.
- **Sound balance:** volumes are a guess; tune them in the script.

## Calls I made (the user can override)

- **Phrase to say:** the option's own label ("Potion"). Any of the offer's existing phrases also
  counts.
- **Free speech:** saying an option without tapping still works.
- **Tap-only mode:** with no mic, a tap still acts immediately.
- **Boss bar text:** `Phase 2/3` replaces the HP number on the boss bar.
- **SFX volume:** the SFX bus has no settings slider yet.
- **Minion look:** the helmet design is mine; the King keeps wandering.

## Left to the builder

Exact waveforms and volumes, pip size and placement, and Say-it box spacing, within the style of the
existing challenge card.
