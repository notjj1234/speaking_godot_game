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

const STRUGGLE_UNLOCK_COUNT := 3
const VOICE_COMMANDS := [
	"move forward",
	"move backwards",
	"move backward",
	"move left",
	"move right",
	"attack",
]

var mic_enabled: bool = false
var mic_restart_timer: Timer = null
var _challenge_mic_active: bool = false
var _mic_enabled_before_challenge: bool = false
var _touch_ui_enabled: bool = true
var _voice_only_mode: bool = false
var _struggle_count: int = 0
var _movement_unlocked: bool = false

func _ready() -> void:
	add_to_group("touch_controls")
	mic_button.pressed.connect(_on_mic_button_pressed)
	mic_touch_button.pressed.connect(_on_mic_touch_button_pressed)
	
	_update_mic_ui()
	print("Touch Controls Ready: Mic state initialized to: ", mic_enabled)

	_hide_controls_on_desktop()
	if _touch_ui_enabled:
		_apply_level_touch_rules()

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
	if not _touch_ui_enabled:
		return
	if safe_area == null or left_cluster == null or right_cluster == null:
		return
	var vis := MobileSafeLayout.visible_rect_design_from_viewport(get_viewport())
	safe_area.anchor_left = 0.0
	safe_area.anchor_top = 0.0
	safe_area.anchor_right = 0.0
	safe_area.anchor_bottom = 0.0
	safe_area.position = vis.position
	safe_area.size = vis.size

	var placed: Dictionary = MobileSafeLayout.layout_touch_controls(get_viewport())
	_place_cluster(left_cluster, MobileSafeLayout.LEFT_CLUSTER_SIZE, placed["left"] as Rect2, vis.position)
	_place_cluster(right_cluster, MobileSafeLayout.RIGHT_CLUSTER_SIZE, placed["right"] as Rect2, vis.position)


func _place_cluster(cluster: Control, base: Vector2, visual: Rect2, origin: Vector2) -> void:
	cluster.anchor_left = 0.0
	cluster.anchor_top = 0.0
	cluster.anchor_right = 0.0
	cluster.anchor_bottom = 0.0
	cluster.pivot_offset = Vector2.ZERO
	cluster.position = visual.position - origin
	cluster.size = base
	if base.x <= 0.0 or base.y <= 0.0 or visual.size.x <= 0.0 or visual.size.y <= 0.0:
		cluster.scale = Vector2.ZERO
		return
	var scale := minf(visual.size.x / base.x, visual.size.y / base.y)
	cluster.scale = Vector2(scale, scale)


func apply_touch_ui_enabled() -> void:
	_touch_ui_enabled = MobileSafeLayout.wants_touch_ui()
	if not _touch_ui_enabled:
		if left_cluster:
			left_cluster.visible = false
		if right_cluster:
			right_cluster.visible = false
		visible = false
		return
	if left_cluster:
		left_cluster.visible = true
	if right_cluster:
		right_cluster.visible = true
	_apply_level_touch_rules()
	_apply_safe_layout()
	visible = not _pause_menu_open()


func _pause_menu_open() -> bool:
	var menu := get_node_or_null("/root/PauseMenu")
	return menu != null and bool(menu.get("is_paused"))


func _apply_level_touch_rules() -> void:
	var current_level := get_tree().current_scene.name
	if current_level == "02":
		_disable_arrow_buttons()
		_disable_interact_button()
	if current_level == "Playground":
		_disable_mic_button()
		_disable_interact_button()
	if current_level == "EndlessHorde":
		_disable_interact_button()


func set_suppressed_by_pause(suppressed: bool) -> void:
	if not _touch_ui_enabled:
		return
	visible = not suppressed


func _process(_delta: float) -> void:
	if not _touch_ui_enabled:
		return
	_align_touch_button(mic_button, mic_touch_button)
	_align_touch_button(interact_button, interact_touch_button)


func _align_touch_button(button: Control, touch: TouchScreenButton) -> void:
	if button == null or touch == null or not button.visible:
		return
	var rect := button.get_global_rect()
	touch.global_position = rect.position + rect.size / 2.0
	if touch.shape is RectangleShape2D:
		(touch.shape as RectangleShape2D).size = rect.size


func _hide_controls_on_desktop() -> void:
	_touch_ui_enabled = MobileSafeLayout.wants_touch_ui()
	if _touch_ui_enabled:
		return
	print("🖥️ Desktop detected — hiding all on-screen touch controls.")
	if left_cluster:
		left_cluster.visible = false
	if right_cluster:
		right_cluster.visible = false
	visible = false


