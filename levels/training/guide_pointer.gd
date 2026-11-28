class_name GuidePointer
extends CanvasLayer
## Tutorial guide markers, so nobody has to guess where to go or what to press:
##  - "world": a chunky gold arrow bobbing just above a world target (an enemy,
##    a patch, a gem, an NPC, the campfire);
##  - "edge": the same arrow pinned to the screen edge, pointing toward a
##    target that is off screen;
##  - "ui": a pulsing ring (plus a small arrow) around a button on any layer.
## Everything is drawn in screen space on one overlay that ignores input, so it
## never blocks a tap. follow() takes a Callable re-evaluated every frame; it
## returns a Node2D, a Vector2 world point, a Control / screen-layer Node2D
## (button), or null to hide.

const GOLD := Color(1.0, 0.82, 0.22, 1)
const INK := Color(0.15, 0.1, 0.03, 1)
const EDGE_INSET := 28.0
## How far above a world target's origin the arrow tip sits (times its scale).
const HEAD_HEIGHT := 40.0
const TIP_GAP := 6.0
const BOB_PX := 6.0
const BOB_HZ := 2.0
const RING_PAD := 6.0

var _target_fn: Callable = Callable()
var _kind: StringName = &""
var _arrow_pos := Vector2.ZERO
var _arrow_angle := PI / 2.0  # pointing down
var _ring := Rect2()
var _ring_frame := false
var _head_px := 0.0
var _time := 0.0
var _overlay: Control


func _init() -> void:
	layer = 9  # above the HUD (2), coach (5) and dialog (8); below the pause menu (10)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = Control.new()
	_overlay.name = "GuideOverlay"
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_on_draw)
	add_child(_overlay)


func follow(target_fn: Callable) -> void:
	_target_fn = target_fn
	_update()


func clear() -> void:
	_target_fn = Callable()
	_update()


func current_kind() -> StringName:
	return _kind


func is_showing() -> bool:
	return _kind != &"" and _overlay.visible


## Screen position of the arrow tip ("world" / "edge").
func arrow_position() -> Vector2:
	return _arrow_pos


## Direction the arrow points, in radians (0 = right, PI/2 = down).
func arrow_angle() -> float:
	return _arrow_angle


## Screen rect the ring surrounds ("ui").
func ring_rect() -> Rect2:
	return _ring


## Rectangular controls (chips, tiles, a card row) get a hugging frame; only
## round screen buttons (the touch sword / mic) get a circle.
func is_wide_ring() -> bool:
	return _ring_frame


## Screen rect around a world target and its arrow (empty when the target is
## a button or off screen) so other UI can keep clear of it.
func world_target_rect() -> Rect2:
	if _kind != &"world":
		return Rect2()
	var top := _arrow_pos.y - 30.0
	var bottom := _arrow_pos.y + TIP_GAP + _head_px + 12.0
	return Rect2(_arrow_pos.x - 32.0, top, 64.0, bottom - top)


func overlay_mouse_filter() -> int:
	return _overlay.mouse_filter


func _process(delta: float) -> void:
	_time += delta
	_update()


func _update() -> void:
	_kind = &""
	var target = _target_fn.call() if _target_fn.is_valid() else null
	if target is Object and not is_instance_valid(target):
		target = null
	if target != null:
		_locate(target)
	_overlay.visible = _kind != &"" and _allowed()
	_overlay.queue_redraw()


## Pause menu open: hide. Game paused by a speech challenge: only button rings.
func _allowed() -> bool:
	var menu := get_node_or_null("/root/PauseMenu")
	if menu and menu.visible:
		return false
	if get_tree() and get_tree().paused:
		return _kind == &"ui"
	return true


