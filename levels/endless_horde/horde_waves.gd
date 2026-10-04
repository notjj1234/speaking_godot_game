extends Level

const WAVE_COUNT := 10
const START_DELAY := 1.0
const SPAWN_RADIUS := 96.0
const MIN_SPACING := 48.0
const BOUNDS_INSET := 64.0
const MIN_PLAYER_DISTANCE := 48.0
const PICKUP_PULL_SPEED := 280.0
const PICKUP_COLLECT_DISTANCE := 18.0
const WALLS_LAYER := 16

const NORMAL_HP := 6

const SLIME := preload("res://enemies/slime/slime.tscn")
const GOBLIN := preload("res://enemies/goblin/goblin.tscn")
const BEETLE := preload("res://enemies/beetle/beetle.tscn")
const START_FONT := preload("res://gui/fonts/Abaddon Bold.ttf")

var _wave := 0
var _awaiting_clear := false
var _finished := false
var _practice := true
var _start_pad: Node2D
var _pad_restore: Array[Dictionary] = []

@onready var _enemies: Node2D = $HordeEnemies
@onready var _label: Label = $WaveLayer/WaveLabel
@onready var _grass: TileMapLayer = $"Grass-01"
@onready var _start_timer: Timer = $StartTimer


func _ready() -> void:
	super()
	PlayerManager.revive_for_horde()
	_add_top_barrier()
	_label.text = "Wave 0"
	_spawn_practice_dummy()
	_spawn_start_pad()


func _free_level() -> void:
	PlayerManager.set_health(NORMAL_HP, NORMAL_HP)
	super()


func _process(delta: float) -> void:
	if get_tree().paused or _finished or not _awaiting_clear:
		return
	if _enemy_count() > 0:
		return
	var pickups := _pickups()
	if not pickups.is_empty():
		_pull_pickups(pickups, delta)
		return
	_awaiting_clear = false
	if _wave >= WAVE_COUNT:
		_finished = true
		_label.text = "Horde cleared"
		print("✅ Horde cleared")
		return
	_spawn_wave()


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or get_tree().current_scene != self:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key_event := event as InputEventKey
	var target := _dev_wave_target(key_event)
	if target < 1:
		return
	_jump_to_wave(target)
	get_viewport().set_input_as_handled()


func _dev_wave_target(event: InputEventKey) -> int:
	var keycode := event.keycode if event.keycode != 0 else event.physical_keycode
	if keycode == KEY_BRACKETRIGHT:
		return mini(maxi(_wave, 0) + 1, WAVE_COUNT)
	if keycode == KEY_BRACKETLEFT:
		return maxi(_wave - 1, 1)
	if not event.shift_pressed:
		return -1
	match keycode:
		KEY_1:
			return 1
		KEY_2:
			return 2
		KEY_3:
			return 3
		KEY_4:
			return 4
		KEY_5:
			return 5
		KEY_6:
			return 6
		KEY_7:
			return 7
		KEY_8:
			return 8
		KEY_9:
			return 9
		KEY_0:
			return 10
	return -1


func _jump_to_wave(target: int) -> void:
	_finished = false
	_awaiting_clear = false
	_end_practice()
	if _start_timer:
		_start_timer.stop()
	_clear_horde()
	_wave = target - 1
	print("✅ Dev skip to horde wave ", target)
	_spawn_wave()


func _spawn_practice_dummy() -> void:
	var enemy: Enemy = SLIME.instantiate()
	_enemies.add_child(enemy)
	enemy.global_position = _clamp_to_grass(_player_position() + Vector2(72, 0))
	enemy.make_practice_dummy()


