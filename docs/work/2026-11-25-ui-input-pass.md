# UI input pass: one press, one action (2026-11-25)

Branch `fix/ui-input-single-dispatch`. The rules this pass sets are in
[`docs/ui-input-rules.md`](../ui-input-rules.md).

## 1. Root cause

With `emulate_touch_from_mouse=true`, one desktop click is delivered as an
emulated `ScreenTouch` **and** a `MouseButton` (`core/input/input.cpp`).
`TouchScreenButton` reacts to the first and `BaseButton` to the second
(`scene/gui/base_button.cpp`). Every twin pair, and every script that handled
both event types, fired more than once. On a real finger the opposite holds:
`Button.pressed` never fires, which is why each screen had grown a workaround.

Reproduced headlessly on the pre-fix tree with real engine input:

| One mouse click on | Pre-fix result |
|---|---|
| Settings Difficulty, Reset | 2 activations each |
| Bonfire Crit, Equip, Continue, Journal | 2 activations each |
| Dialog bar | skipped 2 lines |
| Inventory slot | **used 3 items** |

## 2. How this was verified

The brief said this machine has no Godot binary. It does:
`~/Downloads/Godot.app`, **4.7.1 stable**, the same path
`tools/web/play_in_browser.py` searches first. So the proof is behavioural, not
only static. All runs were on throwaway copies of the project.

| Proof | Result |
|---|---|
| `tools/ui_qa/test_input_router.tscn` (router rules) | 45 / 45 pass |
| `tools/ui_qa/test_ui_screens.tscn` (real screens, real engine input) | 96 / 96 pass |
| Every project script loads | 100 / 100 (pre-fix: 94 / 95, the journal failed) |
| Real levels Playground, 01, 02, 03, EndlessHorde with touch UI forced | 0 unexpected overlaps, 0 undersized live targets, 0 script errors, Pause opens and closes on 5/5 |
| Same five levels at 390x844, 844x390 and 1280x600 windows | same |
| `tools/tests/test_combat_softlock_contracts.py` | pass |
| `grep -rn "_align_touch\|uses_touch_button_twins\|emit_signal(\"pressed\")"` (`.gd`, `.tscn`) | nothing |
| `grep -rn "Touch_" --include=*.tscn gui levels touch_controls` | nothing |

Rerun with `python3.13 tools/ui_qa/run_headless_tests.py`.

Headless means no real browser, no real finger, no pixels on a screen and no
speech backend. Section 8 lists what that leaves open. Engine behaviour cited
from source was read at tag `4.5-stable`; the behaviour tests ran on 4.7.1.

## 3. Evidence table, with the fixed state

| # | Finding in the brief | Fixed state |
|---|---|---|
| E1 | Mic / Interact Buttons under TSB twins | `Touch_Mic` and `Touch_Interact` deleted. Mic and Interact are `IGNORE` / `FOCUS_NONE` labels that the router uses as the hit area |
| E2 | `TouchCrit` / `TouchEquip` on one point | all 8 bonfire twins deleted |
| E3 | `TouchDifficulty` / `TouchReset` on one point | all 8 settings twins deleted |
| E4 | bonfire Continue / Journal / Title overlap 20 px | deleted; Journal and Back to Title now share a row |
| E5 | `button.pressed` and `touch.pressed` on one handler | twins and align code deleted; one `UiInputRouter` binding per button |
| E6 | title twins, Yes/No `_input` hit-test, dimmer not blocking TSBs | all deleted; each confirm card is a router layer |
| E7 | journal `gui_input` + `emit_signal("pressed")` | deleted, with `_try_press_button_at`, `try_tap` and two `ProgressTracker` forwarders |
| E8 | `uses_touch_button_twins()` always true | function deleted |
| E9 | D-pad diagonals | preserved, native `action`, allowlisted; two fingers and one corner thumb both tested |

### Where the brief and the code disagreed

- **Self-test pair 7 (Attack / Interact, 8x6) does not exist.** `Attack` is a
  textured `TouchScreenButton`, and the engine anchors those top-left
  (`touch_screen_button.cpp`: the texture is drawn and hit-tested from the node
  origin). In `RightCluster` Attack spans x 132..212 and Interact ends at x 100,
  a 32 px gap. The pre-fix runtime rects agree (Interact right edge 516, Attack
  left edge 548 in a 640x640 viewport). Centring the Attack texture gives an
  8 px horizontal overlap, which is the likely source of the figure. The tool
  was not bent to match: `--self-test` stays strict, reports 6/7 and exits 1.