func _disable_arrow_buttons() -> void:
	print("🎤 Mic-only level detected. Hiding arrow buttons.")
	_set_movement_arrows_visible(false)
	if has_node("Root/SafeArea/RightCluster/Attack"):
		$Root/SafeArea/RightCluster/Attack.visible = false


func _enable_movement_arrows() -> void:
	print("✅ Showing movement arrows after voice struggles.")
	_set_movement_arrows_visible(true)


func _set_movement_arrows_visible(shown: bool) -> void:
	if has_node("Root/SafeArea/LeftCluster/Left"):
		$Root/SafeArea/LeftCluster/Left.visible = shown
	if has_node("Root/SafeArea/LeftCluster/Right"):
		$Root/SafeArea/LeftCluster/Right.visible = shown
	if has_node("Root/SafeArea/LeftCluster/Up"):
		$Root/SafeArea/LeftCluster/Up.visible = shown
	if has_node("Root/SafeArea/LeftCluster/Down"):
		$Root/SafeArea/LeftCluster/Down.visible = shown


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
	if _voice_only_mode:
		print("Mic toggle ignored during voice-only mode.")
		if not mic_enabled:
			mic_enabled = true
			_start_listening()
			_update_mic_ui()
			_set_voice_banner_listening(true)
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
		_set_voice_banner_listening(_voice_only_mode)
	else:
		_stop_listening()
		_set_voice_banner_listening(false)
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


func begin_voice_only_mode() -> void:
	_voice_only_mode = true
	_struggle_count = 0
	_movement_unlocked = false
	print("✅ Voice-only mode started.")
	if _touch_ui_enabled:
		_disable_arrow_buttons()
		_disable_interact_button()
	var stt = _stt_manager()
	if stt == null or not stt.is_speech_available():
		print("⚠️ STT unavailable. Voice-only mode cannot start listening.")
		_set_voice_banner_listening(false)
		if _touch_ui_enabled:
			_unlock_movement_buttons()
		return
	mic_enabled = true
	_start_listening()
	_update_mic_ui()
	_set_voice_banner_listening(true)


func end_voice_only_mode() -> void:
	_voice_only_mode = false
	_struggle_count = 0
	_movement_unlocked = false
	print("✅ Voice-only mode ended.")
	if mic_restart_timer:
		mic_restart_timer.stop()
	if not _challenge_mic_active:
		_stop_listening()
		mic_enabled = false
		_update_mic_ui()
	_set_voice_banner_listening(false)


func _unlock_movement_buttons() -> void:
	if _movement_unlocked or not _touch_ui_enabled:
		return
	_movement_unlocked = true
	_enable_movement_arrows()
	PlayerManager.voice_only = false
	_apply_safe_layout()
	if player_hud and player_hud.has_method("show_arrows_unlocked_banner"):
		player_hud.show_arrows_unlocked_banner()
	var scene := get_tree().current_scene
	if scene:
		var tutorial := scene.find_child("TutorialDialog", true, false)
		if tutorial and tutorial.has_method("show_custom_message"):
			tutorial.show_custom_message("On-screen arrows unlocked.", true)
	print("✅ Movement buttons unlocked after voice struggles.")


func _set_voice_banner_listening(listening: bool) -> void:
	if player_hud and player_hud.has_method("set_voice_only_listening"):
		player_hud.set_voice_only_listening(listening)


func begin_challenge_mic() -> void:
	if not OS.has_feature("web"):
		return
	_challenge_mic_active = true
	_mic_enabled_before_challenge = mic_enabled
	if mic_restart_timer:
		mic_restart_timer.stop()
	mic_enabled = true
	_update_mic_ui()


func end_challenge_mic() -> void:
	if not OS.has_feature("web"):
		return
	_challenge_mic_active = false
	mic_enabled = _mic_enabled_before_challenge or _voice_only_mode
	_update_mic_ui()
	if mic_enabled:
		_start_listening()
		_set_voice_banner_listening(_voice_only_mode)
	else:
		_set_voice_banner_listening(false)

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

	var matched := false
	var lower := transcription.to_lower()
	for command in VOICE_COMMANDS:
		if lower.findn(command) != -1:
			matched = true
			await _execute_command(command)
			break

	if _voice_only_mode and not _movement_unlocked and _touch_ui_enabled:
		var spoken := transcription.strip_edges()
		if not spoken.is_empty() and not matched:
			_struggle_count += 1
			print("⚠️ Voice struggle ", _struggle_count, "/", STRUGGLE_UNLOCK_COUNT)
			if _struggle_count >= STRUGGLE_UNLOCK_COUNT:
				_unlock_movement_buttons()

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
		"move backward", "move backwards":
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
