# enemy_state_chase_bandit.gd
class_name EnemyStateChaseBandit extends EnemyStateChase

## "The Exit Strategy": orbits the player at mid range, strafing, then darts
## straight in for a quick slash and darts back out. No telegraph — the circling
## IS the read. Requires Enemy.uses_state_velocity (toggled in enter/exit).

@export var orbit_inner: float = 52.0
@export var orbit_outer: float = 64.0
## Speed of the dart-in lunge (px/s).
@export var dart_speed: float = 78.0
## Seconds between dart-ins. Re-armed with ±30% jitter after each dart; the
## first dart after entering chase always waits at least 80% of this, so a
## re-aggro can't lunge instantly.
@export var dart_cooldown: float = 1.8
@export var dart_duration: float = 0.45
@export var retreat_duration: float = 0.5

enum Phase { ORBIT, DART_IN, RETREAT }

var _phase: Phase = Phase.ORBIT
var _phase_timer: float = 0.0
var _dart_timer: float = 0.0
var _strafe_sign: float = 1.0


func init() -> void:
	super.init()
	_dart_timer = dart_cooldown * randf_range(0.5, 1.0)


func enter() -> void:
	super.enter()
	enemy.uses_state_velocity = true
	enemy.state_velocity = Vector2.ZERO
	_phase = Phase.ORBIT
	_dart_timer = dart_cooldown * randf_range(0.8, 1.2)  # no instant dart on re-aggro


func exit() -> void:
	enemy.uses_state_velocity = false
	enemy.state_velocity = Vector2.ZERO
	super.exit()


func process(delta: float) -> EnemyState:
	var target_pos: Vector2 = enemy.get_chase_target_position()
	var to_player: Vector2 = enemy.global_position.direction_to(target_pos)
	var dist: float = enemy.global_position.distance_to(target_pos)

	var desired: Vector2 = Vector2.ZERO
	match _phase:
		Phase.ORBIT:
			_dart_timer -= delta
			var radial: Vector2 = Vector2.ZERO
			if dist > orbit_outer:
				radial = to_player
			elif dist < orbit_inner:
				radial = -to_player
			var tangent: Vector2 = to_player.rotated(PI / 2.0) * _strafe_sign
			desired = radial * 1.2 + tangent * 0.9
			if desired.length_squared() > 0.0001:
				desired = desired.normalized() * chase_speed
			if _dart_timer <= 0.0 and dist <= orbit_outer + 8.0:
				_phase = Phase.DART_IN
				_phase_timer = dart_duration
		Phase.DART_IN:
			_phase_timer -= delta
			desired = to_player * dart_speed
			if _phase_timer <= 0.0 or dist < 22.0:
				_phase = Phase.RETREAT
				_phase_timer = retreat_duration
				_dart_timer = dart_cooldown * randf_range(0.7, 1.3)
				if randi() % 3 == 0:
					_strafe_sign = -_strafe_sign
		Phase.RETREAT:
			_phase_timer -= delta
			desired = -to_player * chase_speed * 0.9 \
				+ to_player.rotated(PI / 2.0) * _strafe_sign * chase_speed * 0.5
			if _phase_timer <= 0.0:
				_phase = Phase.ORBIT

	var separation: Vector2 = enemy.get_separation_vector()
	if separation != Vector2.ZERO:
		desired += separation * chase_speed * 0.8
	enemy.state_velocity = desired
	if desired.length_squared() > 1.0:
		if enemy.set_direction(desired.normalized()):
			enemy.update_animation(anim_name)

	# Lose interest (same semantics as base chase)
	if _can_see_player == false:
		_timer -= delta
		if _timer < 0:
			_phase = Phase.ORBIT
			return next_state
	else:
		_timer = state_aggro_duration
	return null
