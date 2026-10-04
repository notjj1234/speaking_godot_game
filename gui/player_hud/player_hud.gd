# player_hud.gd

class_name PlayerHudUI
extends CanvasLayer

signal fallback_submitted(text: String)
signal speak_pressed
signal feedback_closed

const FEEDBACK_DURATION := 0.8

var hearts: Array[HeartGUI] = []
var target_sentence: String = ""  # Added to store the target sentence for validation
var _feedback_token: int = 0

@onready var challenge_panel: PanelContainer = $Control/ChallengePanel
@onready var speech_challenge_label: Label = $Control/ChallengePanel/MarginContainer/ChallengeVBox/SpeechChallengeLabel
@onready var live_transcript_label: Label = $Control/ChallengePanel/MarginContainer/ChallengeVBox/LiveTranscriptLabel
@onready var challenge_feedback_label: Label = $Control/ChallengePanel/MarginContainer/ChallengeVBox/ChallengeFeedbackLabel
@onready var challenge_fallback_row: HBoxContainer = $Control/ChallengePanel/MarginContainer/ChallengeVBox/ChallengeFallbackRow
@onready var challenge_speak_button: Button = $Control/ChallengePanel/MarginContainer/ChallengeVBox/ChallengeFallbackRow/ChallengeSpeakButton
@onready var challenge_fallback_input: LineEdit = $Control/ChallengePanel/MarginContainer/ChallengeVBox/ChallengeFallbackRow/ChallengeFallbackInput
@onready var challenge_fallback_submit: Button = $Control/ChallengePanel/MarginContainer/ChallengeVBox/ChallengeFallbackRow/ChallengeFallbackSubmit
@onready var challenge_vbox: VBoxContainer = $Control/ChallengePanel/MarginContainer/ChallengeVBox
@onready var life_sprite: Sprite2D = $Control/Sprite2D
@onready var voice_only_banner: PanelContainer = $Control/VoiceOnlyBanner
@onready var voice_only_label: Label = $Control/VoiceOnlyBanner/VoiceOnlyLabel


func _ready() -> void:
	for child in $Control/HFlowContainer.get_children():
		if child is HeartGUI:
			hearts.append(child)
			child.visible = false
	hide_speech_challenge()
	challenge_fallback_submit.pressed.connect(_on_fallback_submit_pressed)
	challenge_fallback_input.text_submitted.connect(_on_fallback_text_submitted)
	challenge_speak_button.pressed.connect(_on_speak_pressed)
	hide_voice_only_banner()
	_center_life_hud()
	call_deferred("_center_life_hud")
	var viewport := get_viewport()
	if viewport:
		viewport.size_changed.connect(_center_life_hud)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_center_life_hud()


func _center_life_hud() -> void:
	if life_sprite == null:
		return
	var host := life_sprite.get_parent() as Control
	var mid_x := 320.0
	if host and host.size.x > 0.0:
		mid_x = host.size.x * 0.5
	else:
		var viewport := get_viewport()
		if viewport:
			mid_x = viewport.get_visible_rect().size.x * 0.5
	life_sprite.position = Vector2(mid_x, 6)


func show_voice_only_banner() -> void:
	if voice_only_banner:
		voice_only_banner.visible = true
	if voice_only_label:
		voice_only_label.text = "VOICE ONLY — keyboard disabled. Speak to move."
	set_voice_only_listening(false)


func hide_voice_only_banner() -> void:
	if voice_only_banner:
		voice_only_banner.visible = false
	set_voice_only_listening(false)


func show_arrows_unlocked_banner() -> void:
	if voice_only_banner:
		voice_only_banner.visible = true
	if voice_only_label:
		voice_only_label.text = "Arrows unlocked — tap to move. Voice still works."
		voice_only_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.55, 1))


func set_voice_only_listening(listening: bool) -> void:
	if voice_only_label == null:
		return
	if listening:
		voice_only_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.55, 1))
	else:
		voice_only_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))


