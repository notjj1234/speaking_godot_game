class_name EnemyStateSearch extends EnemyState
## Lost sight of the player in a horde arena: walk to where they were last seen
## (pathing around walls and props), stop and look in all four directions,
## then give up to next_state. Seeing the player again at any point switches
## back to Chase (EnemyStateChase._on_player_enter works from any state).
## Built in code by Enemy._ensure_search; never placed in a scene.

const ARRIVE_DISTANCE := 10.0
const LOOK_STEP_SEC := 0.35
## Can't get there (blocked, pushed around): look around where it stands.
const WALK_LIMIT_SEC := 6.0
## Walks a little slower than it chases.
const SEARCH_PACE := 0.8

var anim_name: String = "walk"
var next_state: EnemyState
var last_seen: Vector2 = Vector2.ZERO

var _looking := false
var _look_left := 0.0
var _looks_done := 0
var _walked := 0.0


func enter() -> void:
	_looking = false
	_looks_done = 0
	_walked = 0.0
	enemy.update_animation(anim_name)


func exit() -> void:
	_looking = false


func process(delta: float) -> EnemyState:
	if not _looking:
		_walked += delta
		if enemy.global_position.distance_to(last_seen) <= ARRIVE_DISTANCE or _walked >= WALK_LIMIT_SEC:
			_start_looking()
		else:
			var target := enemy.pursuit_target(last_seen)
			var dir := enemy.global_position.direction_to(target)
			dir = (dir + enemy.get_separation_vector()).normalized()
			if enemy.set_direction(dir * SEARCH_PACE):
				enemy.update_animation(anim_name)
		return null
	_look_left -= delta
	if _look_left > 0.0:
		return null
	if _looks_done >= 4:
		return next_state
	_turn()
	return null


func _start_looking() -> void:
	_looking = true
	_looks_done = 0
	_look_left = 0.0


## Quarter turn, standing still (the vision cone follows the facing).
func _turn() -> void:
	var facing := enemy.cardinal_direction.rotated(PI * 0.5) if _looks_done > 0 else enemy.cardinal_direction
	enemy.set_direction(facing.round())
	enemy.direction = Vector2.ZERO
	enemy.update_animation("idle")
	_looks_done += 1
	_look_left = LOOK_STEP_SEC
