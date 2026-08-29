# touch_controls.gd

extends CanvasLayer

@onready var mic_button = $Root/SafeArea/RightCluster/Mic
@onready var mic_touch_button = $Root/SafeArea/RightCluster/Touch_Mic
@onready var interact_button = $Root/SafeArea/RightCluster/Interact
@onready var interact_touch_button = $Root/SafeArea/RightCluster/Touch_Interact
@onready var safe_area: Control = $Root/SafeArea
@onready var left_cluster: Control = $Root/SafeArea/LeftCluster
@onready var right_cluster: Control = $Root/SafeArea/RightCluster
@onready var player_hud = $"/root/PlayerHud"  # Reference to the Player HUD for live transcription

const LEFT_CLUSTER_SIZE := Vector2(220, 220)
const RIGHT_CLUSTER_SIZE := Vector2(220, 180)
const MOBILE_SCALE_MAX := 1.35
const MOBILE_SCALE_MIN := 0.65

var mic_enabled: bool = false
var mic_restart_timer: Timer = null
var _challenge_mic_active: bool = false
var _mic_enabled_before_challenge: bool = false

func _ready() -> void:
	add_to_group("touch_controls")
	mic_button.pressed.connect(_on_mic_button_pressed)
	mic_touch_button.pressed.connect(_on_mic_touch_button_pressed)
	
	_update_mic_ui()
	print("Touch Controls Ready: Mic state initialized to: ", mic_enabled)

	# Hide certain buttons for specific levels
	var current_level := get_tree().current_scene.name
	if current_level == "02":
		_disable_arrow_buttons()
		_disable_interact_button()
	if current_level == "Playground":
		_disable_mic_button()
		_disable_interact_button()

	var viewport := get_viewport()
	if viewport:
		viewport.size_changed.connect(_apply_safe_layout)
	_apply_safe_layout()
	call_deferred("_apply_safe_layout")

	var stt = _stt_manager()
	if stt != null and stt.is_speech_available():
		stt.listening_completed.connect(_on_listening_completed)
		stt.error.connect(_on_stt_error)
	else:
		print("STT unavailable. Mic toggle will stay off.")

	# Timer for forcing mic restart if unresponsive
	mic_restart_timer = Timer.new()
	mic_restart_timer.one_shot = true
	mic_restart_timer.wait_time = 1.0
	add_child(mic_restart_timer)
	mic_restart_timer.timeout.connect(_force_mic_restart)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_apply_safe_layout()


func _apply_safe_layout() -> void:
	if safe_area == null or left_cluster == null or right_cluster == null:
		return
	var vis := MobileSafeLayout.visible_rect_design_from_viewport(get_viewport())
	var margin := MobileSafeLayout.MARGIN
	var available := vis.size.x - margin * 3.0

	safe_area.anchor_left = 0.0
	safe_area.anchor_top = 0.0
	safe_area.anchor_right = 0.0
	safe_area.anchor_bottom = 0.0
	safe_area.position = vis.position
	safe_area.size = vis.size

	var total_width := LEFT_CLUSTER_SIZE.x + RIGHT_CLUSTER_SIZE.x
	var cluster_scale := 1.0
	if available > 0.0 and total_width > 0.0:
		# Use nearly all horizontal space between the two bottom corners.
		cluster_scale = (available / total_width) * 0.98
	cluster_scale = clampf(cluster_scale, MOBILE_SCALE_MIN, MOBILE_SCALE_MAX)

	# Bottom-left: scale grows up and to the right from the corner.
	left_cluster.anchor_left = 0.0
	left_cluster.anchor_top = 1.0
	left_cluster.anchor_right = 0.0
	left_cluster.anchor_bottom = 1.0
	left_cluster.offset_left = margin
	left_cluster.offset_top = -LEFT_CLUSTER_SIZE.y - margin
	left_cluster.offset_right = margin + LEFT_CLUSTER_SIZE.x
	left_cluster.offset_bottom = -margin
	left_cluster.pivot_offset = Vector2(0.0, LEFT_CLUSTER_SIZE.y)
	left_cluster.scale = Vector2(cluster_scale, cluster_scale)

	# Bottom-right: scale grows up and to the left from the corner.
	right_cluster.anchor_left = 1.0
	right_cluster.anchor_top = 1.0
	right_cluster.anchor_right = 1.0
	right_cluster.anchor_bottom = 1.0
	right_cluster.offset_left = -margin - RIGHT_CLUSTER_SIZE.x
	right_cluster.offset_top = -RIGHT_CLUSTER_SIZE.y - margin
	right_cluster.offset_right = -margin
	right_cluster.offset_bottom = -margin
	right_cluster.pivot_offset = Vector2(RIGHT_CLUSTER_SIZE.x, RIGHT_CLUSTER_SIZE.y)
	right_cluster.scale = Vector2(cluster_scale, cluster_scale)


