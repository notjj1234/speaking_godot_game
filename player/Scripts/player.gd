class_name Player extends CharacterBody2D

var player_hud: PlayerHudUI = null  # Explicitly set the type to PlayerHudUI

signal direction_changed(new_direction: Vector2)
signal player_damaged(hurt_box: HurtBox)

const DIR_4 = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]

var cardinal_direction: Vector2 = Vector2.DOWN
var direction: Vector2 = Vector2.ZERO

var invulnerable: bool = false
var hp: int = 6
var max_hp: int = 6

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var effect_animation_player: AnimationPlayer = $EffectAnimationPlayer
@onready var sprite: Sprite2D = $Sprite2D
@onready var state_machine: PlayerStateMachine = $StateMachine
@onready var hit_box: HitBox = $HitBox

func _ready() -> void:
	PlayerManager.player = self
	state_machine.Initialize(self)
	hit_box.damaged.connect(_take_damage)
	update_hp(99)  # Initialize HUD with current HP

func _process(_delta: float) -> void:
	direction = Vector2(
		Input.get_axis("left", "right"),
		Input.get_axis("up", "down"),
	)

func _physics_process(_delta: float) -> void:
	move_and_slide()

func set_direction(force_update: bool = false) -> bool:
	if direction == Vector2.ZERO and not force_update:
		return false

	var new_dir = cardinal_direction
	if direction != Vector2.ZERO:
		var input_dir = direction.normalized()

		if abs(input_dir.x) > abs(input_dir.y):
			new_dir = Vector2.LEFT if input_dir.x < 0 else Vector2.RIGHT
		else:
			new_dir = Vector2.UP if input_dir.y < 0 else Vector2.DOWN

	if new_dir == cardinal_direction and not force_update:
		return false

	cardinal_direction = new_dir
	direction_changed.emit(new_dir)
	sprite.scale.x = -1 if cardinal_direction == Vector2.LEFT else 1
	return true

func update_animation(state: String) -> void:
	if animation_player.current_animation != (state + "_" + anim_direction()):
		animation_player.play(state + "_" + anim_direction())

func anim_direction() -> String:
	if cardinal_direction == Vector2.DOWN:
		return "down"
	elif cardinal_direction == Vector2.UP:
		return "up"
	else:
		return "side"

func _take_damage(hurt_box: HurtBox) -> void:
	if invulnerable:
		return
	update_hp(-hurt_box.damage)

	if hp > 0:
		player_damaged.emit(hurt_box)
	else:
		player_damaged.emit(hurt_box)
		update_hp(99)

func update_hp(delta: int) -> void:
	hp = clampi(hp + delta, 0, max_hp)
	if player_hud != null:
		player_hud.update_hp(hp, max_hp)

func make_invulnerable(_duration: float = 1.0) -> void:
	invulnerable = true
	hit_box.monitoring = false
	await get_tree().create_timer(_duration).timeout
	invulnerable = false
	hit_box.monitoring = true

func move_with_animation(direction_vector: Vector2) -> void:
	direction = direction_vector.normalized()
	set_direction(true)

	var walk_state = state_machine.get_node("Walk")
	var idle_state = state_machine.get_node("Idle")
	
	if walk_state and idle_state:
		state_machine.change_state(walk_state)
		update_animation("walk")  

		var distance = 128  # Total movement distance
		var step = 4       # Distance per frame
		var steps = int(distance / step)

		for i in range(steps):
			position += direction_vector * step
			update_animation("walk")  
			await get_tree().create_timer(0.05).timeout  

		state_machine.change_state(idle_state)
		update_animation("idle")
	else:
		print("Error: State machine missing 'Walk' or 'Idle' state.")

func attack_with_animation() -> void:
	var attack_state = state_machine.get_node("Attack")
	if attack_state:
		state_machine.change_state(attack_state)
	else:
		print("Error: State machine missing 'Attack' state.")

func cardinal_to_relative(direction: Vector2) -> Vector2:
	match cardinal_direction:
		Vector2.UP:
			return Vector2.LEFT if direction == Vector2.LEFT else Vector2.RIGHT
		Vector2.DOWN:
			return Vector2.RIGHT if direction == Vector2.LEFT else Vector2.LEFT
		Vector2.RIGHT:
			return Vector2.UP if direction == Vector2.LEFT else Vector2.DOWN
		Vector2.LEFT:
			return Vector2.DOWN if direction == Vector2.LEFT else Vector2.UP
	return Vector2.ZERO
