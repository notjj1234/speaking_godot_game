# Campfire Camp: talking NPCs in Endless Horde (design)

## Context / why
Treasure chests and friendly NPCs exist (`interactables/treasure_chest/`, `npc/`) but appear in no horde content. In Endless Horde, dying opens the `Bonfire` overlay (`gui/bonfire/bonfire.gd`), which is a static menu: four "Upgrade" buttons, each confirmed by saying one keyword. The user finds it boring and wants it replaced with a walkable Dark Souls–style campfire. Friendly NPCs wander near the fire. You walk up, talk to them, and buy things by actually conversing with them out loud. Loqui Quest is a speaking game, so the conversation should be **both real speaking practice and fun**.

This is project 1 of 2. **Bosses and chest rewards are project 2**, designed later. Bosses don't exist yet: `HordeCurve.is_boss_stage()` always returns false.

## Decisions made with the user
- **Conversation style:** scripted, with natural phrasing. You ask in your own words, and the game recognises the intent from per-option phrase lists. It works offline on every platform. No LLM.
- **Purpose:** a mix of practice and fun. Asking is forgiving. Closing a deal means saying a practice phrase at your level.
- **What's sold:** the 4 stat upgrades (Vitality, Might, Haste, Crit, at today's gem prices) **plus consumables** (apple, potion) to carry into the next run.
- **Approach A:** the camp is a real walkable `Level` scene the horde sends you to on death. It is not an overlay.

## Goals
- Dying in the horde lands you in a camp scene where you walk around normally, with touch controls and voice-move working.
- 3 NPCs wander near an animated campfire. E or the Talk button starts a voice conversation.
- Every purchase that exists today, plus apples and potions, can be bought through conversation on web, Android and iOS.
- Each deal is closed by speaking a phrase at your level (practice), and a good first try earns a discount (fun).
- You leave by interacting with the fire, which resumes the horde at the saved stage. Journal and Title are still reachable.

## Non-goals
- No LLM or free-form AI chat.
- No bosses, no chests in the horde, no new item types (project 2 or later).
- No changes to stat formulas, upgrade costs or horde difficulty, apart from apples and potions now healing (see Consumables).
- No voice command for using a potion mid-fight. Potions are used from the pause-menu inventory (`inventory_slot_ui.gd:52` → `ItemData.use()`).

## Anti-goals (a failure even if it technically works)
- Conversations that dead-end or reject a reasonable phrasing with an error-like message instead of an in-character "say again?".
- Getting locked out of an upgrade because of the mic. With no STT (Windows) or a denied mic, tap choices must still buy everything.
- On web, the practice step failing on silence. That breaks the "challenge never fails on silence" rule. Retries are free and unlimited, and the typed fallback applies.
- Horde voice-move commands ("attack", "move left") firing while you talk to an NPC.

## Constraints (from the code)
- Platform gates: `OS.has_feature("web")` and `OS.get_name()`. STT goes only through `/root/STTManager`, the provider pattern.
- Web mic during a conversation: the touch-controls group's `begin_challenge_mic` / `end_challenge_mic`, as `bonfire.gd:297-307` does, plus `stt.begin_challenge_listen()` on web.
- Level loading goes only through `LevelManager.load_new_level`. The camp root extends `Level` (`levels/scripts/level.gd`) so the global player is moved into it.
- `player.gd:~95` handles a horde death by checking `scene.name == "EndlessHorde"`. In the camp (a different scene name), death goes down the practice path, which is harmless because the camp has no enemies.
- `State.player` is a static var shared by every player state. Nothing in this design should touch it.
- `DialogSystem.show_dialog` sets `PlayerManager.dialog_open`. That flag stops player movement (`state_idle.gd`, `state_walk.gd`, `player.gd:156`) and blocks voice-move on Android and iOS. Conversation mode must set it too.
- `tools/ui_qa/test_ui_screens.gd:194-227` calls `Bonfire.show_rest()` and assumes `show_defeat` forwards to the bonfire. Update it to match the new route.
- UI buttons register through `UiInputRouter` (push_layer / bind_button), following `bonfire.gd:67-81`.
- Logging uses ✅/❌/⚠️ prefixes. The pixel font is ASCII only (`bonfire.gd:113`).