func _spawn_start_pad() -> void:
	var pad_pos := _clamp_to_grass(_grass_center() + Vector2(0, 104))
	if pad_pos.distance_to(_player_position()) < 96.0:
		pad_pos = _clamp_to_grass(_player_position() + Vector2(0, 120))
	var center := _paint_start_path(pad_pos)
	var root := Node2D.new()
	root.name = "StartPad"
	root.z_index = 3
	var label := Label.new()
	label.text = "START"
	label.position = Vector2(-32, -28)
	label.size = Vector2(64, 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", START_FONT)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(label)
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(64, 64)
	shape_node.shape = shape
	area.add_child(shape_node)
	area.body_entered.connect(_on_start_pad_body)
	root.add_child(area)
	add_child(root)
	root.global_position = center
	_start_pad = root


func _paint_start_path(around: Vector2) -> Vector2:
	if _grass == null:
		return around
	var origin := _grass.local_to_map(_grass.to_local(around))
	var cells: Array[Vector2i] = [
		origin,
		origin + Vector2i(1, 0),
		origin + Vector2i(0, 1),
		origin + Vector2i(1, 1),
	]
	var patches: Array[Vector2i] = [
		Vector2i(9, 1),
		Vector2i(10, 1),
		Vector2i(9, 2),
		Vector2i(10, 2),
	]
	var sum := Vector2.ZERO
	for i in cells.size():
		var cell: Vector2i = cells[i]
		_pad_restore.append({
			"cell": cell,
			"source": _grass.get_cell_source_id(cell),
			"atlas": _grass.get_cell_atlas_coords(cell),
			"alt": _grass.get_cell_alternative_tile(cell),
		})
		_grass.set_cell(cell, 0, patches[i])
		sum += _grass.map_to_local(cell)
	return _grass.to_global(sum / float(cells.size()))


func _on_start_pad_body(body: Node) -> void:
	if not _practice or body != PlayerManager.player:
		return
	_end_practice()
	_clear_horde()
	PlayerManager.set_player_position(_grass_center())
	_wave = 0
	_awaiting_clear = false
	_finished = false
	_spawn_wave()


func _end_practice() -> void:
	_practice = false
	if _start_pad and is_instance_valid(_start_pad):
		_start_pad.queue_free()
	_start_pad = null
	_restore_start_path()


func _restore_start_path() -> void:
	if _grass == null:
		_pad_restore.clear()
		return
	for item in _pad_restore:
		var cell: Vector2i = item.cell
		var source := int(item.source)
		if source == -1:
			_grass.erase_cell(cell)
		else:
			_grass.set_cell(cell, source, item.atlas, int(item.alt))
	_pad_restore.clear()


func _grass_center() -> Vector2:
	if _grass == null:
		return global_position
	var rect := _grass.get_used_rect()
	if rect.size == Vector2i.ZERO:
		return global_position
	var min_cell := rect.position
	var max_cell := rect.position + rect.size - Vector2i.ONE
	var min_pos := _grass.to_global(_grass.map_to_local(min_cell))
	var max_pos := _grass.to_global(_grass.map_to_local(max_cell))
	return (min_pos + max_pos) * 0.5


func _clear_horde() -> void:
	for child in _enemies.get_children():
		if is_instance_valid(child):
			child.queue_free()


func _on_start_timer() -> void:
	if _finished or _wave > 0:
		return
	_spawn_wave()


func _spawn_wave() -> void:
	_wave += 1
	var count := 3 + (_wave - 1) * 2
	_label.text = "Wave %d / 10" % _wave
	print("✅ Spawning horde wave ", _wave, " (", count, " enemies)")
	var origin := _player_position()
	var radius := _ring_radius(count)
	for i in count:
		var angle := TAU * float(i) / float(count)
		var pos := origin + Vector2.RIGHT.rotated(angle) * radius
		if pos.distance_to(origin) < MIN_PLAYER_DISTANCE:
			pos = origin + Vector2.RIGHT.rotated(angle) * MIN_PLAYER_DISTANCE
		pos = _clamp_to_grass(pos)
		var enemy := _scene_for_index(i, count).instantiate()
		_enemies.add_child(enemy)
		enemy.global_position = pos
	_awaiting_clear = true


func _scene_for_index(index: int, count: int) -> PackedScene:
	if _wave <= 1:
		return SLIME
	if _wave == 2:
		return GOBLIN if index == 0 else SLIME
	if _wave <= 4:
		# Mix slime / goblin / beetle
		match index % 3:
			0:
				return GOBLIN
			1:
				return SLIME
			_:
				return BEETLE
	# Waves 5-10: mostly goblins, with slime and beetle sprinkled in
	match index % 4:
		0, 1:
			return GOBLIN
		2:
			return BEETLE
		_:
			return SLIME


func _ring_radius(count: int) -> float:
	var needed := (float(count) * MIN_SPACING) / TAU
	return maxf(SPAWN_RADIUS, needed)


func _player_position() -> Vector2:
	if PlayerManager.player:
		return PlayerManager.player.global_position
	return global_position


func _enemy_count() -> int:
	var alive := 0
	for child in _enemies.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		if child is ItemPickup:
			continue
		alive += 1
	return alive


func _pickups() -> Array[ItemPickup]:
	var found: Array[ItemPickup] = []
	for child in _enemies.get_children():
		if child is ItemPickup and is_instance_valid(child) and not child.is_queued_for_deletion():
			found.append(child)
	return found


func _pull_pickups(pickups: Array[ItemPickup], delta: float) -> void:
	var player := PlayerManager.player
	if player == null:
		return
	var dest := player.global_position
	for drop in pickups:
		if drop.has_meta("horde_collecting"):
			continue
		drop.velocity = Vector2.ZERO
		drop.global_position = drop.global_position.move_toward(dest, PICKUP_PULL_SPEED * delta)
		if drop.global_position.distance_to(dest) <= PICKUP_COLLECT_DISTANCE:
			_collect_pickup(drop)


func _collect_pickup(drop: ItemPickup) -> void:
	if drop.has_meta("horde_collecting"):
		return
	drop.set_meta("horde_collecting", true)
	var accepted := false
	if drop.item_data and PlayerManager.INVENTORY_DATA:
		accepted = PlayerManager.INVENTORY_DATA.add_item(drop.item_data)
	if accepted:
		drop.item_picked_up()
	else:
		drop.queue_free()


func _add_top_barrier() -> void:
	if _grass == null:
		return
	var rect := _grass.get_used_rect()
	if rect.size == Vector2i.ZERO:
		return
	var left_cell := rect.position
	var right_cell := rect.position + Vector2i(rect.size.x - 1, 0)
	var left := _grass.to_global(_grass.map_to_local(left_cell))
	var right := _grass.to_global(_grass.map_to_local(right_cell))
	var top_y := minf(left.y, right.y) - 16.0
	var x0 := minf(left.x, right.x) - 16.0
	var x1 := maxf(left.x, right.x) + 16.0
	var body := StaticBody2D.new()
	body.name = "TopBarrier"
	body.collision_layer = WALLS_LAYER
	body.collision_mask = 0
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(x1 - x0, 24.0)
	shape_node.shape = shape
	body.add_child(shape_node)
	add_child(body)
	body.global_position = Vector2((x0 + x1) * 0.5, top_y)


func _clamp_to_grass(pos: Vector2) -> Vector2:
	if _grass == null:
		return pos
	var rect := _grass.get_used_rect()
	if rect.size == Vector2i.ZERO:
		return pos
	var min_cell := rect.position
	var max_cell := rect.position + rect.size - Vector2i.ONE
	var min_pos := _grass.to_global(_grass.map_to_local(min_cell))
	var max_pos := _grass.to_global(_grass.map_to_local(max_cell))
	var lo := Vector2(minf(min_pos.x, max_pos.x), minf(min_pos.y, max_pos.y))
	var hi := Vector2(maxf(min_pos.x, max_pos.x), maxf(min_pos.y, max_pos.y))
	lo += Vector2(BOUNDS_INSET, BOUNDS_INSET)
	hi -= Vector2(BOUNDS_INSET, BOUNDS_INSET)
	if lo.x > hi.x:
		var mid_x := (lo.x + hi.x) * 0.5
		lo.x = mid_x
		hi.x = mid_x
	if lo.y > hi.y:
		var mid_y := (lo.y + hi.y) * 0.5
		lo.y = mid_y
		hi.y = mid_y
	return Vector2(clampf(pos.x, lo.x, hi.x), clampf(pos.y, lo.y, hi.y))
