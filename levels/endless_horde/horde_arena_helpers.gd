class_name HordeArenaHelpers
extends RefCounted
## Ground helpers shared by the Endless Horde and Training levels.

## Painted patch tiles (2x2) from the ground atlas, source 0.
const PATCH_TILES: Array[Vector2i] = [Vector2i(9, 1), Vector2i(10, 1), Vector2i(9, 2), Vector2i(10, 2)]


static func clamp_to_grass(grass: TileMapLayer, pos: Vector2, inset: float) -> Vector2:
	if grass == null:
		return pos
	var rect := grass.get_used_rect()
	if rect.size == Vector2i.ZERO:
		return pos
	var min_cell := rect.position
	var max_cell := rect.position + rect.size - Vector2i.ONE
	var min_pos := grass.to_global(grass.map_to_local(min_cell))
	var max_pos := grass.to_global(grass.map_to_local(max_cell))
	var lo := Vector2(minf(min_pos.x, max_pos.x), minf(min_pos.y, max_pos.y))
	var hi := Vector2(maxf(min_pos.x, max_pos.x), maxf(min_pos.y, max_pos.y))
	lo += Vector2(inset, inset)
	hi -= Vector2(inset, inset)
	if lo.x > hi.x:
		var mid_x := (lo.x + hi.x) * 0.5
		lo.x = mid_x
		hi.x = mid_x
	if lo.y > hi.y:
		var mid_y := (lo.y + hi.y) * 0.5
		lo.y = mid_y
		hi.y = mid_y
	return Vector2(clampf(pos.x, lo.x, hi.x), clampf(pos.y, lo.y, hi.y))


## A wall along the ground's top edge, named "TopBarrier". Null without ground.
static func add_top_barrier(parent: Node, grass: TileMapLayer, walls_layer: int) -> StaticBody2D:
	if grass == null:
		return null
	var rect := grass.get_used_rect()
	if rect.size == Vector2i.ZERO:
		return null
	var left_cell := rect.position
	var right_cell := rect.position + Vector2i(rect.size.x - 1, 0)
	var left := grass.to_global(grass.map_to_local(left_cell))
	var right := grass.to_global(grass.map_to_local(right_cell))
	var top_y := minf(left.y, right.y) - 16.0
	var x0 := minf(left.x, right.x) - 16.0
	var x1 := maxf(left.x, right.x) + 16.0
	var body := StaticBody2D.new()
	body.name = "TopBarrier"
	body.collision_layer = walls_layer
	body.collision_mask = 0
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(x1 - x0, 24.0)
	shape_node.shape = shape
	body.add_child(shape_node)
	parent.add_child(body)
	body.global_position = Vector2((x0 + x1) * 0.5, top_y)
	return body


## Paints a 2x2 path patch at `around`, appending what it replaced to
## `restore`. Returns the patch centre in global space.
static func paint_patch(grass: TileMapLayer, around: Vector2, restore: Array[Dictionary]) -> Vector2:
	if grass == null:
		return around
	var origin := grass.local_to_map(grass.to_local(around))
	var cells: Array[Vector2i] = [
		origin,
		origin + Vector2i(1, 0),
		origin + Vector2i(0, 1),
		origin + Vector2i(1, 1),
	]
	var sum := Vector2.ZERO
	for i in cells.size():
		var cell: Vector2i = cells[i]
		restore.append({
			"cell": cell,
			"source": grass.get_cell_source_id(cell),
			"atlas": grass.get_cell_atlas_coords(cell),
			"alt": grass.get_cell_alternative_tile(cell),
		})
		grass.set_cell(cell, 0, PATCH_TILES[i])
		sum += grass.map_to_local(cell)
	return grass.to_global(sum / float(cells.size()))


static func restore_patch(grass: TileMapLayer, restore: Array[Dictionary]) -> void:
	if grass == null:
		restore.clear()
		return
	for item in restore:
		var cell: Vector2i = item.cell
		var source := int(item.source)
		if source == -1:
			grass.erase_cell(cell)
		else:
			grass.set_cell(cell, source, item.atlas, int(item.alt))
	restore.clear()


## A softly pulsing gold square over a painted patch, so "the glowing patch"
## really glows. Drawn under actors; freed with its parent.
static func add_glow(parent: Node, center: Vector2, size: Vector2) -> PatchGlow:
	var glow := PatchGlow.new()
	glow.size = size
	parent.add_child(glow)
	glow.global_position = center
	return glow


class PatchGlow extends Node2D:
	const GOLD := Color(1.0, 0.85, 0.3)
	var size := Vector2(64, 64)
	var _t := 0.0

	func _init() -> void:
		z_index = 1
		process_mode = Node.PROCESS_MODE_ALWAYS

	func glow_alpha() -> float:
		return 0.25 + 0.3 * (0.5 + 0.5 * sin(_t * TAU * 1.2))

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(-size * 0.5, size)
		draw_rect(r, Color(GOLD, glow_alpha()), true)
		draw_rect(r, Color(GOLD, 0.9), false, 2.0)
