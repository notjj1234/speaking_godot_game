# Campfire Camp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the death-only Bonfire overlay in Endless Horde with a walkable campfire level. Three wandering NPCs sell the stat upgrades, apples and potions through scripted voice conversations that end with a practice phrase.

**Architecture:**
- A new `Camp` level (extends `Level`) is loaded through `LevelManager` on horde death.
- A single `CampConversation` node in the camp runs every conversation as a small step machine. It reads per-NPC lines from a data script (`CampLines`) and matches speech with a shared `IntentMatcher`.
- Purchases go through a pure `CampShop` helper. The existing `DialogSystem` gains a "conversation mode" that shows lines, a heard echo, a listening indicator, tap chips and a Leave button.

**Tech Stack:** Godot 4.7, GDScript, existing autoloads (`STTManager`, `DialogSystem`, `PlayerManager`, `LevelManager`, `WordTracker`, `ProgressTracker`, `PronunciationManager`, `UiInputRouter`, `PlayerHud`).

**Spec:** `docs/superpowers/specs/2026-11-26-campfire-camp-design.md`

## Global Constraints
- **Text:** all on-screen text is ASCII only, because the pixel font has no glyphs for → — … (see `gui/bonfire/bonfire.gd:113`).
- **Logging:** runtime logs use ✅/❌/⚠️ prefixes.
- **Speech-to-text:** STT is used only through `/root/STTManager` (`listen()`, `stop()`, `is_speech_available()`, `begin_challenge_listen()`, signals `listening_completed(result)`, `error(code)`). Platforms are checked with `OS.has_feature("web")`.
- **Buttons:** every tappable button is bound with `UiInputRouter.push_layer` / `bind_button` / `pop_layer`, as in `bonfire.gd:67-81`.
- **Matching:** text is normalised, then checked for a whole-word substring match, then a fuzzy fallback `PhoneticMatcher.transcript_contains_fuzzy(..., 0.72)`. Web phoneme scoring passes at a score of 75 or more.
- **Prices:**
  - Upgrades cost `PlayerManager.upgrade_cost(stat)` (2 + rank).
  - Apple costs 2 gems and heals 4 HP. Potion costs 4 gems and heals 10 HP.
  - The first-try practice discount is 1 gem off, with a minimum price of 1.
  - The carry cap is 3 per consumable and applies to purchases only.
- **Speaking:** speaking is required when `is_speech_available()` is true. Tap chips appear only when there is no speech input (no STT, or `error(-1)`). Taps skip practice and pay full price.
- **Web:** never fail on silence. An empty transcript means listen again. After 3 misses in the practice step, show the HUD typed fallback and speak button (pattern from `enemy.gd:815-856`).
- **Audio:** the Master bus is muted only while actively listening (pattern from `bonfire.gd:364-379`) and is restored on every exit path.
- **Off limits:** don't touch `State.player` (a static var). Leave `gui/bonfire/` and the `Bonfire` autoload in place.
- **No commits** unless the user asks. The "Checkpoint" steps below mean: stop and show the diff.
- **Running a `tools/tests` scene** (always on a throwaway copy, so `--import` and the save file stay untouched):
  ```bash
  run_test() { T=$(mktemp -d); rsync -a --exclude .git --exclude build --exclude graphify-out ./ "$T/p"; \
    sed -i '' "s/config\/name=\"[^\"]*\"/config\/name=\"camptest-$(basename "$T")\"/" "$T/p/project.godot"; \
    G=~/Downloads/Godot.app/Contents/MacOS/Godot; "$G" --headless --path "$T/p" --import >/dev/null 2>&1; \
    "$G" --headless --path "$T/p" "res://tools/tests/$1" --quit-after 6000 2>&1 | grep -E "^(PASS|FAIL|RESULT)|SCRIPT ERROR|Parse Error"; }
  ```
  `tools/ui_qa` scenes run with `python3.13 tools/ui_qa/run_headless_tests.py`.