func _process(_delta: float) -> void:
	_align_touch_button(mic_button, mic_touch_button)
	_align_touch_button(interact_button, interact_touch_button)


func _align_touch_button(button: Control, touch: TouchScreenButton) -> void:
	if button == null or touch == null or not button.visible:
		return
	var rect := button.get_global_rect()
	touch.global_position = rect.position + rect.size / 2.0
	if touch.shape is RectangleShape2D:
		(touch.shape as RectangleShape2D).size = rect.size


func _disable_arrow_buttons() -> void:
	print("🎤 Mic-only level detected. Hiding arrow buttons.")
	if has_node("Root/SafeArea/LeftCluster/Left"): $Root/SafeArea/LeftCluster/Left.visible = false
	if has_node("Root/SafeArea/LeftCluster/Right"): $Root/SafeArea/LeftCluster/Right.visible = false
	if has_node("Root/SafeArea/LeftCluster/Up"): $Root/SafeArea/LeftCluster/Up.visible = false
	if has_node("Root/SafeArea/LeftCluster/Down"): $Root/SafeArea/LeftCluster/Down.visible = false
	if has_node("Root/SafeArea/RightCluster/Attack"): $Root/SafeArea/RightCluster/Attack.visible = false
	
func _disable_mic_button() -> void:
	if has_node("Root/SafeArea/RightCluster/Mic"): $Root/SafeArea/RightCluster/Mic.visible = false
	if has_node("Root/SafeArea/RightCluster/Touch_Mic"): $Root/SafeArea/RightCluster/Touch_Mic.visible = false
	
func _disable_interact_button() -> void:
	if has_node("Root/SafeArea/RightCluster/Interact"): $Root/SafeArea/RightCluster/Interact.visible = false
	if has_node("Root/SafeArea/RightCluster/Touch_Interact"): $Root/SafeArea/RightCluster/Touch_Interact.visible = false

func _on_mic_button_pressed() -> void:
	print("Mic button pressed.")
	_toggle_microphone()

func _on_mic_touch_button_pressed() -> void:
	print("Touch mic button pressed.")
	_toggle_microphone()

func _toggle_microphone() -> void:
	if _challenge_mic_active:
		print("Mic toggle ignored during speech challenge.")
		return
	var stt = _stt_manager()
	if stt == null or not stt.is_speech_available():
		print("STT unavailable. Mic toggle ignored.")
		mic_enabled = false
		_update_mic_ui()
		return

	mic_enabled = not mic_enabled
	print("Toggling microphone. New state: ", mic_enabled)
	if mic_enabled:
		_start_listening()
	else:
		_stop_listening()
	_update_mic_ui()

func _start_listening() -> void:
	print("Starting microphone...")
	var stt = _stt_manager()
	if stt != null and stt.is_speech_available():
		stt.listen()
	else:
		print("STT unavailable.")
		mic_enabled = false
		_update_mic_ui()

func _stop_listening() -> void:
	print("Stopping microphone...")
	var stt = _stt_manager()
	if stt != null:
		stt.stop()

func _stt_manager():
	return get_node_or_null("/root/STTManager")


func begin_challenge_mic() -> void:
	if not OS.has_feature("web"):
		return
	_challenge_mic_active = true
	_mic_enabled_before_challenge = mic_enabled
	if mic_restart_timer:
		mic_restart_timer.stop()
	_stop_listening()
	mic_enabled = true
	_update_mic_ui()


func end_challenge_mic() -> void:
	if not OS.has_feature("web"):
		return
	_challenge_mic_active = false
	mic_enabled = _mic_enabled_before_challenge
	_update_mic_ui()
	if mic_enabled:
		_start_listening()

func _on_stt_error(error_code) -> void:
	var code = error_code
	if code is String:
		code = int(code) if code.is_valid_int() else -1
	elif typeof(code) != TYPE_INT:
		code = -1
	_on_mic_error(code, str(error_code))

func _force_mic_restart() -> void:
	if _challenge_mic_active:
		return
	if mic_enabled:
		print("Forcing microphone restart...")
		_stop_listening()
		await get_tree().create_timer(0.5).timeout
		_start_listening()

func _update_mic_ui() -> void:
	print("Updating UI. Mic Enabled: ", mic_enabled)
	mic_button.text = "Mic On" if mic_enabled else "Mic Off"

func _on_listening_completed(transcription: String) -> void:
	if _challenge_mic_active:
		return
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
	if _challenge_mic_active:
		return
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
