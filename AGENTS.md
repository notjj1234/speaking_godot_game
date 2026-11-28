# AGENTS.md

Loqui Quest — a 2D topdown RPG in **Godot 4.7** (Forward Plus) where you fight enemies by speaking. Voice/STT is the core mechanic.

## Running / building

- **No `godot` binary is installed on this Mac** (not in PATH, not in `/Applications`). You cannot run or export the project here. Do not invent a run/lint/test command that doesn't exist.
- Main scene: `res://levels/title_screen/title_screen.tscn` (set in `project.godot`).
- There is no test framework, linter, or formatter. Verification is manual via the Godot editor, which isn't available in this environment.

## Platform & STT architecture (the important part)

Speech-to-text uses a **provider pattern** with a base class, selected at runtime by platform:
- `speech_to_text/stt_provider.gd` — abstract base (`SttProvider`)
- `android_stt_provider.gd` — uses the `SpeechToText` Android singleton/plugin (`addons/plugins/SpeechToText.gdap`)
- `web_stt_provider.gd` — wraps the browser Web Speech API via `JavaScriptBridge`
- `unavailable_stt_provider.gd` — fallback

Selection happens in `speech_to_text/STTManager.gd:_create_provider()`. Keep new STT backends behind this pattern; don't special-case platforms in callers.

Known platform reality (README is partially stale; web is now the primary focus and works):
- **Android**: fully functional STT.
- **Web**: functional via Web Speech API (needs a Secure Context — see below).
- **Windows**: plays but speech challenge does NOT work.
- STT code paths are heavily gated on `OS.has_feature("web")` and `OS.get_name() == "Android"` — mind this when editing shared code.

## State machines (player & enemy)

