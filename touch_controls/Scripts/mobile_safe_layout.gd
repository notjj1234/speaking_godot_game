class_name MobileSafeLayout
extends RefCounted

const DESIGN_SIZE := Vector2(640, 480)
const MARGIN := 4.0

static var _wants_touch_ui_cached: bool = false
static var _wants_touch_ui_resolved: bool = false
static var _force_touch_ui: bool = false

static func window_size() -> Vector2:
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return DESIGN_SIZE
	return Vector2(win)


static func is_portrait(viewport: Viewport = null) -> bool:
	var size := _screen_size(viewport)
	return size.y > size.x


static func wants_touch_ui() -> bool:
	if _force_touch_ui:
		return true
	if _wants_touch_ui_resolved:
		return _wants_touch_ui_cached
	_wants_touch_ui_cached = _detect_wants_touch_ui()
	_wants_touch_ui_resolved = true
	return _wants_touch_ui_cached


static func set_force_touch_ui(enabled: bool) -> void:
	# Temporary desktop preview. Phones already take the real detection path.
	_force_touch_ui = enabled


static func uses_touch_button_twins() -> bool:
	# Mouse clicks become ScreenTouch while emulate_mouse_from_touch is off,
	# so GUI Buttons never fire. Invisible TouchScreenButton twins are the hitboxes.
	return bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false))


static func _detect_wants_touch_ui() -> bool:
	if OS.has_feature("web"):
		# DisplayServer.is_touchscreen_available() is a false positive on web:
		# emulate_touch_from_mouse is enabled, and browsers expose touch APIs on desktop.
		var js_result: Variant = JavaScriptBridge.eval(
			"""
			(function(){
				var ua = navigator.userAgent || '';
				if (/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini|Mobile/i.test(ua)) return true;
				try {
					if (window.matchMedia && window.matchMedia('(pointer: coarse)').matches) return true;
				} catch (e) {}
				return false;
			})()
			""",
			true
		)
		return bool(js_result)
	return DisplayServer.is_touchscreen_available()


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


static func playfield_rect_design_from_viewport(viewport: Viewport) -> Rect2:
	# Largest centered 4:3 rect inside the expanded viewport (matches design playfield).
	var vis := visible_rect_design_from_viewport(viewport)
	var aspect := DESIGN_SIZE.x / DESIGN_SIZE.y
	var play_w: float
	var play_h: float
	if vis.size.y <= 0.0 or vis.size.x <= 0.0:
		return Rect2(vis.position, DESIGN_SIZE)
	if vis.size.x / vis.size.y > aspect:
		play_h = vis.size.y
		play_w = play_h * aspect
	else:
		play_w = vis.size.x
		play_h = play_w / aspect
	var origin := vis.position + Vector2((vis.size.x - play_w) * 0.5, (vis.size.y - play_h) * 0.5)
	return _clip_to_safe_area(Rect2(origin, Vector2(play_w, play_h)), viewport)


static func safe_insets_design(viewport: Viewport = null) -> Vector4:
	var window := window_size()
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0 or window.x <= 0.0 or window.y <= 0.0:
		return Vector4.ZERO
	var scale := minf(window.x / DESIGN_SIZE.x, window.y / DESIGN_SIZE.y)
	if scale <= 0.0:
		return Vector4.ZERO
	var left := float(safe.position.x) / scale
	var top := float(safe.position.y) / scale
	var right := (window.x - float(safe.position.x + safe.size.x)) / scale
	var bottom := (window.y - float(safe.position.y + safe.size.y)) / scale
	return Vector4(maxf(left, 0.0), maxf(top, 0.0), maxf(right, 0.0), maxf(bottom, 0.0))


static func _clip_to_safe_area(rect: Rect2, viewport: Viewport) -> Rect2:
	var vis := visible_rect_design_from_viewport(viewport)
	var insets := safe_insets_design(viewport)
	var safe := Rect2(
		vis.position + Vector2(insets.x, insets.y),
		vis.size - Vector2(insets.x + insets.z, insets.y + insets.w)
	)
	if safe.size.x < 32.0 or safe.size.y < 32.0:
		return rect
	var clipped := rect.intersection(safe)
	if clipped.size.x < 32.0 or clipped.size.y < 32.0:
		return rect
	return clipped