- Pair 6 measures 80x44, not 64x44. Pair 5 matches at 88x38.
- `attack` is edge-triggered too, not only `pause` and `interact` (section 4).

### Found beyond the brief

| Finding | Fix |
|---|---|
| Inventory slot: `gui_input` for touch and mouse plus `pressed`; one click used 3 items | one router binding; slots grown 32 to 44 px |
| Dialog handled `ScreenTouch` and `MouseButton`; one click skipped 2 lines | router binding on the dialog layer |
| **The Journal screen did not parse** under 4.7.1 (4 untyped variables), so no Journal button worked | types added |
| Pause menu X was a TSB with `action="pause"`, still live under Settings | `CloseIcon`, no action, bound on the pause layer |
| Bonfire and Game Over hid the pause menu with `visible = false`; with layers that would lock all input | they call `hide_pause_menu()` |
| Load used a `ConfirmationDialog` window, which the router cannot reach and fingers cannot press | in-scene confirm on its own layer; Esc cancels |
| `coming_soon` also used the twin pattern | migrated |
| Tutorial banner hit-tested in `_input` | router binding |
| Tutorial banner covered the Pause button on 4 of 5 levels | banner narrowed 520 to 384 px |
| Pause button rendered 41 px tall | base size set to the art's 108x48, minimum 44 px tall |
| Title after No on the Load card left keyboard focus nowhere | focus returns to Load |
| Main Menu with a dialog open left the dialog over the title | dialog is closed first |
| Bonfire panel was 652x485 in a 640x480 viewport | now fits (portrait column 180 to 164) |

## 4. Action dispatch proof

`Input.action_press()` changes state and injects no event. `bind_held` sends an
`InputEventAction` through `Input.parse_input_event()`. The engine matches such
an event to its action and updates the action state
(`InputMap::event_get_action_status`), then dispatches it through `_input` and
`_unhandled_input`. One mechanism covers both kinds of reader.

| Action | Readers | How they read | Driven by | Headless proof |
|---|---|---|---|---|
| `pause` | `pause_menu.gd` `_unhandled_input`; `settings.gd`, `progress_journal.gd` `_input`; `title_screen.gd` `_unhandled_input` | event | `bind_held` on the HUD Pause visual. The pause menu's X calls `hide_pause_menu()` directly | finger and mouse open the menu once (no open-then-close); 5/5 real levels |
| `interact` | `state_idle.gd`, `state_walk.gd` `handle_input`, via `PlayerStateMachine._unhandled_input`, emit `interact_pressed` (read by `npc.gd`, `treasure_chest.gd`); `dialog_system.gd` `_input` | event | `bind_held` on the Interact label | one click or tap emits `interact_pressed` exactly once |
| `attack` | `state_idle.gd`, `state_walk.gd` `handle_input` | **event** | `bind_held` on the Attack visual | exactly one attack event; the player state machine enters `Attack`; released on finger up |
| `left` `right` `up` `down` | `player.gd` `Input.get_axis` | polled state | native D-pad `action` (engine calls `action_press` and pushes an event) | two fingers and one corner thumb give a diagonal; inert under pause and dialog |
| Mic (no action) | `touch_controls.gd` | direct call | `bind` calls `_on_mic_tapped` | drives no action. Real STT start is untested (no backend headless) |

## 5. Router behaviour and API deviations

| Brief | As built | Why |
|---|---|---|
| `bind(control: Control, ...)` | takes a `CanvasItem` | Attack and Pause are `TouchScreenButton` visuals, which are `Node2D` |
| | adds `bind_button` | one call for router binding plus keyboard `pressed`, instead of two lines in eight screens |
| `push_layer(name)` | optional `owner` | a freed overlay cannot leave a layer open |
| every overlay calls `set_gameplay_suppressed` | `push_layer` / `pop_layer` call it | one call site that an overlay cannot forget |
| `bind_held` uses `action_press` / `action_release` | `InputEventAction` through `parse_input_event` | section 4 |
| winner: layer, `z_index`, tree order | only the top layer is eligible; then `CanvasLayer.layer`, `z_index`, tree order | tree order alone is wrong across CanvasLayers |
| `allow_multi_touch` for the D-pad | implemented and declared on `LeftCluster`, but the router never claims the D-pad | the arrows stay native |
| | adds `unbind`, queries, `debug_regions`, signal `activated` | probe and tests |
| bind sets `IGNORE` | on Buttons only | the first version set it on every bound Control; the probe showed the journal dimmer letting drags reach the pause slider underneath. A test now covers it |

