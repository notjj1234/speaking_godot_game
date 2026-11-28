# Plan: Mute UI, background audio, and Endless Horde "Training" tutorial

## Context
Three requests from the user:
1. **Mute UI**: pressing Mute in Settings really mutes, but the UI doesn't show it. Cause: `gui/settings/settings.gd:133-142` toggles the bus but never calls `_sync_controls()`, so the button keeps saying "Mute". (The pause menu re-syncs, `gui/pause_menu/pause_menu.gd:461`, so it already flips the text.)
2. **Audio keeps playing in the background** (browser tab switch / app switch / swipe-away, on web and Android). Nothing pauses audio. Only STT suspends (`speech_to_text/STTManager.gd:62`, `web_stt_provider.gd:157`). On web the game loop freezes while the page is hidden, so GDScript can't react reliably. The browser's AudioContext keeps playing.
3. **New tutorial**: Endless Horde is now the main game. The old tutorial (`levels/playground.tscn` + `levels/tutorial_area/01-03`) teaches bushes, a maze and goblins, and nothing about the horde loop. User's goal: *by the end the player understands everything (what the game is for, every system, how to play) so they're never confused, and the first few stages feel stress-free.*

### Decisions made with the user
- Approach: **Guided Training**, a hands-on, step-gated tutorial in a horde arena led by the camp Trainer, ending in a guided camp tour, then stage 1. Gentler stages on the first run, plus one-time reminder tips.
- First launch: **auto-start, skippable**. A new player's first "Main Game" press goes into Training. "Skip tutorial" sits in the pause menu. Training can be replayed from the title "Tutorial" button.
- Old tutorial: **unlink, keep the files** (playground / 01-03 stay in the repo, unreferenced by the title screen).

## 1. Mute shows as muted (small)
- `gui/settings/settings.gd`: `_on_music_mute_pressed` / `_on_sfx_mute_pressed` call `_sync_controls()` after toggling. The slider handlers unmute when the slider is moved above 0 (same rule as `pause_menu.gd:456`) and re-sync.
- New helper `_apply_mute_look(button, slider, muted)`. When muted: button text "Unmute" plus a red-tinted "pressed" style (`button.modulate` or a theme override), and the slider dimmed (`modulate.a = 0.45`). When not muted: restored. Use it for the music and SFX rows in Settings, and for the music row in `pause_menu.gd:_sync_music_controls`.
- Check `00_globals/global_settings.gd:16` (`music_muted = true` initializer vs. `false` load default). Make the initializer `false` so first-run state matches what the UI shows.

