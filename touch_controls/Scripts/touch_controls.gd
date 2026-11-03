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

const DEFAULT_STRUGGLE_UNLOCK_COUNT := 3
# Longer phrases first so "stop please" wins over bare "stop".
const DEFAULT_VOICE_COMMANDS: Array[String] = [
	"move forward",
	"move backwards",
	"move backward",
	"move left",
	"move right",
	"stop please",
	"stop moving",
	"stop",
	"halt",
	"attack",
]

var STRUGGLE_UNLOCK_COUNT: int = DEFAULT_STRUGGLE_UNLOCK_COUNT
var VOICE_COMMANDS: Array[String] = DEFAULT_VOICE_COMMANDS.duplicate()

var mic_enabled: bool = false
var mic_restart_timer: Timer = null
var _challenge_mic_active: bool = false
var _mic_enabled_before_challenge: bool = false
var _touch_ui_enabled: bool = true
var _voice_only_mode: bool = false
## Level 03+: mic toggle available, keyboard stays unlocked.
var _optional_mic_mode: bool = false
var _struggle_count: int = 0
var _movement_unlocked: bool = false
var _voice_only_gesture_hooked: bool = false
## Guards against Button+TouchScreenButton both seeing one click (felt like hold-to-talk).
var _mic_ui_syncing: bool = false
var _mic_toggle_cooldown_until_msec: int = 0

func _ready() -> void:
	add_to_group("touch_controls")
	# Click/tap toggle — not hold. Use Button.toggled only; the overlapping
	# TouchScreenButton used to fire on press and the Button on release, which
	# turned the mic off as soon as you let go.
	if mic_button:
		mic_button.toggle_mode = true
		mic_button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		if not mic_button.toggled.is_connected(_on_mic_button_toggled):
			mic_button.toggled.connect(_on_mic_button_toggled)
	if mic_touch_button:
		# Keep node for layout helpers, but do not let it steal press/release.
		mic_touch_button.visible = false
		mic_touch_button.set_process_mode(Node.PROCESS_MODE_DISABLED)

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
		if not stt.listening_started.is_connected(_on_mic_listening_started):
			stt.listening_started.connect(_on_mic_listening_started)
		if not stt.listening_stopped.is_connected(_on_mic_listening_stopped):
			stt.listening_stopped.connect(_on_mic_listening_stopped)
	else:
		print("STT unavailable. Mic toggle will stay off.")
		if player_hud and player_hud.has_method("set_stt_state"):
			player_hud.set_stt_state(PlayerHudUI.SttState.STT_UNAVAILABLE)

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
	var current_scene = get_tree().current_scene
	if current_scene == null:
		return
	
	var metadata = LevelMetadata.get_for_level(current_scene)
	if metadata:
		LevelMetadata.apply_to_touch_controls(self, metadata)
		print("✅ Applied level metadata: ", metadata.level_name)
	else:
		# Fallback for legacy levels without metadata
		_apply_legacy_level_rules(current_scene.name)


func _apply_legacy_level_rules(level_name: String) -> void:
	match level_name:
		"02":
			_disable_arrow_buttons()
			_disable_interact_button()
		"Playground":
			_disable_mic_button()
			_disable_interact_button()
		"EndlessHorde":
			_disable_interact_button()


func set_suppressed_by_pause(suppressed: bool) -> void:
	if not _touch_ui_enabled:
		return
	visible = not suppressed


func _process(_delta: float) -> void:
	if not _touch_ui_enabled:
		return
	# Mic uses the Button only (no TouchScreenButton overlay — that caused hold).
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


func _disable_attack_button() -> void:
	if has_node("Root/SafeArea/RightCluster/Attack"): $Root/SafeArea/RightCluster/Attack.visible = false


func set_struggle_unlock_count(count: int) -> void:
	STRUGGLE_UNLOCK_COUNT = count
	print("✅ Struggle unlock count set to: ", count)


func set_custom_voice_commands(commands: Array[String]) -> void:
	VOICE_COMMANDS = commands
	print("✅ Custom voice commands set: ", commands)