const LEFT_CLUSTER_SIZE := Vector2(220, 220)
const RIGHT_CLUSTER_SIZE := Vector2(220, 180)
const PAUSE_BUTTON_SIZE := Vector2(130, 58)


static func layout_touch_controls(viewport: Viewport) -> Dictionary:
	# Visual rects in viewport coordinates. Each rect sits in an unused band
	# and does not intersect the centered 4:3 arena.
	var vis := visible_rect_design_from_viewport(viewport)
	var content := _safe_content_rect(viewport, vis)
	var arena := _arena_rect(vis)
	var placed := {
		"left": Rect2(),
		"right": Rect2(),
		"pause": Rect2(),
		"arena": arena,
	}
	if vis.size.y > arena.size.y + 0.5:
		var top := Rect2(
			content.position.x,
			content.position.y,
			content.size.x,
			maxf(0.0, arena.position.y - content.position.y)
		)
		var bottom := Rect2(
			content.position.x,
			arena.end.y,
			content.size.x,
			maxf(0.0, content.end.y - arena.end.y)
		)
		var bottom_inner := _inset_rect(bottom, MARGIN)
		var half := maxf(0.0, (bottom_inner.size.x - MARGIN) * 0.5)
		var left_slot := Rect2(bottom_inner.position, Vector2(half, bottom_inner.size.y))
		var right_slot := Rect2(
			Vector2(bottom_inner.position.x + half + MARGIN, bottom_inner.position.y),
			Vector2(maxf(0.0, bottom_inner.size.x - half - MARGIN), bottom_inner.size.y)
		)
		placed["left"] = _fit_in_slot(left_slot, LEFT_CLUSTER_SIZE, "bottom")
		placed["right"] = _fit_in_slot(right_slot, RIGHT_CLUSTER_SIZE, "bottom")
		placed["pause"] = _fit_top_right_avoiding(_inset_rect(top, MARGIN), PAUSE_BUTTON_SIZE, _hud_rects(vis))
	elif vis.size.x > arena.size.x + 0.5:
		var left_band := Rect2(
			content.position.x,
			content.position.y,
			maxf(0.0, arena.position.x - content.position.x),
			content.size.y
		)
		var right_band := Rect2(
			Vector2(arena.end.x, content.position.y),
			Vector2(maxf(0.0, content.end.x - arena.end.x), content.size.y)
		)
		placed["left"] = _fit_in_slot(_inset_rect(left_band, MARGIN), LEFT_CLUSTER_SIZE, "bottom")
		var right_inner := _inset_rect(right_band, MARGIN)
		var pause_rect: Rect2 = _fit_top_right_avoiding(right_inner, PAUSE_BUTTON_SIZE, _hud_rects(vis))
		placed["pause"] = pause_rect
		var below_y := right_inner.position.y
		if pause_rect.size.y > 0.0:
			below_y = pause_rect.end.y + MARGIN
		var below := Rect2(
			right_inner.position.x,
			below_y,
			right_inner.size.x,
			maxf(0.0, right_inner.end.y - below_y)
		)
		placed["right"] = _fit_in_slot(below, RIGHT_CLUSTER_SIZE, "bottom")
	return placed


static func _arena_rect(vis: Rect2) -> Rect2:
	var aspect := DESIGN_SIZE.x / DESIGN_SIZE.y
	var play_w: float
	var play_h: float
	if vis.size.y <= 0.0 or vis.size.x <= 0.0:
		return Rect2(vis.position, DESIGN_SIZE)
	if vis.size.x / vis.size.y > aspect:
		play_h = vis.size.y
		play_w = play_h * aspect
	else:
		play_w = vis.size.x
		play_h = play_w / aspect
	var origin := vis.position + Vector2((vis.size.x - play_w) * 0.5, (vis.size.y - play_h) * 0.5)
	return Rect2(origin, Vector2(play_w, play_h))


