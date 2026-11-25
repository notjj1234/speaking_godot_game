extends CanvasLayer

## Fallback only: the badge shows application/config/version from project.godot,
## so bumping the version there is enough.
const VERSION := "0.2.4"
## Sits under the HUD's mic/speech indicator (top-right, y 8-36) instead of on top of it.
const TOP := 40.0


func _ready() -> void:
	layer = 128
	follow_viewport_enabled = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := PanelContainer.new()
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