func _on_mic_button_toggled(is_on: bool) -> void:
	if _mic_ui_syncing:
		return
	print("Mic button toggled → ", is_on)
	_set_microphone_enabled(is_on)


func _toggle_microphone() -> void:
	_set_microphone_enabled(not mic_enabled)


func _set_microphone_enabled(want_on: bool) -> void:
	if _challenge_mic_active:
		print("Mic toggle ignored during speech challenge.")
		_sync_mic_button_pressed(mic_enabled)
		return
	var now := Time.get_ticks_msec()
	if now < _mic_toggle_cooldown_until_msec:
		_sync_mic_button_pressed(mic_enabled)
		return
	_mic_toggle_cooldown_until_msec = now + 250

	if _voice_only_mode:
		# Voice-only stays armed; a tap only restarts listen if needed.
		print("Mic toggle ignored during voice-only mode.")
		if not mic_enabled:
			mic_enabled = true
			_start_listening()
			_update_mic_ui()
			_set_voice_banner_listening(true)
		else:
			_sync_mic_button_pressed(true)
		return
	var stt = _stt_manager()
	if stt == null or not stt.is_speech_available():
		print("STT unavailable. Mic toggle ignored.")
		mic_enabled = false
		_update_mic_ui()
		return

	mic_enabled = want_on
	print("Microphone enabled: ", mic_enabled)
	if mic_enabled:
		_start_listening()
		_set_voice_banner_listening(_voice_only_mode)
		if _optional_mic_mode and player_hud and player_hud.has_method("show_voice_commands_list"):
			player_hud.show_voice_commands_list()
	else:
		_stop_listening()
		_set_voice_banner_listening(false)
		if PlayerManager.player and PlayerManager.player.has_method("stop_continuous_move"):
			PlayerManager.player.stop_continuous_move()
		if _optional_mic_mode and player_hud and player_hud.has_method("hide_voice_commands_list"):
			player_hud.hide_voice_commands_list()
	_update_mic_ui()


func _sync_mic_button_pressed(is_on: bool) -> void:
	if mic_button == null or not mic_button.toggle_mode:
		return
	_mic_ui_syncing = true
	mic_button.set_pressed_no_signal(is_on)
	_mic_ui_syncing = false

func _start_listening() -> void:
	print("Starting microphone...")
	var stt = _stt_manager()
	if stt != null and stt.is_speech_available():
		stt.listen()
	else:
		print("STT unavailable.")
		mic_enabled = false
		_update_mic_ui()
		if _voice_only_mode:
			_fail_open_voice_only("Speech is unavailable — keyboard unlocked.")

func _stop_listening() -> void:
	print("Stopping microphone...")
	var stt = _stt_manager()
	if stt != null:
		stt.stop()

func _stt_manager():
	return get_node_or_null("/root/STTManager")


func begin_voice_only_mode() -> void:
	_optional_mic_mode = false
	_voice_only_mode = true
	_struggle_count = 0
	_movement_unlocked = false
	print("✅ Voice-only mode started.")
	if _touch_ui_enabled:
		_disable_arrow_buttons()
		_disable_interact_button()
		# Keep the mic button visible so a tap can satisfy the browser's
		# user-gesture rule for SpeechRecognition.start().
		_ensure_mic_button_visible()
	var stt = _stt_manager()
	if stt == null or not stt.is_speech_available():
		print("⚠️ STT unavailable. Voice-only mode cannot start listening.")
		_set_voice_banner_listening(false)
		_fail_open_voice_only("Speech is unavailable — keyboard unlocked.")
		return
	PlayerManager.voice_only = true
	mic_enabled = true
	_start_listening()
	_update_mic_ui()
	_set_voice_banner_listening(true)
	_hook_voice_only_gesture_retry()