Layer ids are new on each open, so screens bind in their open function.

### Visible changes to expect

- A dialog now hides the touch clusters **and the on-screen Pause button**. On
  a phone, pausing waits until the dialog is dismissed; Esc still works.
- Buttons are taller (44 px). Settings row spacing is tighter, the journal's
  Back sits in the tab row, bonfire's Journal and Back to Title share a row, the
  Pause button and tutorial banner changed size, and the challenge card's
  controls are 44 px.
- Presses act on release, including every former twin that acted on press.
  Held gameplay actions still act on press.
- `player_hud.gd` changed only in minimum sizes. No speech, STT, scoring,
  balance or save-format code changed, and the pointing settings are untouched.

## 6. Audit output

The tool exempts three scenes nothing instances (`SpeechToText.tscn`,
`tutorial_popup.tscn`, `pause_exit_button.tscn`) and fails if one becomes
referenced.

### Before (pre-fix tree, `--self-test`)

```

❌ fullscreen-stop (8)
   gui/bonfire/bonfire.tscn: Control (Control) is full-screen STOP
   gui/game_over/game_over.tscn: Control (Control) is full-screen STOP
   gui/pause_menu/pause_menu.tscn: Control (Control) is full-screen STOP
   gui/settings/settings.tscn: Control (Control) is full-screen STOP
   levels/coming_soon/coming_soon.tscn: Control (Control) is full-screen STOP
   levels/title_screen/title_screen.tscn: Control (Control) is full-screen STOP
   levels/title_screen/title_screen.tscn: LoadConfirm (Control) is full-screen STOP
   levels/title_screen/title_screen.tscn: ExitConfirm (Control) is full-screen STOP

❌ handler-multi-node (28)
   gui/bonfire/bonfire.gd: _on_vitality wired to touch_vitality, vitality_button
   gui/bonfire/bonfire.gd: _on_might wired to might_button, touch_might
   gui/bonfire/bonfire.gd: _on_haste wired to haste_button, touch_haste
   gui/bonfire/bonfire.gd: _on_crit wired to crit_button, touch_crit
   gui/bonfire/bonfire.gd: _on_equip wired to equip_button, touch_equip
   gui/bonfire/bonfire.gd: _on_continue wired to continue_button, touch_continue
   gui/bonfire/bonfire.gd: _on_journal wired to journal_button, touch_journal
   gui/bonfire/bonfire.gd: _on_title wired to title_button, touch_title
   gui/game_over/game_over.gd: _on_title_pressed wired to title_button, touch_title
   gui/pause_menu/pause_menu.gd: _on_save_pressed wired to button_save, touch_save
   gui/pause_menu/pause_menu.gd: _on_load_pressed wired to button_load, touch_load
   gui/pause_menu/pause_menu.gd: _on_main_menu_pressed wired to button_main_menu, touch_main_menu
   gui/pause_menu/pause_menu.gd: _on_journal_pressed wired to journal_button, touch_journal
   gui/progress_journal/progress_journal.gd: close wired to _back, _touch_back
   gui/settings/settings.gd: _on_music_mute_pressed wired to %MusicMuteButton, %TouchMusicMute
   gui/settings/settings.gd: _on_sfx_mute_pressed wired to %SFXMuteButton, %TouchSFXMute
   gui/settings/settings.gd: _on_fullscreen_pressed wired to %FullscreenButton, %TouchFullscreen
   gui/settings/settings.gd: _on_language_pressed wired to %LanguageButton, %TouchLanguage
   gui/settings/settings.gd: _on_touch_pressed wired to %TouchButton, %TouchTouch
   gui/settings/settings.gd: _on_difficulty_pressed wired to %DifficultyButton, %TouchDifficulty
   gui/settings/settings.gd: _on_reset_pressed wired to %ResetButton, %TouchReset
   gui/settings/settings.gd: _on_close_pressed wired to %CloseButton, %TouchClose
   levels/coming_soon/coming_soon.gd: _on_back_pressed wired to back_button, touch_back
   levels/title_screen/title_screen.gd: _on_tutorial_pressed wired to touch_tutorial_button, tutorial_button
   levels/title_screen/title_screen.gd: _on_game_pressed wired to game_button, touch_game_button
   levels/title_screen/title_screen.gd: _on_load_pressed wired to load_button, touch_load_button
   levels/title_screen/title_screen.gd: _on_journal_pressed wired to journal_button, touch_journal_button
   levels/title_screen/title_screen.gd: _on_exit_pressed wired to exit_button, touch_exit_button

❌ pointer-path (17)
   gui/dialog_system/scripts/dialog_system.gd:196: if event is InputEventScreenTouch and event.pressed:
   gui/dialog_system/scripts/dialog_system.gd:198: elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
   gui/pause_menu/inventory/Scripts/inventory_slot_ui.gd:56: if event is InputEventScreenTouch and event.pressed:
   gui/pause_menu/inventory/Scripts/inventory_slot_ui.gd:60: elif event is InputEventMouseButton and event.pressed:
   gui/pause_menu/pause_menu.gd:100: if event is InputEventScreenTouch and event.pressed:
   gui/pause_menu/pause_menu.gd:398: if not (event is InputEventScreenTouch and event.pressed):
   gui/progress_journal/progress_journal.gd:470: if event is InputEventScreenTouch and event.pressed:
   gui/progress_journal/progress_journal.gd:497: if event is InputEventScreenTouch and event.pressed:
   gui/progress_journal/progress_journal.gd:499: if event is InputEventMouseButton \
   levels/title_screen/title_screen.gd:241: if event is InputEventScreenTouch and event.pressed:
   levels/title_screen/title_screen.gd:243: if event is InputEventMouseButton \
   levels/title_screen/title_screen.gd:251: if event is InputEventScreenTouch and not event.pressed:
   levels/title_screen/title_screen.gd:253: if event is InputEventMouseButton \
   levels/tutorial_items/tutorial_dialog.gd:199: if event is InputEventScreenTouch and event.pressed:
   levels/tutorial_items/tutorial_dialog.gd:200: tap_pos = (event as InputEventScreenTouch).position
   levels/tutorial_items/tutorial_dialog.gd:201: elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
   levels/tutorial_items/tutorial_dialog.gd:202: tap_pos = (event as InputEventMouseButton).position

❌ pressed-and-gui-input (3)
   gui/pause_menu/inventory/Scripts/inventory_slot_ui.gd: self is wired through gui_input and ['pressed']
   gui/pause_menu/pause_menu.gd: prev_page_button is wired through gui_input and ['pressed']
   gui/pause_menu/pause_menu.gd: next_page_button is wired through gui_input and ['pressed']

❌ small-target (41)
   gui/bonfire/bonfire.tscn: VitalityButton (Button) is 110x34
   gui/bonfire/bonfire.tscn: MightButton (Button) is 110x34
   gui/bonfire/bonfire.tscn: HasteButton (Button) is 110x34
   gui/bonfire/bonfire.tscn: CritButton (Button) is 110x34
   gui/bonfire/bonfire.tscn: EquipButton (Button) is 220x34
   gui/bonfire/bonfire.tscn: ContinueButton (Button) is 220x38
   gui/bonfire/bonfire.tscn: JournalButton (Button) is 220x36
   gui/bonfire/bonfire.tscn: TitleButton (Button) is 220x36
   gui/pause_menu/pause_menu.tscn: MusicSlider (HSlider) is 0x24
   gui/pause_menu/pause_menu.tscn: MusicQuieter (Button) is 64x36
   gui/pause_menu/pause_menu.tscn: MusicMute (Button) is 120x36
   gui/pause_menu/pause_menu.tscn: MusicLouder (Button) is 64x36
   gui/pause_menu/pause_menu.tscn: JournalButton (Button) is 120x32
   gui/pause_menu/pause_menu.tscn: PrevPageButton (Button) is 64x36
   gui/pause_menu/pause_menu.tscn: NextPageButton (Button) is 64x36
   gui/player_hud/player_hud.tscn: ChallengeSpeakButton (Button) is 80x40
   gui/player_hud/player_hud.tscn: ChallengeFallbackInput (LineEdit) is 0x40
   gui/player_hud/player_hud.tscn: ChallengeFallbackSubmit (Button) is 80x40
   gui/settings/settings.tscn: MusicSlider (HSlider) is 200x24
   gui/settings/settings.tscn: MusicMuteButton (Button) is 56x32
   gui/settings/settings.tscn: SFXSlider (HSlider) is 200x24
   gui/settings/settings.tscn: SFXMuteButton (Button) is 56x32
   gui/settings/settings.tscn: FullscreenButton (Button) is 180x36
   gui/settings/settings.tscn: LanguageButton (Button) is 180x36
   gui/settings/settings.tscn: TouchButton (Button) is 180x36
   gui/settings/settings.tscn: DifficultyButton (Button) is 180x36
   gui/settings/settings.tscn: ResetButton (Button) is 180x36
   gui/settings/settings.tscn: CloseButton (Button) is 180x36
   levels/playground.tscn: ConfirmButton (Button) is 0x0
   levels/playground_changed.tscn: ConfirmButton (Button) is 0x0
   levels/title_screen/title_screen.tscn: YesButton (Button) is 100x40
   levels/title_screen/title_screen.tscn: NoButton (Button) is 100x40
   levels/title_screen/title_screen.tscn: ExitYesButton (Button) is 100x40
   levels/title_screen/title_screen.tscn: ExitNoButton (Button) is 100x40
   gui/pause_menu/pause_menu.gd:92: music_mute_button is 120x36
   gui/player_hud/player_hud.gd:313: challenge_speak_button is 80x40
   gui/player_hud/player_hud.gd:315: challenge_fallback_input is 0x40
   gui/player_hud/player_hud.gd:317: challenge_speak_button is 72x28
   gui/player_hud/player_hud.gd:319: challenge_fallback_input is 0x28
   gui/progress_journal/progress_journal.gd:184: _back is 120x36
   gui/progress_journal/progress_journal.gd:440: btn is 88x32

❌ synthetic-press (2)
   gui/progress_journal/progress_journal.gd:471: button.emit_signal("pressed")
   gui/progress_journal/progress_journal.gd:515: btn.emit_signal("pressed")

❌ touch-twin-node (33)
   gui/bonfire/bonfire.tscn: TouchVitality
   gui/bonfire/bonfire.tscn: TouchMight
   gui/bonfire/bonfire.tscn: TouchHaste
   gui/bonfire/bonfire.tscn: TouchCrit
   gui/bonfire/bonfire.tscn: TouchEquip
   gui/bonfire/bonfire.tscn: TouchContinue
   gui/bonfire/bonfire.tscn: TouchJournal
   gui/bonfire/bonfire.tscn: TouchTitle
   gui/game_over/game_over.tscn: TouchTitle
   gui/pause_menu/pause_menu.tscn: Touch_Journal
   gui/pause_menu/pause_menu.tscn: Touch_Save
   gui/pause_menu/pause_menu.tscn: Touch_Load
   gui/pause_menu/pause_menu.tscn: Touch_MainMenu
   gui/pause_menu/pause_menu.tscn: TouchScreenButton
   gui/settings/settings.tscn: TouchMusicMute
   gui/settings/settings.tscn: TouchSFXMute
   gui/settings/settings.tscn: TouchFullscreen
   gui/settings/settings.tscn: TouchLanguage
   gui/settings/settings.tscn: TouchTouch
   gui/settings/settings.tscn: TouchDifficulty
   gui/settings/settings.tscn: TouchReset
   gui/settings/settings.tscn: TouchClose
   levels/coming_soon/coming_soon.tscn: TouchBack
   levels/title_screen/title_screen.tscn: TouchStartTutorial
   levels/title_screen/title_screen.tscn: TouchStartGame
   levels/title_screen/title_screen.tscn: TouchLoad
   levels/title_screen/title_screen.tscn: TouchJournal
   levels/title_screen/title_screen.tscn: TouchExitGame
   levels/title_screen/title_screen.tscn: TouchLoadYes
   levels/title_screen/title_screen.tscn: TouchLoadNo
   touch_controls/Scene/touch_controls.tscn: Touch_Mic
   touch_controls/Scene/touch_controls.tscn: Touch_Interact
   gui/progress_journal/progress_journal.gd:188: creates a TouchScreenButton

❌ tsb-native-action (4)
   gui/pause_menu/pause_menu.tscn: TouchScreenButton has action="pause"
   touch_controls/Scene/pause_button.tscn: Pause has action="pause"
   touch_controls/Scene/touch_controls.tscn: Touch_Interact has action="interact"
   touch_controls/Scene/touch_controls.tscn: Attack has action="attack"

❌ tsb-on-button (2)
   touch_controls/Scene/touch_controls.tscn: Touch_Mic sits on Button Mic (80x44)
   touch_controls/Scene/touch_controls.tscn: Touch_Interact sits on Button Interact (88x38)

❌ tsb-overlap (28)
   gui/bonfire/bonfire.tscn: TouchCrit / TouchEquip overlap 120x36
   gui/bonfire/bonfire.tscn: TouchContinue / TouchJournal overlap 220x20
   gui/bonfire/bonfire.tscn: TouchJournal / TouchTitle overlap 220x20
   gui/pause_menu/pause_menu.tscn: Touch_Save / Touch_Load overlap 75x44
   gui/pause_menu/pause_menu.tscn: Touch_Save / Touch_MainMenu overlap 75x44
   gui/pause_menu/pause_menu.tscn: Touch_Load / Touch_MainMenu overlap 75x44
   gui/settings/settings.tscn: TouchDifficulty / TouchReset overlap 180x36
   levels/title_screen/title_screen.tscn: TouchStartTutorial / TouchStartGame overlap 120x24
   levels/title_screen/title_screen.tscn: TouchStartTutorial / TouchLoad overlap 120x24
   levels/title_screen/title_screen.tscn: TouchStartTutorial / TouchJournal overlap 120x24
   levels/title_screen/title_screen.tscn: TouchStartTutorial / TouchExitGame overlap 120x24
   levels/title_screen/title_screen.tscn: TouchStartTutorial / TouchLoadYes overlap 100x24
   levels/title_screen/title_screen.tscn: TouchStartTutorial / TouchLoadNo overlap 100x24
   levels/title_screen/title_screen.tscn: TouchStartGame / TouchLoad overlap 120x24
   levels/title_screen/title_screen.tscn: TouchStartGame / TouchJournal overlap 120x24
   levels/title_screen/title_screen.tscn: TouchStartGame / TouchExitGame overlap 120x24
   levels/title_screen/title_screen.tscn: TouchStartGame / TouchLoadYes overlap 100x24
   levels/title_screen/title_screen.tscn: TouchStartGame / TouchLoadNo overlap 100x24
   levels/title_screen/title_screen.tscn: TouchLoad / TouchJournal overlap 120x24
   levels/title_screen/title_screen.tscn: TouchLoad / TouchExitGame overlap 120x24
   levels/title_screen/title_screen.tscn: TouchLoad / TouchLoadYes overlap 100x24
   levels/title_screen/title_screen.tscn: TouchLoad / TouchLoadNo overlap 100x24
   levels/title_screen/title_screen.tscn: TouchJournal / TouchExitGame overlap 120x24
   levels/title_screen/title_screen.tscn: TouchJournal / TouchLoadYes overlap 100x24
   levels/title_screen/title_screen.tscn: TouchJournal / TouchLoadNo overlap 100x24
   levels/title_screen/title_screen.tscn: TouchExitGame / TouchLoadYes overlap 100x24
   levels/title_screen/title_screen.tscn: TouchExitGame / TouchLoadNo overlap 100x24
   levels/title_screen/title_screen.tscn: TouchLoadYes / TouchLoadNo overlap 100x36

Allowlisted D-pad diagonals (4):
   touch_controls/Scene/touch_controls.tscn: Left / Up overlap 14x10
   touch_controls/Scene/touch_controls.tscn: Left / Down overlap 14x18
   touch_controls/Scene/touch_controls.tscn: Right / Up overlap 14x10
   touch_controls/Scene/touch_controls.tscn: Right / Down overlap 14x18

166 finding(s)

  ✅ 1 TouchCrit / TouchEquip overlap 120x36
  ✅ 2 TouchDifficulty / TouchReset overlap 180x36
  ✅ 3 TouchContinue / TouchJournal overlap 220x20
  ✅ 4 TouchJournal / TouchTitle overlap 220x20
  ✅ 5 Touch_Interact sits on Button Interact (88x38)
  ✅ 6 Touch_Mic sits on Button Mic (80x44)
  ❌ 7 touch_controls.tscn Attack / Interact NOT reported
       Attack is textured, so the engine anchors it top-left: x 132..212 in RightCluster,
       while Interact ends at x 100. They are 32 px apart. See the report, section 3.
self-test: 6/7 pairs reported
```