static func _safe_content_rect(viewport: Viewport, vis: Rect2) -> Rect2:
	var insets := safe_insets_design(viewport)
	if insets == Vector4.ZERO:
		return vis
	var safe := Rect2(
		vis.position + Vector2(insets.x, insets.y),
		vis.size - Vector2(insets.x + insets.z, insets.y + insets.w)
	)
	if safe.size.x < 32.0 or safe.size.y < 32.0:
		return vis
	return safe


static func _hud_rects(vis: Rect2) -> Array[Rect2]:
	# Hearts, wave label, and version badge. Anchored to the full viewport, not the arena.
	var mid_x := vis.position.x + vis.size.x * 0.5
	var top := vis.position.y
	return [
		Rect2(mid_x - 70.0, top + 2.0, 140.0, 48.0),
		Rect2(mid_x - 160.0, top + 56.0, 320.0, 28.0),
		Rect2(vis.end.x - 72.0, top + 8.0, 64.0, 20.0),
	]


static func _inset_rect(rect: Rect2, margin: float) -> Rect2:
	var inset_size := rect.size - Vector2(margin, margin) * 2.0
	if inset_size.x <= 0.0 or inset_size.y <= 0.0:
		return Rect2(rect.position, Vector2.ZERO)
	return Rect2(rect.position + Vector2(margin, margin), inset_size)


static func _fit_in_slot(slot: Rect2, base: Vector2, anchor: String) -> Rect2:
	if slot.size.x < 1.0 or slot.size.y < 1.0 or base.x <= 0.0 or base.y <= 0.0:
		return Rect2(slot.position, Vector2.ZERO)
	var scale := minf(1.0, minf(slot.size.x / base.x, slot.size.y / base.y))
	var visual := base * scale
	var pos := slot.position + (slot.size - visual) * 0.5
	if anchor == "bottom":
		pos = Vector2(slot.position.x + (slot.size.x - visual.x) * 0.5, slot.end.y - visual.y)
	elif anchor == "top_right":
		pos = Vector2(slot.end.x - visual.x, slot.position.y)
	return Rect2(pos, visual)


static func _fit_top_right_avoiding(slot: Rect2, base: Vector2, obstacles: Array[Rect2]) -> Rect2:
	if slot.size.x < 1.0 or slot.size.y < 1.0 or base.x <= 0.0 or base.y <= 0.0:
		return Rect2(slot.position, Vector2.ZERO)
	var rect := _fit_in_slot(slot, base, "top_right")
	for _step in 6:
		var blocker := _deepest_overlap(rect, obstacles)
		if blocker.size.x <= 0.0:
			break
		var next_y := blocker.end.y + MARGIN
		var room_h := slot.end.y - next_y
		if room_h >= 8.0:
			var room := Rect2(slot.position.x, next_y, slot.size.x, room_h)
			rect = _fit_in_slot(room, base, "top_right")
			continue
		var next_right := blocker.position.x - MARGIN
		var left_w := next_right - slot.position.x
		if left_w < 8.0:
			break
		var left_room := Rect2(slot.position.x, slot.position.y, left_w, slot.size.y)
		rect = _fit_in_slot(left_room, base, "top_right")
	if not slot.encloses(rect):
		rect = rect.intersection(slot)
	return rect


static func _deepest_overlap(rect: Rect2, obstacles: Array[Rect2]) -> Rect2:
	var found := Rect2()
	var found_end := -1.0e20
	for item in obstacles:
		var block: Rect2 = item
		if rect.intersects(block) and block.end.y > found_end:
			found = block
			found_end = block.end.y
	return found


static func _screen_size(viewport: Viewport) -> Vector2:
	if viewport != null:
		var vis := viewport.get_visible_rect().size
		if vis.x > 0.0 and vis.y > 0.0:
			return vis
	return window_size()
