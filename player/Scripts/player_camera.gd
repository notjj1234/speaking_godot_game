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

var _bounds: Array[Vector2] = []
var _fit_key := ""


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	LevelManager.tilemap_bounds_changed.connect(update_limits)
	update_limits(LevelManager.current_tilemap_bounds)


func _process(_delta: float) -> void:
	# Keep the view on whole pixels while the parent CharacterBody2D moves subpixel.
	var parent_node := get_parent() as Node2D
	if parent_node == null:
		return
	var parent_pos := parent_node.global_position
	offset = parent_pos.round() - parent_pos
	# Refit when the window turns or resizes, or touch controls are switched on/off.
	var key := "%s|%s" % [get_viewport_rect().size, MobileSafeLayout.wants_touch_ui()]
	if key != _fit_key:
		_refit()


func update_limits(bounds: Array[Vector2]) -> void:
	if bounds == []:
		return
	_bounds = bounds.duplicate()
	_refit()


func _refit() -> void:
	var view := get_viewport_rect().size
	_fit_key = "%s|%s" % [view, MobileSafeLayout.wants_touch_ui()]
	if _bounds.size() < 2 or view.x <= 0.0 or view.y <= 0.0:
		return
	var map := Rect2(_bounds[0], _bounds[1] - _bounds[0])
	if map.size.x <= 0.0 or map.size.y <= 0.0:
		return
	var portrait_touch := MobileSafeLayout.wants_touch_ui() and view.y > view.x
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
