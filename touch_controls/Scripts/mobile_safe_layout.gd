class_name MobileSafeLayout
extends RefCounted

const DESIGN_SIZE := Vector2(640, 480)
const MARGIN := 4.0

static func window_size() -> Vector2:
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return DESIGN_SIZE
	return Vector2(win)


static func is_portrait(viewport: Viewport = null) -> bool:
	var size := _screen_size(viewport)
	return size.y > size.x


static func visible_rect_design() -> Rect2:
	return visible_rect_design_from_viewport(null)


static func visible_rect_design_from_viewport(viewport: Viewport) -> Rect2:
	if viewport != null:
		var vis := viewport.get_visible_rect()
		if vis.size.x > 0.0 and vis.size.y > 0.0:
			return vis
	var window := window_size()
	var scale := minf(window.x / DESIGN_SIZE.x, window.y / DESIGN_SIZE.y)
	if scale <= 0.0:
		return Rect2(Vector2.ZERO, DESIGN_SIZE)
	# Godot stretch aspect "expand": min scale, then grow the viewport to cover the window.
	var expanded := window / scale
	return Rect2(Vector2.ZERO, expanded)


static func _screen_size(viewport: Viewport) -> Vector2:
	if viewport != null:
		var vis := viewport.get_visible_rect().size
		if vis.x > 0.0 and vis.y > 0.0:
			return vis
	return window_size()