func end_voice_only_mode() -> void:
	_voice_only_mode = false
	_struggle_count = 0
	_movement_unlocked = false
	_unhook_voice_only_gesture_retry()
	print("✅ Voice-only mode ended.")
	if mic_restart_timer:
		mic_restart_timer.stop()
	if not _challenge_mic_active:
		_stop_listening()
		mic_enabled = false
		_update_mic_ui()
	_set_voice_banner_listening(false)
	PlayerManager.voice_only = false


func begin_optional_mic_mode() -> void:
	# Final tutorial (03) and onwards: user can toggle mic; WASD/attack stay free.
	_voice_only_mode = false
	_optional_mic_mode = true
	PlayerManager.voice_only = false
	_ensure_mic_button_visible()
	mic_enabled = false
	_update_mic_ui()
	_set_voice_banner_listening(false)
	print("✅ Optional mic mode — toggle Mic On for voice move/attack.")


func end_optional_mic_mode() -> void:
	_optional_mic_mode = false
	if mic_restart_timer:
		mic_restart_timer.stop()
	if not _challenge_mic_active and mic_enabled:
		_stop_listening()
	mic_enabled = false
	_update_mic_ui()
	_set_voice_banner_listening(false)
	if player_hud and player_hud.has_method("hide_voice_commands_list"):
		player_hud.hide_voice_commands_list()
	print("✅ Optional mic mode ended.")


func _fail_open_voice_only(message: String) -> void:
	# Never soft-lock the player: if the mic cannot run, restore keyboard/arrows.
	_voice_only_mode = false
	_unhook_voice_only_gesture_retry()
	PlayerManager.voice_only = false
	_set_voice_banner_listening(false)
	mic_enabled = false
	_update_mic_ui()
	if _touch_ui_enabled:
		_unlock_movement_buttons()
	if player_hud and player_hud.has_method("show_arrows_unlocked_banner"):
		player_hud.show_arrows_unlocked_banner()
	var scene := get_tree().current_scene
	if scene:
		var tutorial := scene.find_child("TutorialDialog", true, false)
		if tutorial and tutorial.has_method("show_custom_message"):
			tutorial.show_custom_message(message, true)
	print("⚠️ ", message)


func _ensure_mic_button_visible() -> void:
	if mic_button:
		mic_button.visible = true
	# Touch_Mic stays disabled — the Button alone is the click/tap toggle.
	if mic_touch_button:
		mic_touch_button.visible = false
	# Desktop web hides the whole layer; show at least the right cluster so the
	# player can tap Mic On and satisfy the browser gesture requirement.
	if not _touch_ui_enabled:
		visible = true
		if left_cluster:
			left_cluster.visible = false
		if right_cluster:
			right_cluster.visible = true
			_disable_interact_button()
			_disable_attack_button()


func _hook_voice_only_gesture_retry() -> void:
	if _voice_only_gesture_hooked:
		return
	set_process_unhandled_input(true)
	_voice_only_gesture_hooked = true