Player and enemy AI both use a **custom child-node state machine** (not Godot's built-in):
- Player: `player/Scripts/player_state_machine.gd` (`PlayerStateMachine`) + base `state.gd` (`State`); states are `Node`s under the machine, e.g. `state_idle.gd`, `state_walk.gd`, `state_attack.gd`, `state_stun.gd`.
- Enemy: `enemies/scripts/enemy_state_machine.gd` (`EnemyStateMachine`) + `states/enemy_state.gd` (`EnemyState`); states in `enemies/scripts/states/` (`chase`, `idle`, `wander`, `stun`, `destroy`).
- The machine's `process_mode` starts `DISABLED`; `Initialize(entity)` collects child states and flips it on. A state implements `init` / `enter` / `exit` / `process` / `physics` / `handle_input` and returns the next state (or `null`).
- **Footgun**: `State.player` and `State.state_machine` are **`static var`** (shared across all player states). `EnemyState` uses instance `var enemy` / `var state_machine` instead. Don't "normalize" the static to instance casually, and remember edits to it affect all player states at once.
- Add a new behavior by adding a child `Node` + extending `State`/`EnemyState`; the machine picks up children automatically.

## Combat & speech-challenge flow

- Damage uses an Area2D pair: `HitBox` (`general_nodes/hit_box/hit_box.gd`) emits `damaged(hurt_box)`; `HurtBox` (`general_nodes/hurt_box/hurt_box.gd`) carries `damage` and calls `a.take_damage(self)` on overlap.
- On an enemy reaching 0 HP (`enemies/scripts/enemy.gd:_take_damage`): the game **pauses**, a challenge is chosen via `/root/WordTracker.get_random_speech_challenge()`, shown in the PlayerHud, and STT starts. Success → `enemy_destroyed` → `EnemyStateDestroy` runs the destroy animation then `queue_free`.
- **Speech-match logic** (in `enemy.gd:_on_listening_completed`): both platforms accept a normalized **substring** match plus a fuzzy pass (`PhoneticMatcher.transcript_contains_fuzzy`, 0.72 threshold). **Web additionally**: fuzzy-matches live partial transcripts, and runs a phoneme forgiveness pass — the mic clip is recorded during the challenge (`_begin_web_scorer_capture`) and scored against `sentence_data/phonemes.json` phonemes, passing at ≥ 75/100 (the score shows on the success toast). On final fail the enemy heals to full and the HUD shows "Out of tries — the enemy recovers!". Non-horde "death" refills HP with a "Practice — you can't die here!" HUD notice instead of being silent.
- On **web**, a challenge never fails on silence — STT keeps restarting and the Speak button plus **pick-the-word tiles** are the escape hatch. Don't regress this.
- **Typing answers is developer-only** (players on phones/tablets have no keyboard; desktop players move with the keyboard but never type answers): `SettingsManager.dev_mode` (**Ctrl+`** = `dev_toggle` action, `?dev=1` in the web URL, or five taps on the version badge; saved in `settings.cfg [dev]`) sets `PlayerHud.typed_test_input`. Look-alike tiles come from `WordTracker.lookalike_phrases(target, n)` (same length band, no side effects). Players get word tiles instead (`Enemy._offer_word_tiles` → `PlayerHud.show_word_tiles` / `word_tile_picked`): offered when there's no STT, on a mic error, after a missed attempt, or after `tiles_after_sec` (10 s) with nothing heard. The right tile wins (not logged as a spoken word); a wrong one costs a try. Camp's Say-it box offers tiles after `FALLBACK_AFTER_MISSES` (`DialogSystem.set_say_tiles` / `say_tile_picked`); a tile purchase pays full price.
- STT signals are wired/unwired per challenge (`_connect_stt_signals` / `_disconnect_stt_signals`) plus separate `_connect_fallback` / `_connect_speak_button`. Web also toggles the touch-controls challenge mic (`begin_challenge_mic` / `end_challenge_mic`).

## Google Sheets integration

- `google_sheets/sheets_manager.gd:5` has a **placeholder** `const API_URL = "YOUR APP SCRIPT URL"`. Until replaced with a real Apps Script URL, Sheets calls fail.
- The game deliberately falls back to local data when Sheets is unavailable:
  - Sentences: `res://sentence_data/sentences.txt` (each line = one word or sentence; multi-word lines count as sentences).
  - Built-in defaults live in `00_globals/global_word_tracker.gd` (`DEFAULT_WORDS` / `DEFAULT_SENTENCES`).
  - `global_word_tracker.gd` merges Sheets data over the local fallback, so a broken placeholder URL must not break gameplay.
- Testing offline: expect `[INFO] Loaded local fallback` messages; the `[ERROR]` path only means Sheets is unreachable.

## Autoloads (singletons) — registered in `project.godot`

```
STTManager       speech_to_text/STTManager.gd
LevelManager     00_globals/global_level_manager.gd
PlayerHud        gui/player_hud/player_hud.tscn
PlayerManager    00_globals/global_player_manager.gd
SceneTransition  gui/scene_transition/scene_transition.tscn
PauseMenu        gui/pause_menu/pause_menu.tscn
SaveManager      00_globals/global_save_manager.gd
WordTracker      00_globals/global_word_tracker.gd
SheetsManager    google_sheets/sheets_manager.gd
DialogSystem     gui/dialog_system/dialog_system.tscn
SettingsManager  00_globals/global_settings.gd
AppFocusAudio    00_globals/app_focus_audio.gd   (mutes Master while a native app is paused)
```

Access these via `/root/NAME` (e.g. `/root/WordTracker`). `STTManager`/`WordTracker` resolve `SheetsManager` lazily because autoload `_ready` may run before other nodes exist.

## Level / travel system

- `LevelManager.load_new_level(level_path, transition_name, offset)` (`00_globals/global_level_manager.gd`) is the single way to change levels: pause → `SceneTransition.fade_out()` → `change_scene_to_file` → fade_in → unpause.
- Player is a **global singleton** (`PlayerManager`) that is **reparented into each level**: the `Level` root node (`levels/scripts/level.gd`, class `Level`) calls `PlayerManager.set_as_parent(self)` on ready and `unparent_player` on free. Most level root scenes are therefore not self-contained player scenes.
- `LevelTransition` (`levels/scripts/level_transition.gd`, an `Area2D`): each marker has `level` (target .tscn), `target_transition_area` (matching name on the destination), `side`, `size`. On load the destination marker `_place_player()` matches `LevelManager.target_transition`, positions the singleton player, and nudges it opposite the travel direction.
- Title screen (`levels/title_screen/title_screen.gd`): "Tutorial" → Guided Training (`levels/training/training.tscn`, always). "Main Game" → Training on the first launch (until `TrainingState.is_completed()`), otherwise `levels/endless_horde/endless_horde.tscn`. Before leaving it calls `_prime_web_mic()` to request the browser mic permission — keep that ordering. The old tutorial (`playground.tscn`, `tutorial_area/01-03`) is kept but no longer linked.

## Guided Training (the tutorial)

- `levels/training/training.gd` (`extends Level`, scene root **must** be named `Training`: that name makes it a non-horde level, so deaths refill HP, and `TrainingState.in_tutorial()` keys off it). It loads horde arena 1 and runs 12 step-gated lessons through `TrainingCoach` (`training_coach.gd`) shown in the Trainer's `CoachBanner` (`coach_banner.gd`, CanvasLayer 5). Each lesson shows the full bubble (480 wide, font 17), then after `collapse_sec` (4 s) or the first move/attack it shrinks to a top-left pill (46 tall, font 16, ends at y 50 to clear the HUD mic-banner line; under the pause button on portrait phones) with the lesson's `"goal"`, which pops in when it changes; tap the pill or press H (`coach_toggle` action) to reopen it. Tap-to-continue lessons and flash tips never shrink. It hides (`set_suppressed`) while a speech card or dialog is up.
- The open Trainer bubble moves to the bottom (`CoachBanner.set_avoid(GuidePointer.world_target_rect())`, fed every frame by Training and the camp tour) whenever its top spot would cover the lesson's target.
- Mic switch: touch devices use the cluster's Mic button; desktop has no floating button - the HUD's top-right plate is the switch (`PlayerHud.set_stt_plate_clickable`, signal `stt_plate_pressed`). No STT: no switch, plate says "No mic". Touch Interact only shows while something is in reach (`set_talk_prompt(active, label)`: NPC "Talk", chest "Open").
- Portrait phones: `MobileSafeLayout.portrait_arena_height` gives the map all the height above the controls band and `PlayerCamera.portrait_zoom` zooms to fill it (sides cropped, camera follows). Settings "Touch Controls: On" really forces touch UI (`MobileSafeLayout.set_force_touch_ui`).
- Guide arrows: `GuidePointer` (`levels/training/guide_pointer.gd`, CanvasLayer 9, draw-only, never takes taps). A lesson's optional `"point"` Callable (re-read every frame) returns a world `Node2D` / `Vector2` (bobbing gold arrow, or an edge arrow when off screen), a `Control` / screen-layer button (pulsing ring), or null. `TrainingCoach.pointer` follows it per lesson; Training and the camp tour each own one. Hidden under the pause menu; while a challenge pauses the game only rings show.
- DialogSystem layout: a bottom-centred column (`bar_rect_for`: full width minus 24 on phones, at most 600 wide), name / choices / status indented past a framed portrait card that is a square as tall as the text box (64-112). Chips, the portrait frame, the Say-it box and the result toast share `parchment_style()`. `show_toast(text, good)` shows a short result line above the bar.
- Camp purchases and refusals play their cue through `_play_sfx`, which lifts the mic's game-sound mute (SFX bus) for `CUE_LIFT_SEC`, and show a toast ("Bought! -N gems" / "Need N gems - you have M"). The tour gift, boss reward and treasure chests play `purchase` / `victory`.
- Enemy size: `Enemy.body_scale` (export, set per scene: bandit/skeleton/goblin 1.25, orc 1.5, slime/beetle 1.15) scales the root (art + hit boxes) in `_apply_body_scale`; VisionArea is counter-scaled so detection range is unchanged. Bosses use `BOSS_SCALE` instead, their adds come out at the kind's body size, and split children inherit the parent's scale (`body_scale = 1`).
- Camp conversations (`npc/conversation/camp_conversation.gd`) use only the DialogSystem Say-it box, which has its own Listen / Speak / typing tools (`DialogSystem.set_say_tools`, signals `say_listen_pressed` / `say_speak_pressed` / `say_typed_submitted`). Never call the HUD battle card (`show_speech_challenge`) from camp. Listen there stops the mic, reads the phrase aloud, then listens again by itself (`_on_say_listen`, token-guarded).
- DialogSystem emits `opened` / `closed`; PlayerHud hides the optional-mic banner while a dialog or the speech card is up (and the hint fades after `mic_banner_fade_sec`).
- Lesson targets use `Enemy.make_training_target()` (stands still, harmless, real HP). `make_practice_dummy()` never dies — don't use it for lessons.
- The last lesson loads the camp with `TrainingState.tour_mode = true` (talk → buy → Fight). Fight (or pause → "Skip tutorial") marks Training complete and sets `TrainingState.direct_start`, so the horde starts straight at stage 1 with no practice pad.
- Flags live in `settings.cfg [tutorial]` (`completed`, `tips_seen`) via `SettingsManager`, not the save file; Settings → Reset clears them. Saves made inside Training store the horde path, so Load never resumes mid-tutorial.
- One-time reminder tips: `CoachTips.show_once(host, id, text)` (camp after a death, shop affordable, first boss, new arena).
- First run only: `HordeCurve.first_run_ease(stage, runs)` eases stages 1-5 (0.6 → 1.0) and drops the alive cap by 1.

## Saving & persistence

- `SaveManager` persists a single JSON dict to `user://save.sav`. `save_game()`/`load_game()`; load re-enters the saved level then restores player position/HP/inventory.
- `PersistentDataHandler` (`general_nodes/persistent_data_handler/`) marks a node's state for persistence across saves (e.g. already-destroyed enemies) via `SaveManager.add_persistent_value` / `check_persistent_value`, keyed by `scene_file_path + parent name + node name`. Implement `set_value()`/`get_value()` on a handler to persist a node.

## Web export / HTTPS serving

- Export preset **"Web"** → `build/web/` (see `export_presets.cfg`), custom shell `export/web_shell.html`.
- The shell installs a focus guard (`LQ_AUDIO_FOCUS_BEGIN` block, before the engine script): while the page is hidden it suspends every AudioContext, cancels read-aloud speech and disables every `getUserMedia` track (mic/camera); on return it resumes only what was running. Tested by `tools/tests/test_web_audio_visibility.mjs`.
- Browser Web Speech API requires a Secure Context, so the build is served locally over **self-signed HTTPS**:
  ```
  python3 tools/web/play_in_browser.py --phone   # export, then serve for phone testing (preferred)
  python3 build/serve_https.py                   # serve the last export (PORT/HOST env overridable)
  ```
  `tools/web/play_in_browser.py` (no flag) is the desktop path: plain `http://localhost:8060`, no certificate.
- `build/serve_https.py` generates its own certificate in **`build/phone-certs/`** (gitignored) with SANs for
  `localhost`, `127.0.0.1`, `<mac-name>.local` and every current LAN IPv4, regenerating only when the LAN
  changes or it expires. It serves that cert at `/cert.crt` for installing on a phone, self-tests the LAN URL,
  and prints iOS/Android trust steps plus a firewall hint.
- `build/web-certs/cert.pem` + `key.pem` are the old **committed** cert (`CN=localhost`, no SAN). Only used as a
  fallback when `openssl` is unavailable — a phone will reject it.
- `build/web/` is a generated export target (`index.html`, `index.js`, `index.wasm`, `index.pck`).

## Mic-only voice command mode

- `touch_controls/Scripts/touch_controls.gd` gives the player a mic-toggle mode driven entirely by voice: spoken commands `move forward` / `move backward` / `move left` / `move right` / `attack` call `Player.move_with_animation()` / `attack_with_animation()`.
- The per-level challenge mic is separate from the toggle (`begin_challenge_mic` / `end_challenge_mic`); the toggle is ignored while a challenge is active.
- `MobileSafeLayout` (class, RefCounted) is the responsive layout helper — assumes 640×480 design with stretch aspect "expand", not a real device rect.
- Some buttons are hidden per-level by **scene-name string match** (e.g. scene names `"02"`, `"Playground"`) — brittle; be careful when renaming levels.

## Android build specifics

- `android/.build_version` = **4.4.stable**, but `project.godot` / `config/features` say **4.7** — the Android toolchain is older than the main project; mind this if you touch Android build config.
- `addons/plugins/SpeechToText.gdap` (and `android/plugins/SpeechToText.gdap`) use `binary_type="local"` / `binary="SpeechToText-debug.aar"`, but **that `.aar` is NOT in the repo** — only the plugin config and `android/plugins/**/*.java` source are committed. A fresh Android export needs that AAR available before it works.
- `android/plugins/BluetoothPlugin/*.java` and `android/plugins/src/com/example/godotgame/BluetoothPlugin.java` exist but appear **unused** — don't assume they're wired into a build.

## Export plugin & committed artifacts

- `addons/exclude_colored_folders/` is an `EditorExportPlugin` that can skip files in **colored** folders (see `file_customization/folder_colors` in `project.godot`) per `addons/exclude_colored_folders/folder_color_operation/<color>`. All settings default to `NO_OPERATION` (no-op) unless configured — if files mysteriously vanish from a build, check these.
- `build/web/` (the generated export: `index.*`) **and** `build/web-certs/*.pem` **are committed** to git; re-exporting Web overwrites `build/web/`.
- `file_structure.txt` at repo root is a stale **UTF-16 Windows folder snapshot** — not a source of truth (the real layout differs).

## Other quirks

- `00_globals/global_word_tracker.gd:get_device_name()` shells out to `getprop` (Android-only) via `OS.execute` with a graceful fallback to `"Unknown Device"` on other platforms — don't remove the fallback.
- Physics layers and input actions (WASD, attack=`,`, interact=E, Esc=pause) are defined in `project.godot`; use the named actions, don't hardcode keycodes.
- Heavy use of ✅/❌/⚠️ emoji prefixes in runtime `print` logging throughout scripts — match this style when adding logs.
- `.godot/` and `export_presets.cfg` are **gitignored** — a fresh clone has no export presets (recreate the "Web" preset: export path `build/web/index.html`, shell `res://export/web_shell.html`, threads off, include filter `sentence_data/*.txt, sentence_data/*.json`). The stray `repomix-output.xml` at repo root is committed.