func update_hp(_hp: int, _max_hp: int) -> void:
	update_max_hp(_max_hp)
	for i in _max_hp:
		update_heart(i, _hp)
	pass


func update_heart(_index: int, _hp: int) -> void:
	var _value: int = clampi(_hp - _index * 2, 0, 2) # Figure out the hp for that heart
	# If 0 = no heart, 1 = half a heart, 2 = full heart
	hearts[_index].value = _value
	pass


func update_max_hp(_max_hp: int) -> void:
	var _heart_count: int = roundi(_max_hp * 0.5)
	for i in hearts.size():
		if i < _heart_count:
			hearts[i].visible = true
		else:
			hearts[i].visible = false
	pass


func show_speech_challenge(sentence: String) -> void:
	_feedback_token += 1
	target_sentence = sentence
	challenge_panel.visible = true
	speech_challenge_label.text = "Say: " + sentence
	speech_challenge_label.visible = true
	live_transcript_label.text = ""
	live_transcript_label.visible = true
	challenge_feedback_label.text = ""
	challenge_feedback_label.visible = false
	if OS.has_feature("web"):
		_configure_web_challenge_controls()
	else:
		hide_typed_fallback()
		hide_speak_button()


func _configure_web_challenge_controls() -> void:
	show_typed_fallback()
	show_speak_button()
	# Desktop: keyboard-first (type + Enter). Speak stays for Chrome's user-gesture mic rule.
	# Touch: keep larger tap targets from the scene defaults.
	if MobileSafeLayout.wants_touch_ui():
		challenge_speak_button.custom_minimum_size = Vector2(80, 40)
		challenge_fallback_submit.custom_minimum_size = Vector2(80, 40)
		challenge_fallback_input.custom_minimum_size = Vector2(0, 40)
	else:
		challenge_speak_button.custom_minimum_size = Vector2(72, 28)
		challenge_fallback_submit.custom_minimum_size = Vector2(72, 28)
		challenge_fallback_input.custom_minimum_size = Vector2(0, 28)
		challenge_fallback_input.placeholder_text = "Type the phrase, then press Enter"
	call_deferred("_focus_challenge_input")


func _focus_challenge_input() -> void:
	if challenge_fallback_input and challenge_fallback_row and challenge_fallback_row.visible:
		challenge_fallback_input.grab_focus()
		challenge_fallback_input.caret_column = challenge_fallback_input.text.length()


func hide_speech_challenge() -> void:
	_feedback_token += 1
	if challenge_panel:
		challenge_panel.visible = false
	if speech_challenge_label:
		speech_challenge_label.visible = false
	if live_transcript_label:
		live_transcript_label.text = ""
		live_transcript_label.visible = false
	if challenge_feedback_label:
		challenge_feedback_label.text = ""
		challenge_feedback_label.visible = false
	hide_typed_fallback()
	hide_speak_button()


func show_typed_fallback() -> void:
	var already_open := challenge_fallback_row.visible
	challenge_fallback_row.visible = true
	if not already_open:
		challenge_fallback_input.text = ""
		challenge_fallback_input.grab_focus()


func hide_typed_fallback() -> void:
	if challenge_fallback_row:
		challenge_fallback_row.visible = false
	if challenge_fallback_input:
		challenge_fallback_input.text = ""
	hide_speak_button()


func show_speak_button() -> void:
	if challenge_speak_button:
		challenge_speak_button.visible = true
	if challenge_fallback_row:
		challenge_fallback_row.visible = true


func hide_speak_button() -> void:
	if challenge_speak_button:
		challenge_speak_button.visible = false


func _on_speak_pressed() -> void:
	speak_pressed.emit()


func _on_fallback_submit_pressed() -> void:
	_submit_fallback_text(challenge_fallback_input.text)


func _on_fallback_text_submitted(text: String) -> void:
	_submit_fallback_text(text)


func _submit_fallback_text(text: String) -> void:
	fallback_submitted.emit(text)


func update_live_transcript(transcript: String) -> void:
	live_transcript_label.text = transcript
	live_transcript_label.visible = true
	print("Live transcription updated: ", transcript)


