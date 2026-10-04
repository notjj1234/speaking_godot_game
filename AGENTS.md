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
- **Speech-match logic differs by platform** (in `enemy.gd:_on_listening_completed`): on **web** it compares a **normalized** (alnum/lowercase) and uses **substring** matching; on **Android** it's an exact `strip_edges().to_lower()` match. Keep this platform split intact.
- On **web**, a challenge never fails on silence — STT keeps restarting and the typed/speak-button fallback (`_show_typed_fallback`, `_show_speak_button`) is the escape hatch. Don't regress this.
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
```

Access these via `/root/NAME` (e.g. `/root/WordTracker`). `STTManager`/`WordTracker` resolve `SheetsManager` lazily because autoload `_ready` may run before other nodes exist.

## Level / travel system

- `LevelManager.load_new_level(level_path, transition_name, offset)` (`00_globals/global_level_manager.gd`) is the single way to change levels: pause → `SceneTransition.fade_out()` → `change_scene_to_file` → fade_in → unpause.
- Player is a **global singleton** (`PlayerManager`) that is **reparented into each level**: the `Level` root node (`levels/scripts/level.gd`, class `Level`) calls `PlayerManager.set_as_parent(self)` on ready and `unparent_player` on free. Most level root scenes are therefore not self-contained player scenes.
- `LevelTransition` (`levels/scripts/level_transition.gd`, an `Area2D`): each marker has `level` (target .tscn), `target_transition_area` (matching name on the destination), `side`, `size`. On load the destination marker `_place_player()` matches `LevelManager.target_transition`, positions the singleton player, and nudges it opposite the travel direction.
- Title screen (`levels/title_screen/title_screen.gd`): "Tutorial" → `playground.tscn` (spawns at center), "Main Game" → `coming_soon.tscn`. Before leaving it calls `_prime_web_mic()` to request the browser mic permission — keep that ordering.

## Saving & persistence

- `SaveManager` persists a single JSON dict to `user://save.sav`. `save_game()`/`load_game()`; load re-enters the saved level then restores player position/HP/inventory.
- `PersistentDataHandler` (`general_nodes/persistent_data_handler/`) marks a node's state for persistence across saves (e.g. already-destroyed enemies) via `SaveManager.add_persistent_value` / `check_persistent_value`, keyed by `scene_file_path + parent name + node name`. Implement `set_value()`/`get_value()` on a handler to persist a node.

## Web export / HTTPS serving

- Export preset **"Web"** → `build/web/` (see `export_presets.cfg`), custom shell `export/web_shell.html`.
- Browser Web Speech API requires a Secure Context, so the build is served locally over **self-signed HTTPS**:
  ```
  python3 build/serve_https.py       # serves build/web/ on https://127.0.0.1:8443 (PORT/HOST env overridable)
  ```
  Certs expected at `build/web-certs/cert.pem` + `key.pem` (self-signed; browser warns, continue anyway).
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
- `.godot/` is gitignored; `export_presets.cfg` and the stray `repomix-output.xml` at repo root are committed.
