extends CanvasLayer

@onready var top_right: Control = $Root/TopRight

var _touch_ui_enabled: bool = true
var _layout_hooked: bool = false


func _ready() -> void:
	add_to_group("pause_button")
	_touch_ui_enabled = MobileSafeLayout.wants_touch_ui()
	if not _touch_ui_enabled:
		print("🖥️ Desktop detected — hiding on-screen pause button (use Esc).")
		visible = false
		return
	var viewport := get_viewport()
	if viewport and not viewport.size_changed.is_connected(_apply_safe_layout):
		viewport.size_changed.connect(_apply_safe_layout)
	_layout_hooked = true
	_apply_safe_layout()
	call_deferred("_apply_safe_layout")


func _notification(what: int) -> void:
	if not _touch_ui_enabled:
		return
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_apply_safe_layout()


func apply_touch_ui_enabled() -> void:
	_touch_ui_enabled = MobileSafeLayout.wants_touch_ui()
	if not _touch_ui_enabled:
		visible = false
		return
	if not _layout_hooked:
		var viewport := get_viewport()
		if viewport and not viewport.size_changed.is_connected(_apply_safe_layout):
			viewport.size_changed.connect(_apply_safe_layout)
		_layout_hooked = true
	_apply_safe_layout()
	var menu := get_node_or_null("/root/PauseMenu")
	visible = not (menu != null and bool(menu.get("is_paused")))


func set_suppressed_by_pause(suppressed: bool) -> void:
	if not _touch_ui_enabled:
		return
	visible = not suppressed


func _apply_safe_layout() -> void:
	if not _touch_ui_enabled:
		visible = false
		return
	if top_right == null:
		return
	var root := $Root as Control
	if root:
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.offset_left = 0
		root.offset_top = 0
		root.offset_right = 0
		root.offset_bottom = 0
	var placed: Dictionary = MobileSafeLayout.layout_touch_controls(get_viewport())
	var visual: Rect2 = placed["pause"]
	var base := MobileSafeLayout.PAUSE_BUTTON_SIZE
	top_right.anchor_left = 0.0
	top_right.anchor_top = 0.0
	top_right.anchor_right = 0.0
	top_right.anchor_bottom = 0.0
	top_right.pivot_offset = Vector2.ZERO
	top_right.position = visual.position
	top_right.size = base
	if base.x <= 0.0 or visual.size.x <= 0.0 or visual.size.y <= 0.0:
		top_right.scale = Vector2.ZERO
		return
	var scale := minf(visual.size.x / base.x, visual.size.y / base.y)
	top_right.scale = Vector2(scale, scale)