### After

```

Allowlisted D-pad diagonals (4):
   touch_controls/Scene/touch_controls.tscn: Left / Up overlap 14x10
   touch_controls/Scene/touch_controls.tscn: Left / Down overlap 14x18
   touch_controls/Scene/touch_controls.tscn: Right / Up overlap 14x10
   touch_controls/Scene/touch_controls.tscn: Right / Down overlap 14x18

0 finding(s)
```

## 7. Runtime probe (please paste your output here)

1. Re-export the Web build. `build/web/` is committed and **was not rebuilt in
   this pass**: `python3 tools/web/play_in_browser.py`.
2. Open `http://localhost:8060/?ui_probe` and open the browser console.
3. Visit title, both title confirms (Exit is hidden on web), settings, journal
   (all three tabs), gameplay, pause, load confirm, bonfire, a dialog and a
   speech challenge. It dumps by itself; F9 forces a dump.
4. Paste every `[ui-probe] ===== screen=` block here. Any `** CHECK **` or
   `SMALL` line is a bug. `(allowed D-pad)` and `(backdrop)` are expected.

```
(paste here)
```

## 8. Manual matrix

Run on desktop web and on a real phone. Tick each.

- [ ] Reported case: tap a button that had another directly underneath (settings Difficulty / Reset, bonfire Crit / Equip): only the visible one acts.
- [ ] Every menu button, twice in a row: exactly one effect per tap (watch Mute, Difficulty, Language, inventory quantity, bonfire gems).
- [ ] Title with a save: open LoadConfirm and tap Yes and No where a menu button sits underneath: nothing underneath reacts.
- [ ] Open pause, settings, bonfire, journal and game over; tap where a D-pad arrow or Attack was: nothing moves or attacks.
- [ ] Hold Attack and an arrow, then open pause with another finger or Esc: movement stops and no attack continues.
- [ ] Two fingers on two D-pad arrows, and one thumb on a corner: diagonal movement.
- [ ] Keyboard only: arrows + Enter navigate and activate every menu, including pause Load then Cancel.
- [ ] Dialog: each click or tap advances exactly one line.
- [ ] Level 02, 03 and the horde on a phone: **Mic On starts listening** and Mic Off stops it.
- [ ] Mouse hover still highlights menu buttons.
- [ ] Layout looks right: settings, bonfire, journal tabs, pause button, tutorial banner, challenge card, in portrait and landscape.

