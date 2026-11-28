class_name State extends Node

# Reference to player that this state belongs to
static var player: Player
static var state_machine: PlayerStateMachine


## Frame-rate independent smoothing, tuned at 60 fps so the feel there is
## unchanged. Displays run at 60/90/120/144 Hz or vary, and per-frame
## smoothing would otherwise behave differently on each.
## Per-frame `v -= v * per_second * delta` at 60 fps, as a factor for any delta.
## Never negative, so a long frame cannot reverse the velocity.
static func decay_factor(per_second: float, delta: float) -> float:
	return pow(maxf(0.0, 1.0 - per_second / 60.0), delta * 60.0)


## A lerp weight that moves as far per second as `per_frame_at_60` does per
## 60 fps frame.
static func turn_weight(per_frame_at_60: float, delta: float) -> float:
	return 1.0 - pow(maxf(0.0, 1.0 - per_frame_at_60), delta * 60.0)

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