## 2. Silence audio when the game isn't visible
- **Web (main fix)**, in `export/web_shell.html` (before the engine boots): wrap `window.AudioContext`/`webkitAudioContext` so every context created (Godot's mixer, the pronunciation scorer) is tracked. On `visibilitychange` → hidden, and on `pagehide`: `ctx.suspend()` for every context, plus `speechSynthesis.pause()`/`cancel()` for the read-aloud voice. On visible / `pageshow`: `ctx.resume()` (and `speechSynthesis.resume()`). Only resume contexts that were running before the page was hidden.
- **Android / native**: new small autoload `00_globals/app_focus_audio.gd` (registered in `project.godot` after `SettingsManager`). On `NOTIFICATION_APPLICATION_PAUSED` it remembers the Master bus mute state and mutes Master. On `NOTIFICATION_APPLICATION_RESUMED` it restores that state. It never touches the Music/SFX buses, so the user's own mute settings stay intact. Log in the ✅/⚠️ style.
- Leave Windows desktop focus-loss alone (not requested).
- Re-export Web afterwards (`build/web/` is committed).

## 3. Guided Training tutorial (project)

### Files
- New `levels/training/training.tscn` + `training.gd` (`extends Level`). Instances `levels/endless_horde/arenas/arena_01.tscn` the way `horde_waves.gd:_apply_arena` does (ground, spawn point, decor, TopBarrier). Reuse the enemy scenes and helpers (`_open_position`, `_clamp_to_grass`): copy the minimal bits, or extract shared arena helpers into a small `HordeArenaHelpers` static if they'd otherwise be duplicated.
- New `levels/training/training_coach.gd`: an ordered list of lessons. Each lesson has Trainer text (keyboard and touch variants, like `tutorial_dialog.gd:_playground_messages`), an optional setup callable (spawn things, place a marker), and a completion signal/condition. The next lesson unlocks only when the current one is done. Text shows in a Trainer-portrait banner reusing `TutorialDialog`'s styling (bubble + Abaddon font, positioned clear of the pause button). Optionally read aloud via `TTSManager`.
- New `00_globals` flag storage: `SettingsManager` keys `tutorial/completed` and `tutorial/tips_seen` (a Dictionary of one-time tips), saved in its config. `reset_progress()` clears them. (My call: settings, not the save file, so it survives a new run and isn't tied to a save slot.)

### Lessons (the player can't die: Training is a non-horde level, so the existing "Practice — you can't die here!" refill applies)
1. **Why you're here**: you beat enemies by *speaking*, practising pronunciation. Tap/press to continue.
2. **Move**: walk to a glowing marker (painted like `horde_waves.gd:_paint_start_path`).
3. **Attack**: hit a practice slime (`Enemy.make_practice_dummy`) until it falls.
4. **Speak to finish**: the real challenge flow (`enemy.gd:_take_damage` → challenge). The lesson completes on `enemy_destroyed`. On web, the trainer explains the pronunciation score shown on the success toast.
5. **Fallbacks**: explain the typed box and the Speak button (`_show_typed_fallback`, `_show_speak_button`). A second slime lets them try either.
6. **Out of tries**: tell the player that if all tries fail, the enemy heals to full ("Out of tries — the enemy recovers!") and you knock it down again. Told, not forced.
7. **Voice commands**: toggle the mic, then say "move left" / "attack" (`touch_controls.gd`). Completes on the first recognised command. If STT is unavailable (e.g. Windows), it auto-skips with a note.
8. **Gems & pickups**: the slimes drop gems. Walk over them, or they're pulled in when a wave clears. Gems turn into points at camp.
9. **A small wave**: 3 slimes + 1 goblin trickle in, a horde stage in miniature, ending in "Stage clear".
10. **Mini-boss**: a weakened Slime King (`make_boss` with low phase HP) shows the boss HP bar, the 3 phases, and the music getting faster (`MusicManager.set_intensity`).
11. **HUD tour**: hearts/HP, pause menu (save, settings, journal), the voice-only banner. Text, with arrows/highlights.
12. **Camp tour**: load `camp.tscn` with a tour flag (e.g. `Camp.tour_mode`, plus a small gift of points). Coach steps: talk to an NPC → buy one upgrade → see the Trainer's practice → walk to the bonfire. The bonfire action in tour mode marks `tutorial/completed` and goes to the horde **directly at stage 1** (calls `ProgressTracker.record_run_started()`, skipping the practice pad).

### Wiring
- `levels/title_screen/title_screen.gd`: `PLAYGROUND_PATH` → `TRAINING_PATH`. "Tutorial" always opens Training. `_on_game_pressed`: if `tutorial/completed` is false, open Training, otherwise the horde. Keep `_prime_web_mic()` before leaving. `_friendly_place_name` gets "Training".
- `gui/pause_menu/pause_menu.gd`: a "Skip tutorial" button, shown only while in Training or a camp tour. It marks the tutorial completed and calls `LevelManager.load_new_level(ENDLESS_HORDE_PATH…)`.
- Saving inside Training is disabled (or saves as "go to the horde"), so Load never resumes mid-tutorial.
- Music: Training uses `&"tutorial"`, and the mini-boss uses `&"boss_slime"`.

### Stress-free first run + reminders
- `horde_curve.gd`: new `first_run_ease(stage) -> float`, which is 1.0 except on the player's first run (`ProgressTracker.lifetime().runs_started <= 1`) for stages 1-5 (e.g. 0.6 → 1.0 ramp). `horde_waves.gd:_spawn_one_enemy` multiplies HP/damage/speed by it and lowers `alive_cap` by 1 during those stages.
- One-time tips (shown with the same coach banner, recorded in `tutorial/tips_seen`): first death → camp ("you keep your gems as points; spend them here"), first new arena, first real boss (stage 20), first time at the shop with enough points.

### Tests (follow `tools/tests/test_challenge_exit.gd` style: PASS/FAIL lines, `RESULT`, quit code; fake STT via `tools/tests/fake_stt_provider.gd`)
- `test_training_flow.gd`: lessons advance only on their conditions. Fake STT finishes the speech lesson. Skip marks completion. Finishing the tour lands at horde stage 1.
- `test_first_run_ease.gd`: `first_run_ease` values; no easing after the first run.
- `test_settings_mute_ui.gd`: toggling updates the button text and slider dimming in both Settings and the pause menu.
- `test_app_focus_audio.gd`: PAUSED mutes Master, RESUMED restores the prior state (including the case where Master was already muted).
- Update existing tests that hard-code the title → playground route, if any (grep `playground` under `tools/tests`).

## Verification
- Run the new and existing scene tests headless if a Godot 4.7 binary is available (`godot --headless --path . res://tools/tests/<test>.tscn`); otherwise the user runs them in the editor and checks the `RESULT passes=N failures=0` lines.
- Manual: Settings and pause menu: press Mute (button shows "Unmute", red, slider dimmed), move the slider (unmutes).
- Web (`python tools/web/play_in_browser.py --phone`): start music, switch tab or app and swipe away on a phone (silent), come back (music resumes, mic challenge still works).
- Android build: home button (silent), return (sound restored, user mute settings unchanged).
- Fresh profile (Settings → Reset): Main Game → Training auto-starts, every lesson completes, camp tour → stage 1 is noticeably gentler; second Main Game press goes straight to the horde; Tutorial button replays Training; pause → Skip tutorial works.

## After approval
Save this design to `docs/superpowers/specs/2026-11-28-mute-audio-training-design.md`, then write the step-by-step implementation plan (writing-plans). Build order: 1 → 2 → 3, since the first two are small, independent wins.
