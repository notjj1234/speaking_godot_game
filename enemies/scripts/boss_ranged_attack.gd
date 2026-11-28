class_name BossRangedAttack
extends Node

## A boss's ranged attack. Lives at EnemyStateMachine/Ranged so the boss tune
## ("Ranged/cooldown": f) reaches it; the machine ignores it (not an EnemyState).
## While the player is in range with a clear line, the cooldown runs down;
## at the Chase's next neutral phase the boss stops and flashes (wind-up) and
## throws a fan aimed where the player stands. No lead, so a
## sidestep always dodges. Timers use delta, so every refresh rate plays alike.

const FLASH := Color(1.7, 1.15, 1.05)
## Shots only need a thin clear line; the body needs Enemy.BOSS_CLEARANCE.
const SHOT_CLEARANCE := 4.0
## Shots leave from the edge of the body at chest height (not the feet, where
## they read as spots on the boss) and aim at the player's HitBox height.
const LAUNCH_EDGE := 18.0
const LAUNCH_HEIGHT := 12.0
const PLAYER_HITBOX_HEIGHT := 11.0

@export var shape: StringName = &"glob"
@export var count: int = 1
@export var count_step: int = 0
@export var spread_deg: float = 0.0
@export var speed: float = 100.0
@export var cooldown: float = 3.0
@export var windup: float = 0.5
@export var min_range: float = 40.0
@export var max_range: float = 260.0
@export var lifetime: float = 3.0

var enemy: Enemy
var _cooldown_left: float = 0.0
var _winding: bool = false
var _windup_left: float = 0.0
var _flash: Tween


## Copies a HordeCurve "ranged" profile onto the exported settings.
func configure(profile: Dictionary) -> void:
	for key in profile:
		if get(key) != null:
			set(key, profile[key])


func _ready() -> void:
	enemy = get_parent().get_parent() as Enemy
	_cooldown_left = cooldown
	if enemy:
		enemy.enemy_damaged.connect(func(_hb: HurtBox): cancel())


func _physics_process(delta: float) -> void:
	if enemy == null or enemy.dying:
		cancel()
		return
	var chase := enemy.state_machine.current_state as EnemyStateChase
	var target := PlayerManager.player
	if chase == null or target == null:
		cancel()
		return
	if _winding and not chase.can_start_ranged():
		cancel()
		return
	if _winding:
		_windup_left -= delta
		_face(chase, target.global_position)
		if _windup_left <= 0.0:
			if _line_clear(target.global_position):
				_fire(target.global_position)
			cancel()
			_cooldown_left = cooldown * randf_range(0.8, 1.2)
		return
	var dist := enemy.global_position.distance_to(target.global_position)
	if dist > max_range or not _line_clear(target.global_position):
		return
	# The cooldown runs through melee moves and contact too (an orc charges
	# often, a slime hugs); the wind-up waits for the chase's neutral phase
	# and a little room, so a point-blank volley never happens.
	_cooldown_left -= delta
	if _cooldown_left <= 0.0 and dist >= min_range and chase.can_start_ranged():
		_start_windup()


## Phase change: nothing in flight, no wind-up, full cooldown.
func reset() -> void:
	for p in projectiles():
		p.queue_free()
	cancel()
	_cooldown_left = cooldown


func cancel() -> void:
	if not _winding:
		return
	_winding = false
	if enemy:
		enemy.attack_hold = false
	if _flash and _flash.is_valid():
		_flash.kill()
	_flash = null
	if enemy and enemy.sprite:
		enemy.sprite.modulate = Color.WHITE


func projectiles() -> Array[BossProjectile]:
	var out: Array[BossProjectile] = []
	if enemy == null:
		return out
	for child in enemy.get_children():
		if child is BossProjectile and not child.is_queued_for_deletion():
			out.append(child)
	return out


func _start_windup() -> void:
	_winding = true
	_windup_left = windup
	enemy.attack_hold = true
	if enemy.sprite:
		_flash = enemy.sprite.create_tween()
		_flash.set_loops()
		_flash.tween_property(enemy.sprite, "modulate", FLASH, 0.1)
		_flash.tween_property(enemy.sprite, "modulate", Color.WHITE, 0.1)


func _fire(at: Vector2) -> void:
	var shots := maxi(1, count + count_step * enemy.boss_phase)
	var chest := enemy.global_position + Vector2(0.0, -LAUNCH_HEIGHT)
	var aim := chest.direction_to(at + Vector2(0.0, -PLAYER_HITBOX_HEIGHT))
	var body_hurt := enemy.get_node_or_null("HurtBox") as HurtBox
	var dmg := body_hurt.damage if body_hurt else 1
	for i in shots:
		var t := 0.5 if shots == 1 else float(i) / float(shots - 1)
		var dir := aim.rotated(deg_to_rad(lerpf(-spread_deg, spread_deg, t) * 0.5))
		var shot := BossProjectile.new()
		shot.setup(shape, dir * speed, dmg, lifetime)
		enemy.add_child(shot)
		shot.global_position = chest + aim * LAUNCH_EDGE
		shot.reset_physics_interpolation()
	print("✅ %s: ranged volley of %d" % [enemy.boss_name, shots])


func _face(chase: EnemyStateChase, at: Vector2) -> void:
	if enemy.set_direction(enemy.global_position.direction_to(at)):
		enemy.update_animation(chase.anim_name)


func _line_clear(at: Vector2) -> bool:
	var arena := enemy.horde_arena()
	if arena == null:
		return true
	return arena.line_clear(enemy.global_position, at, SHOT_CLEARANCE)
