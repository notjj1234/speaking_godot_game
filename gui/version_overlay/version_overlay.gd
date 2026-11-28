extends CanvasLayer

## Fallback only: the badge shows application/config/version from project.godot,
## so bumping the version there is enough.
const VERSION := "0.2.4"
## Sits under the HUD's mic/speech indicator (top-right, y 8-36) instead of on top of it.
const TOP := 40.0


## Above the HUD (2) and dialog bar (8), below the pause menu (10) and every
## other modal card: at 640 wide the badge sits on their top-right corner.
const BADGE_LAYER := 9
## Five taps on the badge within TAP_WINDOW_MS toggle developer mode.
const TAPS_FOR_DEV := 5
const TAP_WINDOW_MS := 3000

var _panel: PanelContainer
var _label: Label
var _taps: Array[int] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = BADGE_LAYER
	follow_viewport_enabled = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := PanelContainer.new()
	_panel = panel
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -72.0
	panel.offset_top = TOP
	panel.offset_right = -8.0
	panel.offset_bottom = TOP + 20.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.92)
	style.set_content_margin_all(4)
	style.set_corner_radius_all(2)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var label := Label.new()
	label.text = str(ProjectSettings.get_setting("application/config/version", VERSION))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", 12)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	_label = label
	UiInputRouter.bind(panel, badge_tapped)
	# SettingsManager loads after this autoload.
	call_deferred("_hook_settings")


func _hook_settings() -> void:
	var settings := get_node_or_null("/root/SettingsManager")
	if settings:
		settings.dev_mode_changed.connect(func(_on): _refresh_label())
	_refresh_label()


func badge_tapped() -> void:
	var now := Time.get_ticks_msec()
	_taps.append(now)
	while not _taps.is_empty() and now - _taps[0] > TAP_WINDOW_MS:
		_taps.pop_front()
	if _taps.size() < TAPS_FOR_DEV:
		return
	_taps.clear()
	toggle_dev_mode()


## Ctrl+` (dev_toggle) toggles developer mode too; works while paused.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_action_pressed(&"dev_toggle", false, true):
		get_viewport().set_input_as_handled()
		toggle_dev_mode()


func toggle_dev_mode() -> void:
	var settings := get_node_or_null("/root/SettingsManager")
	if settings == null:
		return
	settings.set_dev_mode(not settings.dev_mode)
	PlayerHud.show_notice("Developer mode ON - typing enabled" if settings.dev_mode else "Developer mode OFF")


func _refresh_label() -> void:
	if _label == null:
		return
	var settings := get_node_or_null("/root/SettingsManager")
	var dev: bool = settings != null and settings.dev_mode
	var version := str(ProjectSettings.get_setting("application/config/version", VERSION))
	_label.text = version + (" DEV" if dev else "")
	_panel.offset_left = -96.0 if dev else -72.0