- **Test file style:** follow `tools/tests/test_challenge_exit.gd`: a `Node2D` scene, `PASS name` / `FAIL name — detail` lines, a final `RESULT passes=N failures=M`, then `get_tree().quit(1 if failures else 0)`. STT is faked by swapping `STTManager.provider` for `preload("res://tools/tests/fake_stt_provider.gd").new()` and restoring it afterwards.

## Review Focus
1. **A late STT result after leaving.** `listening_completed` firing after the player left must not buy anything or reopen the dialog. (Test in Task 4.)
2. **Silence on web.** An empty or whitespace transcript in any step re-listens and never advances, fails or charges. (Test in Task 4.)
3. **Mic denied mid-conversation.** `error(-1)` switches the conversation to tap chips, and buying still works. (Test in Task 4.)
4. **A full inventory when buying an apple.** `add_item` returns false: refund, refuse in character, keep the gems. (Test in Task 2.)
5. **`show_defeat` called twice, or during a load.** Only one camp load happens. (Test in Task 6.)

---

### Task 1: Shared intent matcher

**Files:**
- Create: `speech_to_text/intent_matcher.gd`
- Test: `tools/tests/test_intent_matcher.gd` + `.tscn`

**Interfaces:**
- Produces: `class_name IntentMatcher extends RefCounted`, with all functions static:
  - `normalize(text: String) -> String`: identical behaviour to `bonfire.gd:258-267` (lowercase, keep `a-z0-9`, collapse whitespace).
  - `contains_phrase(transcript: String, phrase: String) -> bool`: both sides normalised. True on a whole-word match (`" %s " % t` contains `" %s " % p`), otherwise `PhoneticMatcher.transcript_contains_fuzzy(t, p, 0.72)`. Empty phrase or transcript returns false.
  - `best_intent(transcript: String, intents: Dictionary) -> String`: `intents` is `{intent_id: Array[String] phrases}`.
    - Pass 1: of all whole-word hits, return the intent whose matched phrase is longest.
    - Pass 2: if there are no exact hits, return the first intent in dictionary order with a fuzzy hit.
    - Otherwise return `""`.

- [ ] **Step 1: Write the failing test** `test_intent_matcher.gd`. Use `I := {"might": ["hit harder", "stronger", "attack", "might"], "vitality": ["tougher", "more health", "hp", "vitality"], "bye": ["bye", "nothing", "no thanks"]}`:
  - `best_intent("I wanna hit harder", I) == "might"`
  - `best_intent("make me tougher please", I) == "vitality"`
  - `best_intent("nothing thanks", I) == "bye"`
  - `best_intent("I am happy", I) == ""`. The whole-word rule stops `hp` matching inside `happy`.
  - `best_intent("", I) == ""`
  - `best_intent("make me stronga", I) == "might"` (fuzzy)
  - `contains_phrase("Good  Morning!", "good morning") == true`
  - `contains_phrase("i can run", "i can swim") == false`
  - `normalize("Hello, World!!") == "hello world"`
