class_name EnemyStateChase extends EnemyState

@export var anim_name: String = "chase"
@export var chase_speed: float = 40.0
@export var turn_rate: float = 0.25

@export_category("AI")

# Wander State durations
@export var state_aggro_duration: float = 0.5
@export var vision_area: VisionArea
@export var attack_area: HurtBox
@export var next_state: EnemyState

## Bosses: never lose interest, always face the player, and move by
## state_velocity (set by Enemy._make_relentless).
var relentless: bool = false

var _timer: float = 0.0
var _direction: Vector2
var _can_see_player: bool = false
## Where the player was when last in sight; a horde Search heads there.
var _last_seen: Vector2 = Vector2.ZERO

func init() -> void:
	if vision_area:
		vision_area.player_entered.connect(_on_player_enter)
		vision_area.player_exited.connect(_on_player_exit)

	pass

func enter() -> void:
	_timer = state_aggro_duration
	var p := PlayerManager.player
	if p:
		_last_seen = p.global_position

	enemy.update_animation(anim_name)
	if attack_area:
		attack_area.monitoring = true
	if relentless:
		enemy.uses_state_velocity = true

func exit() -> void:
	if relentless:
		enemy.uses_state_velocity = false
		enemy.state_velocity = Vector2.ZERO
	if attack_area:
		attack_area.monitoring = false
	_can_see_player = false
	
	pass

func process(_delta: float) -> EnemyState:
	var target_pos: Vector2 = enemy.get_chase_target_position()
	var new_dir: Vector2 = enemy.global_position.direction_to(target_pos)
	var separation: Vector2 = enemy.get_separation_vector()
	if separation != Vector2.ZERO:
		new_dir = (new_dir + separation * 1.6).normalized()
	# Lerping between opposite headings normalises straight back to the old
	# one, so a target dead behind would never be turned toward. Nudge it.
	if _direction.dot(new_dir) < -0.99:
		_direction = _direction.rotated(0.2)
	_direction = lerp(_direction, new_dir, State.turn_weight(turn_rate, _delta))
	if _direction.length_squared() > 0.0001:
		_direction = _direction.normalized()
	enemy.velocity = _direction * chase_speed
	# Only read when uses_state_velocity is on (bosses); others move by direction.
	enemy.state_velocity = _direction * chase_speed
	if enemy.set_direction(_facing(_direction, _to_player())):
		enemy.update_animation(anim_name)
	if _lost_interest(_delta):
		return give_up_state()
	return null

func physics(_delta: float) -> EnemyState:
	return null


## Out of sight for state_aggro_duration -> give up. Bosses never do.
func _lost_interest(delta: float) -> bool:
	if relentless:
		return false
	if not _can_see_player:
		_timer -= delta
		return _timer < 0
	_timer = state_aggro_duration
	var p := PlayerManager.player
	if p:
		_last_seen = p.global_position
	return false


## Where to go after losing interest: in a horde arena, search the last-seen
## spot first; elsewhere (tutorial levels) straight to next_state as before.
func give_up_state() -> EnemyState:
	if enemy.horde_arena() == null:
		return next_state
	var search := enemy._ensure_search()
	search.next_state = next_state
	search.last_seen = _last_seen
	return search


## Which way to face: bosses watch the player, others face where they move.
func _facing(move: Vector2, to_player: Vector2) -> Vector2:
	if relentless and to_player != Vector2.ZERO:
		return to_player
	return move


func _to_player() -> Vector2:
	var p := PlayerManager.player
	if p == null:
		return Vector2.ZERO
	return enemy.global_position.direction_to(p.global_position)


## A straight, unobstructed line to the player (always true outside an arena).
func _line_to_player_clear() -> bool:
	var arena := enemy.horde_arena()
	var p := PlayerManager.player
	if arena == null or p == null:
		return true
	return arena.line_clear(enemy.global_position, p.global_position, Enemy.BOSS_CLEARANCE)


## Grows the distance bands for a bigger body (bosses). Base chase has none.
func scale_reach(_factor: float) -> void:
	pass


## BossRangedAttack only winds up while this is true (the neutral phase).
func can_start_ranged() -> bool:
	return true


func _on_player_enter() -> void:
	_can_see_player = true
	if state_machine.current_state is EnemyStateStun:
		return
	if state_machine.current_state is EnemyStateDestroy:
		return
	if state_machine.current_state == self:
		return
	state_machine.change_state(self)
	pass
	
func _on_player_exit() -> void:
	_can_see_player = false
	pass
