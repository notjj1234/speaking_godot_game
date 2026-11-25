# UI input rules

## The invariant

**One physical press fires at most one interactive action, and it belongs to the
topmost interactive element of the topmost active UI layer.** The only exception
is the D-pad diagonals.

## Why this is easy to break here

`project.godot` has `emulate_touch_from_mouse=true` and
`emulate_mouse_from_touch=false`. Do not change either without evidence: the
input model depends on both.

| Device | What the engine delivers | `TouchScreenButton` reacts | `Button.pressed` reacts |
|---|---|---|---|
| Mouse click | emulated `ScreenTouch`, then `MouseButton` | yes (touch) | yes (mouse) |
| Finger | `ScreenTouch` only | yes | **no** |

So a `Button` with a `TouchScreenButton` on top fires twice on desktop, and a
plain `Button` ignores fingers. Handling both event types yourself in
`gui_input` or `_input` fires twice for the same reason.

`UiInputRouter` (`00_globals/ui_input_router.gd`) is the only pointer
dispatcher. It treats a mouse event and its touch twin (within 80 ms and 3 px)
as one press.

## One owner per region

| Kind of control | Visual | Pointer owner | Keyboard | Never |
|---|---|---|---|---|
| Menu, dialog or confirm button | `Button` (the router sets `mouse_filter = IGNORE`) | `UiInputRouter.bind_button` | `Button.pressed` | a `TouchScreenButton` twin, `gui_input`, hit-testing in `_input` |
| Gameplay action (Attack, Pause) | `TouchScreenButton` with `action = ""` | `UiInputRouter.bind_held` | the input map | a native `action` |
| Gameplay label (Interact, Mic) | `Button` with `mouse_filter = IGNORE`, `focus_mode = NONE` | `bind_held` / `bind` | the input map | |
| Tappable non-button (dialog bar, tutorial banner, journal dimmer) | any `Control` | `UiInputRouter.bind` | `_input`, actions only | reading pointer events |
| **D-pad (the one exception)** | `TouchScreenButton` with native `action` | the engine | the input map | binding it to the router |

### D-pad allowlist

`touch_controls/Scene/touch_controls.tscn`: `Left`, `Right`, `Up`, `Down` under
`LeftCluster`. Neighbouring arrows overlap (14x10 at the top, 14x18 at the
bottom) so that one thumb on a corner holds two directions. It is declared in
three places that must agree: `_bind_pointer_regions()` in `touch_controls.gd`,
`DPAD` in `tools/ui_qa/input_audit.py`, and `DPAD` in
`tools/ui_qa/ui_overlap_probe.gd`.

### Native GUI that stays outside the router

These have no twin and nothing routed on top of them, so each press has one
dispatcher: `HSlider`s, the challenge card's Speak / Submit / Listen buttons and
text box (shown only while the tree is paused, when the gameplay HUD cannot
process), and the Android mic-permission button. They respond to mouse events
only, so on a real touch screen expect them not to react.

## Layers and modals

- Layer 0 is the base layer: gameplay HUD, title menu, tutorial banner.
- An overlay calls `push_layer` when it opens and `pop_layer` when it closes.
  Only the newest open layer receives presses. `pop_layer` forgets everything
  bound to that layer.
- Pass the overlay as the second argument, `push_layer(&"name", self)`, so a
  freed scene cannot leave a layer behind and lock all input.
- Opening any layer releases held actions and hides the touch clusters and the
  pause button (`set_gameplay_suppressed`). The router does this itself.
- **Close an overlay through its close function.** Setting `visible = false` on
  another overlay from outside leaves its layer open, and every press below dies.
- A dimmer needs both: `MOUSE_FILTER_STOP` (blocks sliders and text boxes below)
  **and** a router layer (blocks everything bound or touch-based below). A
  dimmer alone does not block a `TouchScreenButton`.
- Hidden means inert: invisible, disabled, paused, queued-for-deletion and
  zero-scale regions never receive presses.
- Do not use `ConfirmationDialog` or other `Window` popups for in-game confirms.
  The router cannot dispatch to them and they do not respond to fingers.
- Every touch target is at least 44x44 design px.

## Driving input actions

`pause`, `interact` and `attack` are read from **events**
(`event.is_action_pressed`). `Input.action_press()` only changes action state and
never reaches those readers. `bind_held` sends an `InputEventAction` through
`Input.parse_input_event()`, which does both.

## Add a new button (3 steps)

1. **Make the visual.** A `Button`, at least 44x44, placed so it overlaps no
   other interactive node. No `Touch_*` node.
2. **Route it once**, in the function that opens its screen:
   ```gdscript
   UiInputRouter.bind_button(my_button, _on_my_pressed, _input_layer)
   ```
   (Base layer: omit the last argument. New overlay: first
   `_input_layer = UiInputRouter.push_layer(&"my_overlay", self)`, and
   `pop_layer` on close.) Do not also connect `pressed`; `bind_button` does.
3. **Check it.**
   ```bash
   python3.13 tools/ui_qa/input_audit.py          # must exit 0
   python3.13 tools/ui_qa/run_headless_tests.py   # needs a Godot 4.7 binary
   ```
   Then run the probe on the screen: `?ui_probe` on the web URL, or
   `-- --ui-probe` on desktop. F9 dumps; it also dumps on screen or layer
   changes. Any `** CHECK **` line or `SMALL` live node is a bug. Add a
   one-press-one-effect case to `tools/ui_qa/test_ui_screens.gd`.

## API

| Call | Purpose |
|---|---|
| `bind(item, handler, layer = 0)` | Activate once, on release inside `item` (`Control`, or a `TouchScreenButton` used as a visual) |
| `bind_button(button, handler, layer = 0)` | `bind` plus the keyboard `pressed` connection |
| `bind_rect(rect_source, handler, layer = 0)` | A region with no node; ranks below node regions |
| `bind_held(item, action_name, layer = 0)` | Hold an input action while pressed |
| `unbind(item)` | Remove a binding |
| `push_layer(name, owner = null) -> int` / `pop_layer(id)` | Modal layers |
| `active_layer()` / `active_layer_name()` / `is_gameplay_suppressed()` | Queries |
| `set_gameplay_enabled(enabled)` | Suppress gameplay without opening a layer |
| `allow_multi_touch(control, group)` | Several fingers on one region |
| `debug_regions()`, signal `activated` | Probe and tests |

Among overlapping regions on the top layer, the winner is the higher
`CanvasLayer.layer`, then the higher effective `z_index`, then the later node in
the tree.