func _locate(target) -> void:
	var view := get_viewport().get_visible_rect()
	if target is Control:
		var c := target as Control
		if not c.is_visible_in_tree():
			return
		var xf := c.get_global_transform_with_canvas()
		_ring = Rect2(xf.origin, c.size * xf.get_scale())
		_ring_frame = true
		_kind = &"ui"
		return
	if target is Node2D and (target as Node2D).get_canvas_layer_node() != null:
		# A screen-space button (e.g. a TouchScreenButton on the controls layer).
		var n := target as Node2D
		if not n.is_visible_in_tree():
			return
		var xf2 := n.get_global_transform_with_canvas()
		var size := Vector2(64, 64)
		if n is TouchScreenButton and (n as TouchScreenButton).texture_normal:
			size = (n as TouchScreenButton).texture_normal.get_size()
		_ring = Rect2(xf2.origin, size * xf2.get_scale().abs())
		_ring_frame = false
		_kind = &"ui"
		return
	var screen: Vector2
	var head := HEAD_HEIGHT
	if target is Node2D:
		var node := target as Node2D
		if not node.is_inside_tree():
			return
		screen = node.get_global_transform_with_canvas().origin
		head *= absf(node.global_scale.y)
	elif target is Vector2:
		screen = get_viewport().get_canvas_transform() * (target as Vector2)
		head = 0.0
	else:
		return
	var inner := view.grow(-EDGE_INSET)
	_head_px = head
	var tip := screen - Vector2(0.0, head + TIP_GAP)
	if inner.has_point(screen):
		_kind = &"world"
		_arrow_angle = PI / 2.0
		_arrow_pos = tip - Vector2(0.0, BOB_PX * (0.5 + 0.5 * sin(_time * TAU * BOB_HZ)))
		return
	_kind = &"edge"
	var center := view.get_center()
	_arrow_angle = (screen - center).angle()
	_arrow_pos = _clamp_ray(center, screen, inner)


## Where the ray from `from` toward `to` leaves `rect`.
func _clamp_ray(from: Vector2, to: Vector2, rect: Rect2) -> Vector2:
	var d := to - from
	var t := 1.0
	if absf(d.x) > 0.001:
		t = minf(t, ((rect.end.x if d.x > 0.0 else rect.position.x) - from.x) / d.x)
	if absf(d.y) > 0.001:
		t = minf(t, ((rect.end.y if d.y > 0.0 else rect.position.y) - from.y) / d.y)
	return from + d * clampf(t, 0.0, 1.0)


func _on_draw() -> void:
	match _kind:
		&"world":
			_draw_arrow(_arrow_pos, PI / 2.0, 1.0)
		&"edge":
			var pulse := 1.0 + 0.12 * sin(_time * TAU * 1.2)
			_draw_arrow(_arrow_pos, _arrow_angle, pulse)
		&"ui":
			var pulse := 0.5 + 0.5 * sin(_time * TAU * 1.5)
			var c := _ring.get_center()
			if is_wide_ring():
				# A hugging frame (a circle round a tile row would cover the
				# screen); the arrow comes in from the side so it doesn't sit
				# on the text above (dialog lines, the "Say:" word).
				var frame := _ring.grow(RING_PAD + pulse * 3.0)
				_overlay.draw_rect(frame.grow(1.5), INK, false, 5.0)
				_overlay.draw_rect(frame, Color(GOLD, 0.65 + 0.35 * pulse), false, 3.0)
				var view := get_viewport().get_visible_rect()
				if frame.position.x - view.position.x > 34.0:
					_draw_arrow(Vector2(frame.position.x - TIP_GAP - BOB_PX * pulse, c.y), 0.0, 0.75)
				else:
					_draw_arrow(Vector2(frame.end.x + TIP_GAP + BOB_PX * pulse, c.y), PI, 0.75)
			else:
				var r := maxf(_ring.size.x, _ring.size.y) * 0.5 + RING_PAD + pulse * 4.0
				_overlay.draw_arc(c, r + 1.5, 0.0, TAU, 48, INK, 5.0, true)
				_overlay.draw_arc(c, r, 0.0, TAU, 48, Color(GOLD, 0.65 + 0.35 * pulse), 3.0, true)
				_draw_arrow(Vector2(c.x, c.y - r - TIP_GAP - BOB_PX * pulse), PI / 2.0, 0.75)


## A chunky arrow whose tip is at `tip`, pointing along `angle`.
func _draw_arrow(tip: Vector2, angle: float, k: float) -> void:
	# Shape pointing +X with its tip at the origin.
	var shape := PackedVector2Array([
		Vector2(0, 0), Vector2(-14, -12), Vector2(-14, -5), Vector2(-28, -5),
		Vector2(-28, 5), Vector2(-14, 5), Vector2(-14, 12),
	])
	var xf := Transform2D(angle, tip).scaled_local(Vector2(k, k))
	var pts := xf * shape
	_overlay.draw_colored_polygon(pts, GOLD)
	var outline := pts.duplicate()
	outline.append(pts[0])
	_overlay.draw_polyline(outline, INK, 2.0, true)
