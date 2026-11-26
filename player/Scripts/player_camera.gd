# PlayerCamera.gd

class_name PlayerCamera extends Camera2D

## Fits the view to the level's tilemap bounds on any screen shape.
##
## The project stretches the 640x480 design viewport with aspect "expand", so
## wide screens (16:9 / 16:10 laptops, phones in landscape) and tall screens
## (phones in portrait) see more than 640x480. On a map no bigger than that
## (the Endless Horde arenas are exactly 640x480) plain limits left an empty
## strip on one side. Now:
## * desktop, and touch devices in landscape: zoom in just enough that the map
##   covers the whole screen (no bars); the camera still follows the player;
## * touch devices in portrait: the map fills the width and sits just under the
##   HUD; the space below it belongs to the on-screen controls;
## * maps bigger than the screen: unchanged (zoom 1, plain limits);
## * whatever is left (zoom capped) is split evenly, never pushed to one side.

## Highest zoom used to cover the screen (a 19.5:9 phone needs ~1.63 for 640x480).
const MAX_COVER_ZOOM := 1.75

## How far (px) the body may drift from its snapped pixel before the view follows.
const SNAP_HYSTERESIS := 0.75

var _bounds: Array[Vector2] = []
var _fit_view := Vector2.ZERO
var _fit_touch := false
var _snap := Vector2.ZERO
var _snap_ready := false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Keep refitting while paused: a phone rotated with the pause menu open
	# would otherwise leave the map badly fitted behind the dimmer.
	process_mode = Node.PROCESS_MODE_ALWAYS
	LevelManager.tilemap_bounds_changed.connect(update_limits)
	update_limits(LevelManager.current_tilemap_bounds)


func _process(_delta: float) -> void:
	var parent_node := get_parent() as Node2D
	if parent_node == null:
		return
	# Refit when the window turns or resizes, or touch controls are switched on/off.
	var view := get_viewport_rect().size
	var touch := MobileSafeLayout.wants_touch_ui()
	if view != _fit_view or touch != _fit_touch:
		_refit()
	_snap_to_pixels(parent_node.global_position, view)


## Keep the view on whole pixels while the CharacterBody2D moves subpixel, without
## the two shakes the old one-liner caused:
## * Camera2D adds `offset` AFTER clamping to its limits, so where the view is
##   pinned against a limit (walking along the arena wall) a changing sub-pixel
##   offset shook the whole screen. On a pinned axis the offset is now 0.
## * Pressing into a wall makes move_and_slide nudge the body back and forth by
##   a fraction of a pixel; plain rounding flipped between two pixels every
##   frame. The snapped position now only moves once the body is 0.75 px away.
func _snap_to_pixels(pos: Vector2, view: Vector2) -> void:
	if not _snap_ready:
		_snap = pos.round()
		_snap_ready = true
	if absf(pos.x - _snap.x) > SNAP_HYSTERESIS:
		_snap.x = roundf(pos.x)
	if absf(pos.y - _snap.y) > SNAP_HYSTERESIS:
		_snap.y = roundf(pos.y)
	var o := _snap - pos
	var half := view * 0.5 / zoom
	if pos.x - half.x <= float(limit_left) or pos.x + half.x >= float(limit_right):
		o.x = 0.0
	if pos.y - half.y <= float(limit_top) or pos.y + half.y >= float(limit_bottom):
		o.y = 0.0
	offset = o


func update_limits(bounds: Array[Vector2]) -> void:
	if bounds == []:
		return
	_bounds = bounds.duplicate()
	_refit()


func _refit() -> void:
	var view := get_viewport_rect().size
	_fit_view = view
	_fit_touch = MobileSafeLayout.wants_touch_ui()
	if _bounds.size() < 2 or view.x <= 0.0 or view.y <= 0.0:
		return
	var map := Rect2(_bounds[0], _bounds[1] - _bounds[0])
	if map.size.x <= 0.0 or map.size.y <= 0.0:
		return
	var portrait_touch := _fit_touch and view.y > view.x
	var z := 1.0
	if map.size.x < view.x or map.size.y < view.y:
		if portrait_touch:
			z = maxf(1.0, view.x / map.size.x)
		else:
			z = maxf(1.0, maxf(view.x / map.size.x, view.y / map.size.y))
		z = minf(z, MAX_COVER_ZOOM)
	zoom = Vector2(z, z)
	var seen := view / z
	if map.size.x < seen.x - 0.5:
		limit_left = int(floor(map.get_center().x - seen.x * 0.5))
		limit_right = limit_left + int(ceil(seen.x))
	else:
		limit_left = int(map.position.x)
		limit_right = int(map.end.x)
	if map.size.y < seen.y - 0.5:
		if portrait_touch:
			limit_top = int(floor(map.position.y - MobileSafeLayout.PORTRAIT_ARENA_TOP / z))
		else:
			limit_top = int(floor(map.get_center().y - seen.y * 0.5))
		limit_bottom = limit_top + int(ceil(seen.y))
	else:
		limit_top = int(map.position.y)
		limit_bottom = int(map.end.y)