## 9. Only a human can confirm

- **Browser user gesture for the mic.** Mic used to toggle from `Button.toggled`
  and now toggles from the router on release. Both run when Godot processes the
  queued browser event, but only a real browser can show that speech
  recognition still starts.
- **Real touch delivery.** Whether a phone browser sends only `ScreenTouch`, as
  the engine settings imply. Compatibility mouse events inside 80 ms and 3 px
  would be merged; later ones would act as a second press.
- **Native GUI on phones (pre-existing, not changed).** By engine source, plain
  `Button`s and sliders ignore fingers with `emulate_mouse_from_touch=false`.
  Check the challenge card's Speak, Submit and Listen buttons, both volume
  sliders and the Android mic-permission button. If Speak is dead, routing those
  buttons is a small follow-up; it was left alone because it sits in the speech
  flow.
- Visual layout, touch comfort at phone scale (the HUD clusters scale with the
  screen), Android export, and audio.

## 10. Proposed AGENTS.md text (not applied)

Replace the "Running / building" bullet about the binary with:

> - No `godot` on PATH, but `~/Downloads/Godot.app` (4.7.1) runs headless.
>   `python3.13 tools/ui_qa/run_headless_tests.py` runs the input tests on a
>   throwaway copy. Visual and mic checks are still manual.

Add a section:

> ## UI input
>
> One press fires one action. `00_globals/ui_input_router.gd` is the only
> pointer dispatcher: never add `TouchScreenButton` twins, pointer handling in
> `_input` / `gui_input`, or a native TSB `action` outside the D-pad. Overlays
> `push_layer` / `pop_layer` and must be closed through their close function.
> Read `docs/ui-input-rules.md` before adding a button, and run
> `python3.13 tools/ui_qa/input_audit.py`.
