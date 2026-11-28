# enemy_state_chase_skeleton.gd
class_name EnemyStateChaseSkeleton extends EnemyStateChase

## "Still Holding the Line": keeps the player at spear's length. Advances if
## the player retreats, backs off if crowded, and every few seconds makes a
## long straight thrust. Requires Enemy.uses_state_velocity (toggled in
## enter/exit).

## Holds this band: closer -> retreat, farther -> advance.
@export var hold_inner: float = 40.0
@export var hold_outer: float = 48.0
@export var retreat_speed_ratio: float = 0.8
@export var thrust_cooldown: float = 1.8
@export var thrust_speed: float = 72.0
@export var thrust_duration: float = 0.35
@export var recover_duration: float = 0.4

enum Phase { HOLD, THRUST, RECOVER }

var _phase: Phase = Phase.HOLD
var _phase_timer: float = 0.0
var _thrust_timer: float = 0.0


func init() -> void:
	super.init()
	_thrust_timer = thrust_cooldown * randf_range(0.5, 1.0)


func enter() -> void:
	super.enter()
	enemy.uses_state_velocity = true
	enemy.state_velocity = Vector2.ZERO
	_phase = Phase.HOLD
	_thrust_timer = thrust_cooldown * randf_range(0.8, 1.2)  # no instant thrust on re-aggro


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
		Phase.HOLD:
			_thrust_timer -= delta
			if dist > hold_outer:
				desired = to_player * chase_speed
			elif dist < hold_inner:
				desired = -to_player * chase_speed * retreat_speed_ratio
			else:
				# In the pocket: sway faintly so he reads alive, but hold ground.
				desired = to_player.rotated(PI / 2.0) * sin(Time.get_ticks_msec() * 0.002) * chase_speed * 0.15
			if _thrust_timer <= 0.0 and dist <= hold_outer + 10.0:
				_phase = Phase.THRUST
				_phase_timer = thrust_duration
		Phase.THRUST:
			_phase_timer -= delta
			desired = to_player * thrust_speed
			if _phase_timer <= 0.0:
				_phase = Phase.RECOVER
				_phase_timer = recover_duration
				_thrust_timer = thrust_cooldown * randf_range(0.8, 1.2)
		Phase.RECOVER:
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				_phase = Phase.HOLD

	var separation: Vector2 = enemy.get_separation_vector()
	if separation != Vector2.ZERO:
		desired += separation * chase_speed * 0.6
	enemy.state_velocity = desired
	var face := _facing(desired, _to_player())
	if face.length_squared() > 0.0001 and (relentless or desired.length_squared() > 1.0):
		if enemy.set_direction(face.normalized()):
			enemy.update_animation(anim_name)

	if _lost_interest(delta):
		_phase = Phase.HOLD
		return give_up_state()
	return null


func scale_reach(factor: float) -> void:
	hold_inner *= factor
	hold_outer *= factor


func can_start_ranged() -> bool:
	return _phase == Phase.HOLD
