class_name State_Walk extends State

@export var move_speed : float = 100.0
@onready var attack: State_Attack = $"../Attack"

@onready var idle: State = $"../Idle"

func enter() -> void:
	player.update_animation("walk")

func exit() -> void:
	pass

func process(delta: float) -> State:
	# If there's movement, update velocity
	if player.direction != Vector2.ZERO:
		player.velocity = player.direction * move_speed
		if player.set_direction():
			player.update_animation("walk")
	else:
		return idle  # Switch to idle when not moving
	
	return null

func physics(_delta: float)->State:
	return null
	
func handle_input(_event: InputEvent)-> State:
	if _event.is_action_pressed("attack"):
		return attack
	if _event.is_action_pressed("interact"):
		PlayerManager.interact_pressed.emit()
	return null
