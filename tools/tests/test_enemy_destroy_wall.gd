extends Node2D
## F03 regression: an enemy killed beside a wall must still play its one-shot
## destroy animation to the end and free itself. Before the fix, slide-collision
## bouncing swapped it for a looping walk: an immortal enemy, and an Endless
## Horde stage that could never clear. Run headless on a scratch copy:
##   Godot --headless --path <copy> res://tools/tests/test_enemy_destroy_wall.tscn

const KINDS := [
	"res://enemies/slime/slime.tscn",
	"res://enemies/goblin/goblin.tscn",
	"res://enemies/beetle/beetle.tscn",
	"res://enemies/orc/orc.tscn",
]
const WALL_LAYER := 16  # "Walls", the only layer enemies collide with
const START := Vector2(1000, 500)
const HIT_FROM := Vector2(1100, 420)  # up-right of the enemy, beyond the wall
const FREE_WITHIN_SEC := 1.5

var passes := 0
var failures := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _add_wall(holder: Node2D) -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = WALL_LAYER
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 400)
	shape.shape = rect
	wall.add_child(shape)
	wall.position = START + Vector2(22, 0)
	holder.add_child(wall)


func _run_case(scene_path: String, with_wall: bool) -> void:
	var label := "%s wall=%s" % [scene_path.get_file().get_basename(), with_wall]
	var holder := Node2D.new()
	add_child(holder)
	if with_wall:
		_add_wall(holder)
	var enemy: Enemy = load(scene_path).instantiate()
	enemy.chaos_pauses_enabled = false
	holder.add_child(enemy)
	enemy.global_position = START
	await get_tree().physics_frame
	var hit := HurtBox.new()
	holder.add_child(hit)
	hit.global_position = HIT_FROM
	enemy.enemy_destroyed.emit(hit)
	var non_destroy: Array[String] = []
	var moved_away := false
	var elapsed := 0.0
	while elapsed < FREE_WITHIN_SEC and is_instance_valid(enemy):
		await get_tree().physics_frame
		elapsed += 1.0 / Engine.physics_ticks_per_second
		if not is_instance_valid(enemy):
			break
		var anim := String(enemy.animation_player.current_animation)
		if anim != "" and not anim.begins_with("destroy") and not non_destroy.has(anim):
			non_destroy.append(anim)
		if enemy.global_position.distance_to(HIT_FROM) > START.distance_to(HIT_FROM) + 1.0:
			moved_away = true
	_check(label + ": freed after destroy animation", not is_instance_valid(enemy),
			"still alive after %.1fs" % FREE_WITHIN_SEC)
	_check(label + ": only destroy animations played", non_destroy.is_empty(), str(non_destroy))
	if not with_wall:
		_check(label + ": knocked back away from the hit", moved_away)
	holder.queue_free()
	await get_tree().process_frame


func _ready() -> void:
	for kind in KINDS:
		await _run_case(kind, false)
		await _run_case(kind, true)
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