func _unhook_voice_only_gesture_retry() -> void:
	_voice_only_gesture_hooked = false
	set_process_unhandled_input(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _voice_only_mode or not _voice_only_gesture_hooked:
		return
	if not mic_enabled:
		return
	# Any click/tap/key after entering the level can restart recognition once
	# the browser has a user gesture (auto-start on load often fails on web).
	var is_gesture := false
	if event is InputEventMouseButton:
		is_gesture = event.pressed
	elif event is InputEventScreenTouch:
		is_gesture = event.pressed
	elif event is InputEventKey:
		is_gesture = event.pressed and not event.echo
	if not is_gesture:
		return
	print("🎤 Voice-only: retrying mic start after user gesture.")
	_start_listening()
	_set_voice_banner_listening(true)
	# One retry hook is enough; the restart timer handles continuity after that.
	_unhook_voice_only_gesture_retry()
	get_viewport().set_input_as_handled()


func _unlock_movement_buttons() -> void:
	if _movement_unlocked:
		return
	_movement_unlocked = true
	PlayerManager.voice_only = false
	if _touch_ui_enabled:
		_enable_movement_arrows()
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
	if mic_button:
		mic_button.text = "Mic On" if mic_enabled else "Mic Off"
		_sync_mic_button_pressed(mic_enabled)
	_sync_hud_mic_indicator()


func _on_mic_listening_started() -> void:
	# Always update the button to reflect the listening state.
	# The challenge path already manages its own visuals via mic_enabled,
	# but the level UI should show what the provider is doing.
	if mic_button:
		mic_button.text = "Mic On"
	# Sync the HUD dot only when not in a challenge (the challenge
	# manages its own indicator during active challenges).
	if not _challenge_mic_active and player_hud and player_hud.has_method("set_mic_state"):
		player_hud.set_mic_state(true)


func _on_mic_listening_stopped() -> void:
	# Always update the button to reflect the listening stop.
	if mic_button:
		mic_button.text = "Mic Off"
	# Sync the HUD dot regardless — it reflects mic_enabled which is the
	# unified state (challenge sets it too, so this stays consistent).
	_sync_hud_mic_indicator()


func _sync_hud_mic_indicator() -> void:
	if player_hud == null:
		return
	var stt = _stt_manager()
	if stt == null or not stt.is_speech_available():
		if player_hud.has_method("set_stt_state"):
			player_hud.set_stt_state(PlayerHudUI.SttState.STT_UNAVAILABLE)
		return
	if not mic_enabled:
		if player_hud.has_method("set_mic_state"):
			player_hud.set_mic_state(false)
		return
	# Armed: show Listening when the provider is mid-listen; otherwise Mic On via LISTENING
	# so the player can tell the session is live (not stuck on Mic: Off).
	if player_hud.has_method("set_mic_state"):
		player_hud.set_mic_state(true)

func _on_listening_completed(transcription: String) -> void:
	if _challenge_mic_active:
		return
	print("Mic transcription received: ", transcription)
	if player_hud:
		player_hud.update_live_transcript(transcription)

	var matched := false
	var lower := transcription.to_lower()
	# Prefer longer phrases ("stop please" before "stop").
	var ordered: Array[String] = VOICE_COMMANDS.duplicate()
	ordered.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for command in ordered:
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
	if error_code == -1 and _voice_only_mode:
		# Permission / start failure. Keep voice-only armed but re-hook a gesture
		# so the next click can start recognition; do not soft-lock forever.
		print("⚠️ Voice-only mic start failed. Waiting for a click/tap to retry.")
		_hook_voice_only_gesture_retry()
		_set_voice_banner_listening(false)
		# Keep mic_enabled true (armed). HUD shows On so the player knows to tap again.
		_update_mic_ui()
		return
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

	# Continuous walk when mic session is live (voice-only OR optional mic On).
	var use_continuous := _voice_only_mode or (_optional_mic_mode and mic_enabled)

	match command:
		"move forward":
			if use_continuous:
				PlayerManager.player.start_continuous_move(PlayerManager.player.cardinal_direction)
			else:
				await PlayerManager.player.move_with_animation(PlayerManager.player.cardinal_direction)
		"move backward", "move backwards":
			if use_continuous:
				PlayerManager.player.start_continuous_move(-PlayerManager.player.cardinal_direction)
			else:
				await PlayerManager.player.move_with_animation(-PlayerManager.player.cardinal_direction)
		"move left":
			var left_dir := Vector2.LEFT if is_facing_south else PlayerManager.player.cardinal_to_relative(Vector2.LEFT)
			if use_continuous:
				PlayerManager.player.start_continuous_move(left_dir)
			else:
				await PlayerManager.player.move_with_animation(left_dir)
		"move right":
			var right_dir := Vector2.RIGHT if is_facing_south else PlayerManager.player.cardinal_to_relative(Vector2.RIGHT)
			if use_continuous:
				PlayerManager.player.start_continuous_move(right_dir)
			else:
				await PlayerManager.player.move_with_animation(right_dir)
		"stop", "stop moving", "halt", "stop please":
			PlayerManager.player.stop_continuous_move()
		"attack":
			PlayerManager.player.attack_with_animation()
		_:
			print("Unknown command: ", command)
