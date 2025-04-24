# state_idle.gd

class_name State_Idle extends State

@onready var walk: State = $"../Walk"
@onready var attack: State = $"../Attack"

# What happens when player enters the State
func enter() -> void:
	player.update_animation("idle")
	pass

# What happens when player exits the State
func exit() -> void:
	pass

# _process update in this State
func process(_delta: float) -> State:
	if player.direction != Vector2.ZERO:
		return walk
	player.velocity = Vector2.ZERO
	return null

# physics_process update in this State
func physics(_delta: float)->State:
	return null
	
func handle_input(_event: InputEvent)-> State:
	if _event.is_action_pressed("attack"):
		return attack
	if _event.is_action_pressed("interact"):
		PlayerManager.interact_pressed.emit()
	return null