## Approaches considered
| | Approach | Trade-off | Verdict |
|---|---|---|---|
| **A** | Camp is a real `Level` scene loaded on death | Real roaming and NPC use, but the most work, and death becomes a fade plus scene load instead of an instant overlay | **Picked by user** |
| B | A camp diorama drawn inside the paused Bonfire overlay, tap NPCs to talk | Less work, but no walking, so it stays a prettier menu | Rejected |
| C | Turn part of the horde arena into the camp on death, with no scene change | Fights the horde's spawn, stage, pause and arena-swap state. Fragile | Dropped |

## Design

### Flow
1. Horde death (`player.gd` → `ProgressTracker.record_horde_death` → `GameOver.show_defeat()`). `show_defeat` now loads `res://levels/endless_horde/camp/camp.tscn` through `LevelManager.load_new_level` instead of calling `Bonfire.show_rest()`.
2. Camp `_ready` does what `Bonfire.show_rest` does today: `PlayerManager.convert_gems_to_points()`, a full heal (`set_health(horde_max_hp(), horde_max_hp())`) and `SaveManager.save_game()`. It also removes the death invulnerability and hitbox-off state that `player.gd` set on death.
3. The player spawns beside the fire. NPCs wander within a radius around it using the existing `npc_behavior_wander.gd`.
4. **Fire interaction** (Area2D prompt like the NPC's): "Rest and fight on?", with spoken or tapped choices **Fight on** (resume the horde at `ProgressTracker.horde_resume_stage()`, as `bonfire.gd:_on_continue` does), **Journal** and **Title**. This reuses the exit logic in `bonfire.gd:335-361`.
5. **Audio (builder's call, confirmed in review):** the camp is *not* muted. The fire crackles and the NPC talk blips play, and music can stay or switch to a calm track. The Master bus is muted only while STT is actively listening, using the same `_silence_all` / `_restore_audio` pattern as `bonfire.gd:364-379`, so game sound doesn't leak into the mic.

### NPCs (my call; names and art are the builder's)
| NPC | Sells | Notes |
|---|---|---|
| Smith | Might, Crit, equip/unequip sword | Gruff. The practice line is framed as "the smith's oath" |
| Trainer | Vitality, Haste | Upbeat coach |
| Cook | Apple, Potion | Chatty. The practice line is framed as "naming the dish" |

Reuse `npc/npc.tscn`, `npc_resource.gd` and the existing two sprites and portraits. The third NPC's art comes from `tools/art_build/build_npcs.py`.

### Conversation
Each NPC has a **conversation script as data** (a Resource or dictionary per NPC) that a shared controller runs. Steps:

```
GREET    Smith: "Back from the dead? What'll it be?"
ASK      (listen) "I wanna hit harder"      -> intent might
         unclear -> CLARIFY: "Harder how? A sharper blade, or a sharper eye?"
         "nothing"/"bye"                    -> FAREWELL
OFFER    "Sharper blade. 4 gems. Deal?"     (listen yes/no; maxed/broke lines handled here)
PRACTICE "Swear the smith's oath: 'I can run'"   (target from WordTracker)
         first-try match -> 1 gem off (min 1)  "Clean as steel!"
         later match     -> full price
         miss            -> free retry, unlimited; web typed/speak-button fallback
DONE     purchase applied, NPC quip, back to ASK ("Anything else?")
```

- **Intent matching:** for each intent, a phrase list ("hit harder", "stronger", "attack", "might", "damage"…) plus yes/no/bye lists. Matching uses the same logic as `bonfire.gd:244-267`: normalise, substring match, then `PhoneticMatcher.transcript_contains_fuzzy(…, 0.72)`. Put this in a new small shared matcher class so it isn't buried in the controller. Bonfire is left untouched because it becomes unreachable.
- **Practice phrase:** `WordTracker.get_speech_challenge_for_stage(ProgressTracker.horde_resume_stage())`. It is matched like an enemy challenge (substring plus fuzzy). On web it also gets phoneme scoring against `sentence_data/phonemes.json` (≥75 passes), reusing what `enemy.gd` does (`_begin_web_scorer_capture`). The score shows in the NPC's reply.
- **Discount:** given for a first-try match on every platform (my call). That's fair to Android and iOS, which have no phoneme scorer. Prices otherwise come from `PlayerManager.upgrade_cost` / `try_upgrade`.
- **Consumables (user decision):** today `items/apple.tres` and `items/potion.tres` have an empty `effects` list, so using them does nothing.
  - Add an `ItemEffectHeal` (`items/item_effects/item_effect_heal.gd`) to each: **apple heals 4 HP and costs 2 gems; potion heals 10 HP and costs 4 gems.** This also makes apples and potions that enemies drop heal (they enter the inventory via `item_pickup.gd:32`).
  - **Carry cap of 3 each.** The Cook refuses in character once you hold 3 ("Your pack's full of my stew already!").
  - *My call:* the cap limits **purchases only**. Drops still go into the inventory as they do today, so pickup behaviour doesn't change.
  - Buying adds to `PlayerManager.INVENTORY_DATA` the same way a chest does (`treasure_chest.gd:34-44`). Gems are `PlayerManager.bonfire_points`.
- **Small talk:** each NPC has 1–2 optional exchanges that use corpus phrases ("Good morning" → you answer). They give no reward and never block a purchase.
- **UI:** reuse the `DialogSystem` look (portrait and textbox) and add a **conversation mode**. It shows the NPC line, a mic or "listening" indicator and a "heard: …" echo.
- **Speaking is required when STT works.** The user's words were "they have to say what they want". Tappable choice chips appear only when there is no STT (Windows or a denied mic). In that case the practice step is skipped and the price is full. On web, the existing typed/speak-button fallback after repeated misses still applies (`enemy.gd:_show_typed_fallback` pattern), at full price.
- **Movement:** conversation mode sets `PlayerManager.dialog_open`, so the player can't walk and voice-move is blocked. You leave a conversation by saying "bye" / "nothing", pressing Esc, or tapping a small always-visible **Leave** button. Leaving stops STT, disconnects the signals and resumes NPC wandering via `npc.gd:_end_talk`.
- **Mic plumbing:** wire STT signals per step and unwire on exit, like `bonfire.gd:270-287`. On web, also call begin/end_challenge_mic so the touch-controls voice commands are ignored.

### Old Bonfire overlay
It becomes unreachable once `GameOver.show_defeat` routes to the camp. Deleting `gui/bonfire/` and its autoload is a **separate decision to confirm with the user** (deleting files needs approval). Until then it stays in place.

## Left to the builder
Camp layout and props (reuse `props/Sprites/Props.png` campfire frame 33 and tent frame 32, plus a flicker animation, light or particles), the exact phrase lists and NPC lines, third NPC art, the conversation-mode UI layout within the 640×480 `MobileSafeLayout` assumptions, and file and class names.

## Critical files
- New: `levels/endless_horde/camp/camp.tscn` + `camp.gd`, a camp conversation controller, a shared intent matcher, per-NPC conversation data, and a camp fire interactable.
- Modified: `items/apple.tres` + `items/potion.tres` (heal effects), `tools/ui_qa/test_ui_screens.gd` (new death route), `gui/game_over/game_over.gd` (route to camp), `gui/dialog_system/scripts/dialog_system.gd` (conversation mode), `npc/scripts/npc.gd` (start a conversation when the NPC has conversation data, otherwise the linear dialog), and possibly `00_globals/global_player_manager.gd` (consumable purchase helper).
- Reused: `PlayerManager.try_upgrade/upgrade_cost/convert_gems_to_points`, `PhoneticMatcher`, `WordTracker.get_speech_challenge_for_stage`, `npc_behavior_wander.gd`, `UiInputRouter`, `tools/tests/fake_stt_provider.gd`.

## Verification
- Headless tests (Godot at `~/Downloads/Godot.app/Contents/MacOS/Godot`, run on a project copy; runner `tools/ui_qa/run_headless_tests.py`), plus new `tools/tests/test_camp_*.tscn` driven by `fake_stt_provider.gd`:
  - intent matching for each phrase list
  - a full conversation buys each upgrade and consumable with the right gem change, including the first-try discount
  - no-STT tap path buys everything
  - leaving mid-conversation unwires STT
  - death routes to the camp and "Fight on" resumes the saved stage
- Existing tests still pass (`test_save_load`, `test_horde_arenas`, `test_phonetic_matcher`, …).
- Manual web run: `python3 tools/web/play_in_browser.py --phone`. Die in the horde, talk to each NPC by voice, confirm the voice-move commands don't fire mid-conversation, and resume.
