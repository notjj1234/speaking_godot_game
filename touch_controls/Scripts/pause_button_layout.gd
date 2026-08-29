extends CanvasLayer

const PAUSE_SIZE := Vector2(130, 58)

@onready var top_right: Control = $Root/TopRight


func _ready() -> void:
	var viewport := get_viewport()
	if viewport:
		viewport.size_changed.connect(_apply_safe_layout)
	_apply_safe_layout()
	call_deferred("_apply_safe_layout")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_apply_safe_layout()


func _apply_safe_layout() -> void:
	if top_right == null:
		return
	var vis := MobileSafeLayout.visible_rect_design_from_viewport(get_viewport())
	var margin := MobileSafeLayout.MARGIN
	top_right.anchor_left = 1.0
	top_right.anchor_top = 0.0
	top_right.anchor_right = 1.0
	top_right.anchor_bottom = 0.0
	top_right.offset_left = vis.end.x - vis.position.x - margin - PAUSE_SIZE.x
	top_right.offset_top = vis.position.y + margin
	top_right.offset_right = vis.end.x - vis.position.x - margin
	top_right.offset_bottom = vis.position.y + margin + PAUSE_SIZE.y
	# If Root already fills the overlay viewport, pin to its top-right.
	if vis.position == Vector2.ZERO:
		top_right.offset_left = -margin - PAUSE_SIZE.x
		top_right.offset_top = margin
		top_right.offset_right = -margin
		top_right.offset_bottom = margin + PAUSE_SIZE.y
