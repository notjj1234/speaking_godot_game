# enemy_state_chase_orc.gd
class_name EnemyStateChaseOrc extends EnemyStateChase

## "The Siege Engine": stalks slowly, then stops, telegraphs (flash + shake),
## and charges in a straight line. A wall (or the charge timing out) staggers
## him. Requires Enemy.uses_state_velocity (toggled in enter/exit) and
## Enemy.slide_bounce_enabled = false on the scene (wall contact is the
## stagger trigger, not a bounce).

@export var stalk_speed: float = 22.0
## Charge fires while the player is inside this band.
@export var charge_min_range: float = 56.0
@export var charge_max_range: float = 88.0
@export var telegraph_duration: float = 0.7
@export var charge_speed: float = 110.0
@export var charge_max_duration: float = 0.9
@export var stagger_duration: float = 0.9
@export var charge_cooldown: float = 1.2

const TELEGRAPH_FLASH := Color(1.7, 1.15, 1.05)

enum Phase { STALK, TELEGRAPH, CHARGE, STAGGER }

var _phase: Phase = Phase.STALK
var _phase_timer: float = 0.0
var _cooldown: float = 0.0
var _charge_dir: Vector2 = Vector2.ZERO
var _flash_tween: Tween


func enter() -> void:
	super.enter()
	enemy.uses_state_velocity = true
	enemy.state_velocity = Vector2.ZERO
	_phase = Phase.STALK
	_cooldown = charge_cooldown * 0.5


func exit() -> void:
	_stop_flash()
	enemy.uses_state_velocity = false
	enemy.state_velocity = Vector2.ZERO
	super.exit()


func process(delta: float) -> EnemyState:
	var target_pos: Vector2 = enemy.get_chase_target_position()
	var to_player: Vector2 = enemy.global_position.direction_to(target_pos)
	var dist: float = enemy.global_position.distance_to(target_pos)

	var desired: Vector2 = Vector2.ZERO
	match _phase:
		Phase.STALK:
			_cooldown -= delta
			desired = to_player * stalk_speed
			if enemy.set_direction(_facing(to_player, _to_player())):
				enemy.update_animation(anim_name)
			# A boss following a path round a prop must not charge into it.
			var lined_up := not relentless or _line_to_player_clear()
			if _cooldown <= 0.0 and dist >= charge_min_range and dist <= charge_max_range and lined_up:
				_phase = Phase.TELEGRAPH
				_phase_timer = telegraph_duration
				desired = Vector2.ZERO  # stop dead on the transition frame
				_start_flash()
		Phase.TELEGRAPH:
			_phase_timer -= delta
			# Face the player during the wind-up, but hold position.
			if enemy.set_direction(_facing(to_player, _to_player())):
				enemy.update_animation(anim_name)
			_shake()
			if _phase_timer <= 0.0:
				_stop_flash()
				_charge_dir = to_player.normalized()
				_phase = Phase.CHARGE
				_phase_timer = charge_max_duration
		Phase.CHARGE:
			_phase_timer -= delta
			desired = _charge_dir * charge_speed
			if enemy.set_direction(_charge_dir):
				enemy.update_animation(anim_name)
			if enemy.is_on_wall() or _phase_timer <= 0.0:
				_phase = Phase.STAGGER
				_phase_timer = stagger_duration
				desired = Vector2.ZERO  # kill the charge momentum on the transition frame
		Phase.STAGGER:
			_phase_timer -= delta
			_shake()
			# Dazed, but a boss still keeps its eyes on the player.
			if relentless and enemy.set_direction(_to_player()):
				enemy.update_animation(anim_name)
			if _phase_timer <= 0.0:
				_stop_flash()  # clears the shake jitter, not just the flash
				_phase = Phase.STALK
				_cooldown = charge_cooldown * randf_range(0.8, 1.2)

	if _phase != Phase.TELEGRAPH and _phase != Phase.STAGGER and _phase != Phase.CHARGE:
		var separation: Vector2 = enemy.get_separation_vector()
		if separation != Vector2.ZERO:
			desired += separation * stalk_speed * 0.5
	enemy.state_velocity = desired

	if _lost_interest(delta):
		_stop_flash()
		_phase = Phase.STALK
		return give_up_state()
	return null


func _start_flash() -> void:
	if enemy.sprite == null:
		return
	_flash_tween = enemy.sprite.create_tween()
	_flash_tween.set_loops()
	_flash_tween.tween_property(enemy.sprite, "modulate", TELEGRAPH_FLASH, 0.12)
	_flash_tween.tween_property(enemy.sprite, "modulate", Color.WHITE, 0.12)


func _stop_flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null
	if enemy.sprite:
		enemy.sprite.modulate = Color.WHITE
		enemy.sprite.position = Vector2(0, -14)


func _shake() -> void:
	if enemy.sprite == null:
		return
	var jx: float = randf_range(-1.0, 1.0)
	enemy.sprite.position = Vector2(jx, -14)


func scale_reach(factor: float) -> void:
	charge_min_range *= factor
	charge_max_range *= factor


func can_start_ranged() -> bool:
	return _phase == Phase.STALK
