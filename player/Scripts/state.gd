class_name State extends Node

# Reference to player that this state belongs to
static var player: Player
static var state_machine: PlayerStateMachine

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	pass # Replace with function body.

func init() -> void:
	pass


# What happens when player enters the State
func enter() -> void:
	pass

# What happens when player exits the State
func exit() -> void:
	pass

# _process update in this State
func process(_delta: float) -> State:
	return null

# physics_process update in this State
func physics(_delta: float)->State:
	return null
	
func handle_input(_event: InputEvent)-> State:
	return null
