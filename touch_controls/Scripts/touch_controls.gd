# touch_controls.gd

extends CanvasLayer

@onready var mic_button = $Mic
@onready var mic_touch_button = $Touch_Mic
@onready var player_hud = $"/root/PlayerHud"  # Reference to the Player HUD for live transcription

var mic_enabled: bool = false  
var mic_restart_timer: Timer = null  

func _ready() -> void:
	mic_button.pressed.connect(_on_mic_button_pressed)
	mic_touch_button.pressed.connect(_on_mic_touch_button_pressed)
	
	_update_mic_ui()
	print("Touch Controls Ready: Mic state initialized to: ", mic_enabled)

	# Hide certain buttons for specific levels
	var current_level := get_tree().current_scene.name
	if current_level == "02":
		#_disable_arrow_buttons()
		_disable_interact_button()
	if current_level == "Playground":
		_disable_mic_button()
		_disable_interact_button()
	

	if Engine.has_singleton("SpeechToText"):
		var STT = Engine.get_singleton("SpeechToText")
		STT.connect("listening_completed", _on_listening_completed)
		if STT.has_signal("error_occurred"):
			STT.connect("error_occurred", Callable(self, "_on_mic_error"))
		else:
			print("Warning: SpeechToText has no 'error_occurred' signal.")
	else:
		print("Error: SpeechToText singleton not found.")

	# Timer for forcing mic restart if unresponsive
	mic_restart_timer = Timer.new()
	mic_restart_timer.one_shot = true
	mic_restart_timer.wait_time = 1.0
	add_child(mic_restart_timer)
	mic_restart_timer.timeout.connect(_force_mic_restart)

func _disable_arrow_buttons() -> void:
	print("🎤 Mic-only level detected. Hiding arrow buttons.")
	if has_node("Left"): $Left.visible = false
	if has_node("Right"): $Right.visible = false
	if has_node("Up"): $Up.visible = false
	if has_node("Down"): $Down.visible = false
	if has_node("Attack"): $Attack.visible = false
	
func _disable_mic_button() -> void:
	if has_node("Mic"): $Mic.visible = false
	if has_node("Touch_Mic"): $Touch_Mic.visible = false
	
func _disable_interact_button() -> void:
	if has_node("Interact"): $Interact.visible = false
	if has_node("Touch_Interact"): $Touch_Interact.visible = false

func _on_mic_button_pressed() -> void:
	print("Mic button pressed.")
	_toggle_microphone()

func _on_mic_touch_button_pressed() -> void:
	print("Touch mic button pressed.")
	_toggle_microphone()

func _toggle_microphone() -> void:
	mic_enabled = not mic_enabled  
	print("Toggling microphone. New state: ", mic_enabled)
	if mic_enabled:
		_start_listening()
	else:
		_stop_listening()
	_update_mic_ui()

func _start_listening() -> void:
	print("Starting microphone...")
	if Engine.has_singleton("SpeechToText"):
		Engine.get_singleton("SpeechToText").listen()
	else:
		print("Error: SpeechToText singleton not found.")

func _stop_listening() -> void:
	print("Stopping microphone...")
	if Engine.has_singleton("SpeechToText"):
		Engine.get_singleton("SpeechToText").stop()

func _force_mic_restart() -> void:
	if mic_enabled:
		print("Forcing microphone restart...")
		_stop_listening()
		await get_tree().create_timer(0.5).timeout
		_start_listening()

func _update_mic_ui() -> void:
	print("Updating UI. Mic Enabled: ", mic_enabled)
	mic_button.text = "Mic On" if mic_enabled else "Mic Off"

func _on_listening_completed(transcription: String) -> void:
	print("Mic transcription received: ", transcription)
	if player_hud:
		player_hud.update_live_transcript(transcription)  

	var recognized_commands = ["move forward", "move backward", "move left", "move right", "attack"]
	for command in recognized_commands:
		if transcription.to_lower().findn(command) != -1:
			await _execute_command(command)  
			break  

	if mic_enabled:
		mic_restart_timer.start()

func _on_mic_error(error_code: int, error_message: String) -> void:
	print("Microphone error occurred: ", error_message, " (Code: ", error_code, ")")
	if error_code == 7:
		print("Error 7 detected: Ignoring and forcing mic restart...")
		_force_mic_restart()  
	else:
		if mic_enabled:
			mic_restart_timer.start()

func _execute_command(command: String) -> void:
	if PlayerManager.player == null:
		print("Error: PlayerManager.player is null")
		return

	var is_facing_south = PlayerManager.player.cardinal_direction == Vector2.DOWN

	match command:
		"move forward":
			await PlayerManager.player.move_with_animation(PlayerManager.player.cardinal_direction)
		"move backward":
			await PlayerManager.player.move_with_animation(-PlayerManager.player.cardinal_direction)
		"move left":
			if is_facing_south:
				await PlayerManager.player.move_with_animation(Vector2.LEFT)
			else:
				await PlayerManager.player.move_with_animation(PlayerManager.player.cardinal_to_relative(Vector2.LEFT))
		"move right":
			if is_facing_south:
				await PlayerManager.player.move_with_animation(Vector2.RIGHT)
			else:
				await PlayerManager.player.move_with_animation(PlayerManager.player.cardinal_to_relative(Vector2.RIGHT))
		"attack":
			PlayerManager.player.attack_with_animation()
		_:
			print("Unknown command: ", command)