- [ ] **Step 2: Run** `run_test test_intent_matcher.tscn`. Expected: a parse error or FAIL (the class doesn't exist yet).
- [ ] **Step 3: Implement** `speech_to_text/intent_matcher.gd` per the Interfaces block.
- [ ] **Step 4: Run** `run_test test_intent_matcher.tscn`. Expected: every line PASS and `RESULT ... failures=0`.
- [ ] **Step 5: Checkpoint.**

---

### Task 2: Shop logic, heal effects, PlayerManager helpers

**Files:**
- Create: `npc/conversation/camp_shop.gd`
- Modify: `00_globals/global_player_manager.gd` (`try_upgrade` at ~162, add `item_count`)
- Modify: `items/apple.tres`, `items/potion.tres` (add an `ItemEffectHeal` sub-resource to `effects`)
- Test: `tools/tests/test_camp_shop.gd` + `.tscn`

**Interfaces:**
- Produces in `PlayerManager`:
  - `try_upgrade(stat: String, discount: int = 0) -> String`. Same as today, except `cost = maxi(2 + rank - discount, 1)`. Existing callers are unchanged.
  - `item_count(item_path: String) -> int`: sums `quantity` of `INVENTORY_DATA.slots` whose `item_data.resource_path == item_path`.
- Produces `class_name CampShop extends RefCounted`, with all functions static:
  - Constants: `ITEM_PATHS := {"apple": "res://items/apple.tres", "potion": "res://items/potion.tres"}`, `ITEM_PRICES := {"apple": 2, "potion": 4}`, `CARRY_CAP := 3`, `DISCOUNT := 1`, `STATS := ["vitality", "might", "haste", "crit"]`.
  - `price(offer_id: String) -> int`. A stat returns `PlayerManager.upgrade_cost(stat)`, an item returns `ITEM_PRICES`, `"sword"` returns 0.
  - `discounted_price(offer_id: String) -> int` returns `maxi(price(offer_id) - DISCOUNT, 1)`.
  - `refusal(offer_id: String) -> String` returns one of `""`, `"maxed"`, `"broke"`, `"full"`, `"no_sword"`. It checks, in order:
    - maxed: haste/crit rank ≥ `HASTE_MAX`/`CRIT_MAX`
    - no_sword: `"sword"` and `not PlayerManager.has_sword()`
    - full: item count ≥ `CARRY_CAP`
    - broke: `bonfire_points < price` at full price
  - `buy(offer_id: String, discounted: bool) -> bool`:
    - Stats call `try_upgrade(stat, DISCOUNT if discounted else 0)`.
    - Items deduct points, then `INVENTORY_DATA.add_item(load(path))`. If that returns false, refund and return false. If it succeeds, call `SaveManager.save_game()`.
    - `"sword"` calls `toggle_sword()`.
    - Returns true on success.

- [ ] **Step 1: Write the failing test** `test_camp_shop.gd`. Set `bonfire_points = 20`, all ranks 0, and clear apple/potion slots. Assert:
  - `CampShop.price("might") == 2` and `CampShop.discounted_price("might") == 1`
  - `CampShop.buy("might", true)` → `might_rank == 1` and `bonfire_points == 19`
  - `CampShop.price("might") == 3` (the rank went up)
  - three `buy("apple", false)` calls → `item_count(apple) == 3` and `bonfire_points == 13`
  - `refusal("apple") == "full"`. A drop added via `INVENTORY_DATA.add_item` still pushes the count to 4 (the cap is purchases only).
  - `price("potion") == 4`
  - `haste_rank = 5` → `refusal("haste") == "maxed"`
  - `bonfire_points = 1` → `refusal("vitality") == "broke"`
  - Inventory full: fill every slot with distinct dummy `ItemData` and set `bonfire_points = 10`. Then `buy("potion", false) == false`, `bonfire_points == 10`, and `refusal` is unchanged. (Review Focus 4.)
  - Heal: `set_health(10, 20)`, then `load("res://items/apple.tres").use() == true` and `PlayerManager.player.hp == 14`. Potion from 5/20 gives 15.
  - Restore the saved inventory, points and ranks at the end.
- [ ] **Step 2: Run** `run_test test_camp_shop.tscn`. Expected: FAIL or a parse error.
- [ ] **Step 3: Add the heal effects.** In `items/apple.tres` and `items/potion.tres`, add `[sub_resource type="Resource"]` using `res://items/item_effects/item_effect_heal.gd` with `heal_amount = 4` / `10`, and set `effects = [SubResource(...)]`. Leave `audio` null unless an existing heal or pickup sound is already used elsewhere. Check the uid with `ResourceUID`, not by comparing text (see memory note).
- [ ] **Step 4: Implement** the `PlayerManager` changes and `camp_shop.gd` per Interfaces.
- [ ] **Step 5: Run** `run_test test_camp_shop.tscn` → all PASS. Also run `run_test test_save_load.tscn` → still `failures=0`.
- [ ] **Step 6: Checkpoint.**

---

### Task 3: DialogSystem conversation mode

**Files:**
- Modify: `gui/dialog_system/scripts/dialog_system.gd`
- Test: `tools/ui_qa/test_camp_dialog.gd` + `.tscn`. Reuse the `press()` / `frames()` helpers pattern from `tools/ui_qa/test_ui_screens.gd:12-38`.

**Interfaces:**
- Produces, on `DialogSystem`:
  - `show_conversation(speaker: String, portrait: Texture, portrait_hframes: int, on_leave: Callable) -> void`. Opens like `show_dialog`: sets `is_open`, `PlayerManager.dialog_open = true`, freezes enemies, pushes the router layer. It sets `_conversation_mode = true`, does **not** bind the bar to `_advance`, shows the Leave button bound via the router to `close()`, and stores `on_leave` as `_on_finished`.
  - `set_conversation_line(text: String) -> void`
  - `set_heard(text: String) -> void`. Shows `Heard: "<text>"`, and an empty string hides it.
  - `set_listening(on: bool) -> void`. Shows or hides a `Listening...` label.
  - `set_choices(choices: Array, on_choice: Callable) -> void`. `choices` is an Array of `{"id": String, "label": String}`. It rebuilds one Button per choice, router-bound to `on_choice.call(id)`, and an empty array hides the row.
  - `is_conversation() -> bool`
  - `close()` (existing) also clears conversation mode, choices, heard and listening, and hides Leave.
- The new controls (heard label, listening label, choice row, Leave button) are built in code in `_ready`, under `ContentColumn`. `.tscn` editing isn't needed. They stay inside the 640×480 `MobileSafeLayout` design space.
- `_input` in conversation mode: `ui_accept` / `interact` do nothing. `ui_cancel` or `pause` calls `close()` and `set_input_as_handled()`. `PauseMenu._unhandled_input` already ignores `pause` while `DialogSystem.is_open` (`pause_menu.gd:102`).

- [ ] **Step 1: Write the failing test** `test_camp_dialog.gd`:
  - After `show_conversation("Smith", null, 1, cb)`: `DialogSystem.is_open == true`, `PlayerManager.dialog_open == true`, `DialogSystem.is_conversation() == true`.
  - Sending an `interact` action event leaves `is_open == true`. In linear mode it would have closed.
  - `set_choices([{"id":"yes","label":"Yes"},{"id":"no","label":"No"}], f)`, then `press()` on the first chip calls `f` with `"yes"` exactly once (one press, one action).
  - `press()` on the Leave button: `is_open == false`, `dialog_open == false`, `cb` called once, and `UiInputRouter.active_layer() == 0`.
  - Sending a `ui_cancel` event during a second conversation closes it and calls its `on_leave` once.
  - Existing linear `show_dialog` still advances on `interact` (a regression guard).
- [ ] **Step 2: Run** `python3.13 tools/ui_qa/run_headless_tests.py`. Expected: FAIL lines for `test_camp_dialog`.
- [ ] **Step 3: Implement** per Interfaces.
- [ ] **Step 4: Run** `python3.13 tools/ui_qa/run_headless_tests.py`. Expected: every scene ends with RESULT and the runner exits 0 (`test_ui_screens` `_dialog` included).
- [ ] **Step 5: Checkpoint.**

---

### Task 4: Conversation data and controller

**Files:**
- Create: `npc/conversation/camp_lines.gd`
- Create: `npc/conversation/camp_conversation.gd`
- Test: `tools/tests/test_camp_conversation.gd` + `.tscn`

**Interfaces:**
- Consumes: `IntentMatcher` (Task 1), `CampShop` (Task 2), the `DialogSystem` conversation-mode API (Task 3).
- Produces `class_name CampLines extends RefCounted`:
  - `const YES := ["yes", "yeah", "yep", "sure", "deal", "okay", "ok", "of course"]`
  - `const NO := ["no", "nope", "not now", "nah", "never mind"]`
  - `const BYE := ["bye", "goodbye", "nothing", "no thanks", "see you", "im done", "leave"]`
  - `const NPCS: Dictionary` keyed `"smith"`, `"trainer"`, `"cook"`, `"fire"`.
  - `static func npc(id: String) -> Dictionary`
  - Every entry has the keys below; the builder writes all copy except the smith sample:
    ```gdscript
    "smith": {
        "name": "Smith",
        "greet": ["Back from the dead? What'll it be?"],
        "anything_else": "Anything else?",
        "clarify": ["Harder how? A sharper blade, or a sharper eye?"],
        "farewell": "Now get out there.",
        "practice_intro": "Swear the smith's oath: '%s'",
        "praise_first": "Clean as steel! One gem off.",
        "praise": "Good enough. Done.",
        "retry": "Again. Like you mean it.",
        "refuse": {"broke": "Come back with more gems.", "maxed": "Can't sharpen that any further.",
                   "full": "", "no_sword": "You don't even have a sword."},
        "offers": {
            "might": {"label": "Might", "offer": "Sharper blade. %d gems. Deal?", "done": "There. Swing it.",
                      "phrases": ["hit harder", "stronger", "more damage", "attack", "might", "sharper blade"]},
            "crit": {...}, "sword": {...},
        },
        "small_talk": [{"expect": ["good morning", "hello", "hi"], "reply": "Morning. Fire's warm."}],
    }
    ```
  - `"fire"` has `"offers"` `fight` / `journal` / `title`, each with `"action": true`. Action offers skip OFFER and PRACTICE.
  - The cook's `refuse.full` copy is "Your pack's full of my stew already!".
- Produces `class_name CampConversation extends Node` (it adds itself to group `"camp_conversation"` in `_ready`):
  - `enum Step { IDLE, ASK, OFFER, PRACTICE }`
  - Signals: `line_changed(text: String)`, `purchase_made(offer_id: String, paid: int)`, `action_chosen(action_id: String)`, `ended`.
  - `start(npc_id: String, portrait: Texture, portrait_hframes: int, on_end: Callable) -> void`
  - `submit_transcript(text: String) -> void`. This is the single entry for STT results, typed fallback and tests.
  - `choose(choice_id: String) -> void`. The tap-chip entry point.
  - `leave() -> void`
  - `is_active() -> bool`, `step() -> int`, `current_line() -> String`, `voice_mode() -> bool`
- **Step rules:**
  - **Start:** if `STTManager.is_speech_available()`, use voice mode. Otherwise use tap mode.
  - **ASK:**
    1. `best_intent` over `offers` phrases plus `{"bye": BYE}`.
    2. If an offer matches, go to OFFER, unless it has a non-empty `refusal`, in which case say the refuse line and stay in ASK. `"sword"` and action offers run immediately.
    3. If `bye` matches, say the farewell, then `leave()`.
    4. If a small-talk `expect` matches, say its reply and stay in ASK.
    5. Otherwise say the next clarify line.
    6. An empty transcript re-listens with no line change.
  - **OFFER:**
    - `YES` goes to PRACTICE in voice mode, or straight to buy at full price in tap mode.
    - `NO` goes back to ASK with `anything_else`.
    - Unclear repeats the offer line.
  - **PRACTICE:**
    - The target is `WordTracker.get_speech_challenge_for_stage(maxi(ProgressTracker.horde_resume_stage(), 1))`.
    - Pass = `IntentMatcher.contains_phrase(transcript, target)`, OR, on web, a phoneme score of 75 or more (capture/score per `enemy.gd:554-607` via `PronunciationManager.get_scorer()`). Show the score in the praise line as ` (score N/100)` when one exists.
    - A pass on attempt 1 calls `CampShop.buy(id, true)`. A later pass calls `buy(id, false)`. Either way, emit `purchase_made` and go back to ASK with the `done` line plus `anything_else`.
    - A miss says the retry line and counts the attempt. On web, from the 3rd miss, show `PlayerHud.show_typed_fallback()` + `show_speak_button()` and connect `fallback_submitted → submit_transcript` and `speak_pressed → re-listen`. Disconnect them on step exit and on leave.
  - **Tap mode:** after each line, `DialogSystem.set_choices` lists the step's options:
    - ASK: offers with `"<label> (<price>)"`, plus `Bye`.
    - OFFER: `Yes` / `No`.
    - Practice is skipped.
  - **STT error:** `error(-1)` (or `"-1"`) switches to tap mode and shows chips. Any other error re-listens.
  - **Listening:** connect `listening_completed` / `error` once per conversation and disconnect in `leave()`. Each listen mutes Master (saving the previous mute state), calls `set_listening(true)`, and calls `begin_challenge_listen()` on web or `listen()` otherwise. A result restores audio and calls `set_listening(false)`. On web, `start()` calls the touch-controls group's `begin_challenge_mic()` and `leave()` calls `end_challenge_mic()`.
  - **leave():** idempotent. Stops STT, disconnects everything, restores audio, abandons any scorer capture, calls `DialogSystem.close()` if it's open, then `on_end`, and emits `ended`. `DialogSystem`'s Leave button reaches `leave()` through the `on_leave` callable passed to `show_conversation`. Guard against re-entry.

- [ ] **Step 1: Write the failing test** `test_camp_conversation.gd`. Swap in `FakeStt`, set `bonfire_points = 20` and ranks 0, add a `CampConversation` node, and drive it with `submit_transcript` / `STTManager.listening_completed.emit(...)`. Monkey-patching `WordTracker` is avoided by reading the target back: after entering PRACTICE, the test parses the quoted phrase out of `current_line()`.
  - Voice buy, first try: `start("smith", null, 1, cb)`, then `submit_transcript("I wanna hit harder")` → `step() == Step.OFFER`. Then `"yeah"` → `PRACTICE`, then the exact target → `might_rank == 1`, `bonfire_points == 19`, `purchase_made("might", 1)` emitted, `step() == ASK`.
  - Voice buy, second try: `trainer` "make me tougher", then "yes", a wrong phrase, then the target → `vitality_rank == 1` and full price paid (2).
  - Clarify: `"purple monkey"` in ASK → `step() == ASK`, the line is one of the smith clarify lines, and no gems change.
  - Small talk: `"good morning"` → the reply line, `step() == ASK`.
  - Cook cap: hold 3 apples, then "can I get an apple" → the line equals the cook's `refuse.full` and `step() == ASK`.
  - Fire: `start("fire", ...)` then "fight on" → `action_chosen("fight")` emitted and `is_active() == false`.
  - Silence (Review Focus 2): `submit_transcript("   ")` in ASK, OFFER and PRACTICE each leaves `step()` and `bonfire_points` unchanged, and `FakeStt.listen_calls` goes up.
  - Mic denied (Review Focus 3): `STTManager.error.emit(-1)` → `voice_mode() == false`, and the choice row is visible. `choose("might")`, then `choose("yes")` → `might_rank` +1 at full price, with no practice step.
  - Late result (Review Focus 1): reach OFFER for might, `leave()`, then `STTManager.listening_completed.emit("yes")` → no rank change, `DialogSystem.is_open == false`, and `STTManager.listening_completed` has 0 connections to the controller (`_links_to` helper from `test_challenge_exit.gd:29-35`).
  - Leave: after `leave()`, `cb` was called once, `ended` emitted once, `PlayerManager.dialog_open == false`, and the Master bus mute equals its pre-test value.
  - Restore the provider, points, ranks and inventory.
- [ ] **Step 2: Run** `run_test test_camp_conversation.tscn`. Expected: FAIL or a parse error.
- [ ] **Step 3: Implement** `camp_lines.gd`, with full copy for all four entries and at least 1 small-talk entry per NPC, using ASCII only.
- [ ] **Step 4: Implement** `camp_conversation.gd` per the step rules.
- [ ] **Step 5: Run** `run_test test_camp_conversation.tscn` → all PASS. Re-run `run_test test_intent_matcher.tscn` and `run_test test_camp_shop.tscn` → `failures=0`.
- [ ] **Step 6: Checkpoint.**

---

### Task 5: Camp level, NPCs and fire

**Files:**
- Modify: `npc/scripts/npc_resource.gd` (add `@export var conversation_id: String = ""`)
- Modify: `npc/scripts/npc.gd:92-110` (`player_interact`)
- Create: `npc/00_npcs/camp_smith.tres`, `camp_trainer.tres`, `camp_cook.tres`
- Create: `levels/endless_horde/camp/camp.tscn`, `camp.gd`, `camp_fire.tscn`, `camp_fire.gd`
- Possibly modify: `tools/art_build/build_npcs.py` + new sprite/portrait PNGs for the cook
- Test: `tools/tests/test_camp_scene.gd` + `.tscn`

**Interfaces:**
- Consumes: `CampConversation.start/leave/action_chosen` (Task 4).
- `npc.gd`: in `player_interact`, if `npc_resource.conversation_id != ""` and `get_tree().get_first_node_in_group("camp_conversation")` exists, then `_begin_talk()` and `conv.start(npc_resource.conversation_id, npc_resource.portrait, npc_resource.portrait_hframes, _end_talk)`, and return. Otherwise run the existing linear dialog unchanged.
- `camp_fire.gd` (`extends Node2D`, with a child `InteractArea: Area2D` on the same layer and mask as `npc.tscn`'s InteractArea, plus a `StaticBody2D` so the player can't walk through):
  - On area enter/exit it connects/disconnects `PlayerManager.interact_pressed`, shows a `Rest [E]` prompt and drives the touch Talk prompt, like `npc.gd:76-90, 132-140`.
  - On interact (ignored while `PlayerManager.dialog_open`): `conv.start("fire", <fire portrait texture>, 1, Callable())`.
  - Visual: `props/Sprites/Props.png` frame 33 (16×3 grid), plus a flicker (looping modulate/scale tween or AnimationPlayer) and `CPUParticles2D` embers. A light is optional.
- `camp.gd`: `class_name Camp extends Level`, root node name `"Camp"`.
  - `_ready()`: `super()`, then `PlayerManager.revive_for_horde()`, `PlayerManager.convert_gems_to_points()`, `SaveManager.save_game()`, and connect `$CampConversation.action_chosen` to `_on_fire_action`.
  - `_on_fire_action(action_id: String) -> void`:
    - `"fight"` → `_leave("res://levels/endless_horde/endless_horde.tscn")`
    - `"title"` → `_leave("res://levels/title_screen/title_screen.tscn")`
    - `"journal"` → `ProgressTracker.show_journal()`
  - `_leave(path: String) -> void`: guarded by `_navigating`. Sets `PlayerManager.player_spawned = false`, then `LevelManager.load_new_level(path, "", Vector2.ZERO)`. This mirrors `bonfire.gd:351-361`.
- `camp.tscn` children:
  - `GrassBackground` (`tile_maps/grass_background.tscn`) or a camp tilemap
  - `PlayerSpawn` (`levels/player_spawn.tscn`) about 48 px below the fire
  - `TouchControls` (`touch_controls/Scene/touch_controls.tscn`) and `PauseButton` (`touch_controls/Scene/pause_button.tscn`), as in `endless_horde.tscn`
  - `CampFire` at the centre
  - `CampConversation`
  - 3 `npc.tscn` instances (Smith, Trainer, Cook), each with an `npc_behavior_wander.tscn` child (`wander_range = 2`)
  - Tents from Props.png frame 32 as decoration
  - Boundary walls so the player stays within about 1 screen.
- NPC resources: smith reuses `npc_sprite.png` / `npc_portrait_01.png`, trainer reuses `npc_sprite_02.png` / `npc_portrait_02.png`, and the cook gets new art from `build_npcs.py` (or, if the generator can't easily do a third, `npc_sprite.png` with a `modulate` tint set in the scene). Set `conversation_id` to `"smith"` / `"trainer"` / `"cook"`.

- [ ] **Step 1: Write the failing test** `test_camp_scene.gd`. Set `PlayerManager.bonfire_points = 0`, add 5 gems to the inventory, set HP to 3, then instantiate `camp.tscn` as a child:
  - `bonfire_points == 5`, the gem count is 0, and `PlayerManager.player.hp == PlayerManager.horde_max_hp()`
  - `player.invulnerable` becomes false after 1.4 s (`revive_for_horde` grace)
  - 3 nodes in the scene are `NPC` with non-empty `npc_resource.conversation_id`
  - exactly 1 node is in group `camp_conversation`
  - calling `smith_npc.player_interact()` → `DialogSystem.is_conversation() == true`
  - `conv.leave()` → `smith_npc.do_behavior == true` (wandering resumed)
- [ ] **Step 2: Run** `run_test test_camp_scene.tscn` → FAIL.
- [ ] **Step 3: Implement** `npc_resource.gd` / `npc.gd` changes, `camp_fire`, `camp.gd`, `camp.tscn` and the NPC resources (plus art).
- [ ] **Step 4: Run** `run_test test_camp_scene.tscn` → all PASS. Re-run `python3.13 tools/ui_qa/run_headless_tests.py` → exit 0. The linear NPC dialog in `_dialog` must be unchanged.
- [ ] **Step 5: Checkpoint.**

---

### Task 6: Route horde death to the camp

**Files:**
- Modify: `gui/game_over/game_over.gd:17-20` (`show_defeat`)
- Modify: `tools/ui_qa/test_ui_screens.gd:227` (comment only: `show_defeat` now loads the camp. `_bonfire` keeps testing the still-present overlay directly.)
- Test: `tools/tests/test_camp_flow.gd` + `.tscn`

**Interfaces:**
- `game_over.gd`: `const CAMP_PATH := "res://levels/endless_horde/camp/camp.tscn"`.
  - `show_defeat()`:
    1. If `LevelManager.is_loading` or `_camp_requested`, return.
    2. If `ResourceLoader.exists(CAMP_PATH)`: set `_camp_requested = true` and `PlayerManager.player_spawned = false`, call `LevelManager.load_new_level(CAMP_PATH, "", Vector2.ZERO)`, then reset `_camp_requested = false` on `LevelManager.level_loaded`.
    3. Otherwise fall back to `_open()`.
  - Remove the `Bonfire.show_rest()` forwarding.

- [ ] **Step 1: Write the failing test** `test_camp_flow.gd`. Change to `endless_horde.tscn` and wait for it to load:
  - Calling `GameOver.show_defeat()` twice in the same frame (Review Focus 5) results in exactly one `LevelManager.level_load_started` emission. After `level_loaded`, `get_tree().current_scene.name == "Camp"` and `Bonfire.visible == false`.
  - Find the `CampConversation`, `start("fire", null, 1, Callable())`, `submit_transcript("fight on")` → after `level_loaded`, `current_scene.name == "EndlessHorde"`.
  - The horde scene resumes at `ProgressTracker.horde_resume_stage()` when that is > 0 (set via `ProgressTracker.record_horde_death(3)` before the defeat): `current_scene._stage == 3`, checked after one physics frame.
- [ ] **Step 2: Run** `run_test test_camp_flow.tscn` → FAIL (still routes to the Bonfire).
- [ ] **Step 3: Implement** the `game_over.gd` change and the test comment edit.
- [ ] **Step 4: Run all tests.** Run every `tools/tests` camp scene plus `test_save_load`, `test_horde_arenas` and `test_challenge_exit` with `run_test`, and `python3.13 tools/ui_qa/run_headless_tests.py`. Expected: every scene shows `failures=0` and the runner exits 0.
- [ ] **Step 5: Manual web pass** (report the results; don't claim them): `python3 tools/web/play_in_browser.py --phone`.
  1. Die in the horde and land in the camp.
  2. Buy one item from each NPC by voice.
  3. While talking, say "attack" and "move left" and confirm the player doesn't act.
  4. Deny the mic and buy using chips.
  5. Use the fire to choose "Fight on" and resume at the same stage.
- [ ] **Step 6: Checkpoint.** Then ask the user whether to delete `gui/bonfire/` and its autoload (a separate decision, per the spec).