func show_feedback(success: bool) -> void:
	if success:
		# Success: hide challenge panel immediately, show floating toast
		challenge_panel.visible = false
		_show_success_toast()
	else:
		# Failure: keep panel visible for retry
		if not success:
			live_transcript_label.text = ""
		challenge_feedback_label.text = "Try Again!"
		challenge_feedback_label.add_theme_color_override("font_color", Color(0.8, 0.15, 0.08, 1))
		challenge_feedback_label.visible = true
		if not challenge_panel.visible:
			challenge_panel.visible = true
			speech_challenge_label.visible = false
			live_transcript_label.visible = false
			hide_typed_fallback()
		_feedback_token += 1
		var token := _feedback_token
		_hide_feedback_after_delay(token)


func _show_success_toast() -> void:
	if not has_node("ToastLabel"):
		var toast = Label.new()
		toast.name = "ToastLabel"
		toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		toast.add_theme_font_size_override("font_size", 28)
		toast.add_theme_color_override("font_color", Color(0.05, 0.45, 0.15, 1))
		toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		toast.visible = false
		add_child(toast)
		call_deferred("_position_toast")
	
	var toast = get_node("ToastLabel")
	toast.text = "Success!"
	toast.visible = true
	toast.modulate = Color(1, 1, 1, 1)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(toast, "modulate:a", 0.0, FEEDBACK_DURATION)
	tween.finished.connect(_on_toast_finished.bind(toast))
	
	# Emit feedback_closed for the caller awaiting it
	feedback_closed.emit()


func _position_toast() -> void:
	var toast = get_node_or_null("ToastLabel")
	if toast:
		var viewport = get_viewport()
		if viewport:
			toast.position = viewport.get_visible_rect().size * 0.5
			toast.position.y -= 80


func _on_toast_finished(toast: Label) -> void:
	toast.visible = false
	toast.text = ""


func _hide_feedback_after_delay(token: int) -> void:
	await get_tree().create_timer(FEEDBACK_DURATION).timeout
	if token != _feedback_token:
		feedback_closed.emit()
		return
	challenge_feedback_label.visible = false
	challenge_feedback_label.text = ""
	if not speech_challenge_label.visible:
		challenge_panel.visible = false
		target_sentence = ""
	feedback_closed.emit()


func set_mic_state(listening: bool) -> void:
	if not has_node("MicIndicatorRow"):
		var row = HBoxContainer.new()
		row.name = "MicIndicatorRow"
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		
		var dot = ColorRect.new()
		dot.name = "MicDot"
		dot.custom_minimum_size = Vector2(12, 12)
		row.add_child(dot)
		
		var label = Label.new()
		label.name = "MicLabel"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 16)
		row.add_child(label)
		
		challenge_vbox.add_child(row)
		row.move_child(dot, 0)
		row.move_child(label, 1)
	
	var row = get_node("MicIndicatorRow")
	var dot = row.get_node("MicDot")
	var label = row.get_node("MicLabel")
	
	if listening:
		dot.visible = true
		label.visible = true
		label.text = "Listening..."
		dot.add_theme_color_override("bg_color", Color(0.9, 0.15, 0.15, 1))
		
		var tween = dot.create_tween()
		tween.set_loops()
		tween.tween_property(dot, "modulate:a", 0.3, 0.5)
		tween.tween_property(dot, "modulate:a", 1.0, 0.5)
		tween.set_process_mode(2)  # TWEEN_PROCESS_MODE_ALWAYS = 2
		dot.set_meta("_mic_tween", tween)
	else:
		dot.visible = true
		label.visible = true
		label.text = "Mic off"
		dot.add_theme_color_override("bg_color", Color(0.4, 0.4, 0.4, 1))
		dot.modulate = Color(1, 1, 1, 1)
		var existing_tween = dot.get_meta("_mic_tween", null)
		if existing_tween and existing_tween is Tween:
			existing_tween.kill()
		dot.remove_meta("_mic_tween")
