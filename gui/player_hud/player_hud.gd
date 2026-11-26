# player_hud.gd

class_name PlayerHudUI
extends CanvasLayer

signal fallback_submitted(text: String)
signal speak_pressed
signal feedback_closed

enum SttState {
	STT_IDLE = 0,
	STT_LISTENING = 1,
	STT_PROCESSING = 2,
	STT_ERROR = 3,
	STT_UNAVAILABLE = 4
}

const FEEDBACK_DURATION := 0.8
const MAX_CHALLENGE_TRIES := 3
const INK := Color(0.13, 0.08, 0.03, 1)
const CREAM := Color(0.98, 0.96, 0.9, 1)

var hearts: Array[HeartGUI] = []
var target_sentence: String = ""
var _feedback_token: int = 0
var _stt_state: SttState = SttState.STT_IDLE
var _stt_plate: PanelContainer = null
var _stt_indicator_row: HBoxContainer = null
var _stt_dot: ColorRect = null
var _stt_label: Label = null
var _challenge_status_label: Label = null
var _move_heard_label: Label = null
var _success_plate: PanelContainer = null
var _stt_tween: Tween = null
var _tries_label: Label = null
var _warmup_label: Label = null
var _challenge_tries_remaining: int = PlayerHudUI.MAX_CHALLENGE_TRIES
var _listen_row: HBoxContainer = null
var _listen_button: Button = null
var _listen_token: int = 0
var _listen_pending: bool = false
var _listen_pending_token: int = 0
var _listen_warned: bool = false

@onready var challenge_panel: PanelContainer = $Control/ChallengeCenter/ChallengePanel
@onready var speech_challenge_label: Label = $Control/ChallengeCenter/ChallengePanel/MarginContainer/ChallengeVBox/SpeechChallengeLabel
@onready var live_transcript_label: Label = $Control/ChallengeCenter/ChallengePanel/MarginContainer/ChallengeVBox/LiveTranscriptLabel
@onready var challenge_feedback_label: Label = $Control/ChallengeCenter/ChallengePanel/MarginContainer/ChallengeVBox/ChallengeFeedbackLabel
@onready var challenge_fallback_row: HBoxContainer = $Control/ChallengeCenter/ChallengePanel/MarginContainer/ChallengeVBox/ChallengeFallbackRow
@onready var challenge_speak_button: Button = $Control/ChallengeCenter/ChallengePanel/MarginContainer/ChallengeVBox/ChallengeFallbackRow/ChallengeSpeakButton
@onready var challenge_fallback_input: LineEdit = $Control/ChallengeCenter/ChallengePanel/MarginContainer/ChallengeVBox/ChallengeFallbackRow/ChallengeFallbackInput
@onready var challenge_fallback_submit: Button = $Control/ChallengeCenter/ChallengePanel/MarginContainer/ChallengeVBox/ChallengeFallbackRow/ChallengeFallbackSubmit
@onready var challenge_vbox: VBoxContainer = $Control/ChallengeCenter/ChallengePanel/MarginContainer/ChallengeVBox
@onready var life_sprite: Sprite2D = $Control/Sprite2D
@onready var voice_only_banner: PanelContainer = $Control/VoiceOnlyBanner
@onready var voice_only_label: Label = $Control/VoiceOnlyBanner/VoiceOnlyLabel

const VOICE_COMMAND_HELP: PackedStringArray = [
	"Facing is forward.",
	"move forward",
	"move backward",
	"move left",
	"move right",
	"stop",
	"attack",
]

var _voice_commands_panel: PanelContainer = null
var _voice_commands_label: Label = null


func _ready() -> void:
	for child in $Control/HFlowContainer.get_children():
		if child is HeartGUI:
			hearts.append(child)
			child.visible = false
	hide_speech_challenge()
	challenge_fallback_submit.pressed.connect(_on_fallback_submit_pressed)
	challenge_fallback_input.text_submitted.connect(_on_fallback_text_submitted)
	challenge_speak_button.pressed.connect(_on_speak_pressed)
	_style_parchment_button(challenge_speak_button)
	_style_parchment_button(challenge_fallback_submit)
	hide_voice_only_banner()
	_center_life_hud()
	call_deferred("_center_life_hud")
	var viewport := get_viewport()
	if viewport:
		viewport.size_changed.connect(_center_life_hud)
	_create_stt_indicator()
	_create_challenge_status_label()
	_create_tries_label()
	_create_warmup_label()
	_create_listen_button()
	_create_voice_commands_panel()


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
	show_voice_commands_list()


func hide_voice_only_banner() -> void:
	if voice_only_banner:
		voice_only_banner.visible = false
	set_voice_only_listening(false)
	hide_voice_commands_list()


func show_optional_mic_banner() -> void:
	if voice_only_banner:
		voice_only_banner.visible = true
	if voice_only_label:
		voice_only_label.text = "Mic optional — keyboard works. Toggle Mic On to speak."
		voice_only_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	set_voice_only_listening(false)
	# Commands appear when the player turns the mic on.


func hide_optional_mic_banner() -> void:
	if voice_only_banner:
		voice_only_banner.visible = false
	set_voice_only_listening(false)
	hide_voice_commands_list()


func show_voice_commands_list() -> void:
	if _voice_commands_panel == null:
		_create_voice_commands_panel()
	if _voice_commands_panel:
		_voice_commands_panel.visible = true


func hide_voice_commands_list() -> void:
	if _voice_commands_panel:
		_voice_commands_panel.visible = false
	# A stale "Heard: …" must not greet the player when the panel next opens.
	_set_move_heard("")


func _create_voice_commands_panel() -> void:
	if _voice_commands_panel != null:
		return
	var control := $Control as Control
	if control == null:
		return

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.9)
	style.border_color = Color(0.92, 0.92, 0.88, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_top = 8
	style.content_margin_right = 10
	style.content_margin_bottom = 8

	_voice_commands_panel = PanelContainer.new()
	_voice_commands_panel.name = "VoiceCommandsPanel"
	_voice_commands_panel.visible = false
	_voice_commands_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_voice_commands_panel.add_theme_stylebox_override("panel", style)
	_voice_commands_panel.anchor_left = 0.0
	_voice_commands_panel.anchor_top = 0.0
	_voice_commands_panel.anchor_right = 0.0
	_voice_commands_panel.anchor_bottom = 0.0
	_voice_commands_panel.offset_left = 8.0
	# Just under the voice banner (y 52-80), content height only (grows down):
	# the old fixed box reached y 330, over the D-pad's Up arrow (top y 280).
	_voice_commands_panel.offset_top = 84.0
	_voice_commands_panel.offset_right = 228.0
	_voice_commands_panel.offset_bottom = 84.0
	_voice_commands_panel.grow_horizontal = Control.GROW_DIRECTION_END
	_voice_commands_panel.grow_vertical = Control.GROW_DIRECTION_END

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_voice_commands_panel.add_child(vbox)

	var title := Label.new()
	title.text = "COMMANDS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.95, 0.92, 0.55, 1))
	title.add_theme_font_size_override("font_size", 14)
	var bold := load("res://gui/fonts/Abaddon Bold.ttf")
	if bold:
		title.add_theme_font_override("font", bold)
	vbox.add_child(title)

	_voice_commands_label = Label.new()
	var lines: PackedStringArray = PackedStringArray()
	for cmd in VOICE_COMMAND_HELP:
		lines.append("• " + cmd)
	_voice_commands_label.text = "\n".join(lines)
	_voice_commands_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.92, 1))
	_voice_commands_label.add_theme_font_size_override("font_size", 14)
	var body := load("res://gui/fonts/Abaddon Light.ttf")
	if body:
		_voice_commands_label.add_theme_font_override("font", body)
	_voice_commands_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_voice_commands_label)

	_move_heard_label = Label.new()
	_move_heard_label.name = "MoveHeardLabel"
	_move_heard_label.visible = false
	_move_heard_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_move_heard_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.55, 1))
	_move_heard_label.add_theme_font_size_override("font_size", 14)
	if body:
		_move_heard_label.add_theme_font_override("font", body)
	vbox.add_child(_move_heard_label)

	control.add_child(_voice_commands_panel)


func show_arrows_unlocked_banner() -> void:
	if voice_only_banner:
		voice_only_banner.visible = true
	if voice_only_label:
		voice_only_label.text = "Arrows unlocked — tap to move. Voice still works."
		voice_only_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.55, 1))
	show_voice_commands_list()


func set_voice_banner_message(text: String) -> void:
	if voice_only_banner:
		voice_only_banner.visible = true
	if voice_only_label:
		voice_only_label.text = text


func set_voice_only_listening(listening: bool) -> void:
	if voice_only_label == null:
		return
	if listening:
		voice_only_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.55, 1))
	else:
		voice_only_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))


func update_hp(_hp: int, _max_hp: int) -> void:
	update_max_hp(_max_hp)
	# One heart per 2 HP. Looping over every HP point indexed past the 20 heart
	# nodes as soon as Vitality took max HP above 20 (horde starts at 20).
	for i in mini(hearts.size(), ceili(_max_hp / 2.0)):
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
	# A new challenge must never start with the previous card's audio playing.
	_stop_tts()
	target_sentence = sentence
	challenge_panel.visible = true
	speech_challenge_label.text = "Say: " + sentence
	speech_challenge_label.visible = true
	live_transcript_label.text = ""
	live_transcript_label.visible = false
	challenge_feedback_label.text = ""
	challenge_feedback_label.visible = false
	_refresh_warmup_label()
	_apply_listen_button_size()
	if OS.has_feature("web"):
		_configure_web_challenge_controls()
	else:
		hide_typed_fallback()
		hide_speak_button()
	_refresh_listen_button()
	set_challenge_tries(_challenge_tries_remaining)
	set_stt_state(_stt_state)


func _configure_web_challenge_controls() -> void:
	show_typed_fallback()
	show_speak_button()
	# Desktop: keyboard-first (type + Enter). Speak stays for Chrome's user-gesture mic rule.
	# Touch: keep larger tap targets from the scene defaults.
	if MobileSafeLayout.wants_touch_ui():
		challenge_speak_button.custom_minimum_size = Vector2(80, 44)
		challenge_fallback_submit.custom_minimum_size = Vector2(80, 44)
		challenge_fallback_input.custom_minimum_size = Vector2(88, 44)
	else:
		challenge_speak_button.custom_minimum_size = Vector2(72, 44)
		challenge_fallback_submit.custom_minimum_size = Vector2(72, 44)
		challenge_fallback_input.custom_minimum_size = Vector2(88, 44)
		challenge_fallback_input.placeholder_text = "Type the phrase, then press Enter"
	call_deferred("_focus_challenge_input")


func _focus_challenge_input() -> void:
	if challenge_fallback_input and challenge_fallback_row and challenge_fallback_row.visible:
		challenge_fallback_input.grab_focus()
		challenge_fallback_input.caret_column = challenge_fallback_input.text.length()


func hide_speech_challenge() -> void:
	_feedback_token += 1
	_stop_tts()
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
	if _tries_label != null:
		_tries_label.visible = false
		_tries_label.text = ""
	if _warmup_label != null:
		_warmup_label.visible = false
		_warmup_label.text = ""
	hide_typed_fallback()
	hide_speak_button()
	_refresh_listen_button()
	set_stt_state(_stt_state)


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
	# The Speak button re-arms the mic; never let it start under TTS audio.
	_stop_tts()
	speak_pressed.emit()


func _on_fallback_submit_pressed() -> void:
	_submit_fallback_text(challenge_fallback_input.text)


func _on_fallback_text_submitted(text: String) -> void:
	_submit_fallback_text(text)


func _submit_fallback_text(text: String) -> void:
	# Typed answers end the listening moment; stop playback before the mic
	# can be re-armed by the challenge result path.
	_stop_tts()
	fallback_submitted.emit(text)


func update_live_transcript(transcript: String) -> void:
	var heard := transcript.strip_edges()
	if challenge_panel and challenge_panel.visible:
		live_transcript_label.text = heard
		live_transcript_label.visible = not heard.is_empty()
		return
	_set_move_heard(heard)


func _set_move_heard(heard: String) -> void:
	if _move_heard_label == null:
		return
	if heard.is_empty():
		_move_heard_label.text = ""
		_move_heard_label.visible = false
		return
	# Shown only inside the panel, which voice-only / mic-on modes open; any
	# stray transcript must not pop the panel open over the game.
	_move_heard_label.text = "Heard: " + heard
	_move_heard_label.visible = true


func _mark_heard_line() -> void:
	if live_transcript_label == null:
		return
	var heard := live_transcript_label.text.strip_edges()
	if heard.is_empty() or heard.begins_with("Heard:"):
		return
	live_transcript_label.text = "Heard: " + heard
	live_transcript_label.visible = true


func show_feedback(success: bool, score: int = -1) -> void:
	if success:
		# Success: hide challenge panel immediately, show floating toast
		challenge_panel.visible = false
		set_stt_state(_stt_state)
		_show_success_toast(score)
	else:
		# Failure: keep the phrase, the heard line, and the card up for retry.
		_mark_heard_line()
		var left := _challenge_tries_remaining
		if left > 0:
			challenge_feedback_label.text = "Not quite. %d left." % left
		else:
			challenge_feedback_label.text = "Not quite."
		challenge_feedback_label.add_theme_color_override("font_color", Color(0.55, 0.16, 0.08, 1))
		challenge_feedback_label.visible = true
		if challenge_panel and not challenge_panel.visible:
			challenge_panel.visible = true
		_feedback_token += 1
		var token := _feedback_token
		_hide_feedback_after_delay(token)


func _show_success_toast(score: int = 100) -> void:
	var plate := _ensure_success_plate()
	var label := plate.get_node("VBoxContainer/Label") as Label
	# Exact/fuzzy passes report 100 as a sentinel and stay a plain word. A real
	# phoneme score below 100 is the only pronunciation feedback the player
	# gets, so it goes on the plate.
	if score >= 100:
		label.text = "Got it!"
	else:
		label.text = "Got it! (%d)" % maxi(score, 0)
	plate.visible = true
	plate.modulate = Color(1, 1, 1, 1)

	# Back-to-back kills: the previous fade would hide this toast early.
	if _success_tween and _success_tween.is_valid():
		_success_tween.kill()
	_success_tween = create_tween()
	_success_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_success_tween.tween_interval(0.35)
	_success_tween.tween_property(plate, "modulate:a", 0.0, 0.45)
	_success_tween.finished.connect(_on_success_plate_finished.bind(plate))

	# Emit feedback_closed for the caller awaiting it
	feedback_closed.emit()


func _ensure_success_plate() -> PanelContainer:
	if _success_plate != null:
		return _success_plate
	var plate := PanelContainer.new()
	plate.name = "SuccessToast"
	plate.visible = false
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.set_anchors_preset(Control.PRESET_CENTER)
	plate.offset_left = -88.0
	plate.offset_top = -36.0
	plate.offset_right = 88.0
	plate.offset_bottom = 36.0
	var style := StyleBoxFlat.new()
	style.bg_color = CREAM
	style.border_color = Color(0.2, 0.14, 0.05, 1)
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	plate.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.name = "Label"
	label.text = "Got it"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", INK)
	var bold := load("res://gui/fonts/Abaddon Bold.ttf")
	if bold:
		label.add_theme_font_override("font", bold)
	var mark := ColorRect.new()
	mark.custom_minimum_size = Vector2(72, 6)
	mark.color = Color(0.1, 0.34, 0.18, 1)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	# _show_success_toast finds the label by this path; unnamed, Godot would
	# auto-name the node and the lookup would return null.
	column.name = "VBoxContainer"
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	column.add_child(label)
	column.add_child(mark)
	plate.add_child(column)
	var host := $Control as Control
	host.add_child(plate)
	_success_plate = plate
	return plate


func _on_success_plate_finished(plate: PanelContainer) -> void:
	plate.visible = false


func _hide_feedback_after_delay(token: int) -> void:
	# process_always=true: speech challenges pause the tree; a normal timer
	# never fires, feedback_closed never emits, and enemies stay unhittable.
	await get_tree().create_timer(FEEDBACK_DURATION, true).timeout
	if token != _feedback_token:
		# A newer feedback cycle owns the waiter now; stay silent. Only the
		# final-fail recover message may emit for a superseded token.
		return
	challenge_feedback_label.visible = false
	challenge_feedback_label.text = ""
	if not speech_challenge_label.visible:
		challenge_panel.visible = false
		target_sentence = ""
	feedback_closed.emit()


const RECOVER_FEEDBACK_DURATION := 1.4


func show_enemy_recovered() -> void:
	# Final-fail cue: the enemy heals to full, and the player must see that
	# cost spelled out instead of discovering it on the next swing.
	if challenge_panel and not challenge_panel.visible:
		challenge_panel.visible = true
	if challenge_feedback_label:
		challenge_feedback_label.text = "Out of tries — the enemy recovers!"
		challenge_feedback_label.add_theme_color_override("font_color", Color(0.55, 0.16, 0.08, 1))
		challenge_feedback_label.visible = true
	_feedback_token += 1
	var token := _feedback_token
	await get_tree().create_timer(RECOVER_FEEDBACK_DURATION, true).timeout
	if token != _feedback_token:
		feedback_closed.emit()
		return
	if challenge_feedback_label:
		challenge_feedback_label.visible = false
		challenge_feedback_label.text = ""
	if challenge_panel:
		challenge_panel.visible = false
	target_sentence = ""
	feedback_closed.emit()


const PRACTICE_NOTICE_DURATION := 1.6

var _practice_notice_label: Label = null
var _practice_notice_token: int = 0
var _practice_notice_tween: Tween = null
var _success_tween: Tween = null
## Practice notice rows: its usual spot (y 34-58) overlaps the voice banner
## (y 52-80), so it drops below the banner while that is up.
const PRACTICE_NOTICE_TOP := 34.0
const PRACTICE_NOTICE_TOP_UNDER_BANNER := 84.0


func show_practice_notice() -> void:
	# Shown when a non-horde "death" refills HP: makes the silent full heal
	# read as an intentional practice rule, not a bug.
	var control := get_node_or_null("Control") as Control
	if control == null:
		return
	if _practice_notice_label == null:
		_practice_notice_label = Label.new()
		_practice_notice_label.name = "PracticeNotice"
		_practice_notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_practice_notice_label.text = "Practice — you can't die here!"
		_practice_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_practice_notice_label.add_theme_font_size_override("font_size", 16)
		_practice_notice_label.add_theme_color_override("font_color", CREAM)
		_practice_notice_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.02, 1))
		_practice_notice_label.add_theme_constant_override("outline_size", 4)
		_practice_notice_label.anchor_left = 0.5
		_practice_notice_label.anchor_right = 0.5
		_practice_notice_label.anchor_top = 0.0
		_practice_notice_label.anchor_bottom = 0.0
		_practice_notice_label.offset_left = -180.0
		_practice_notice_label.offset_right = 180.0
		control.add_child(_practice_notice_label)
	var top := PRACTICE_NOTICE_TOP
	if voice_only_banner and voice_only_banner.visible:
		top = PRACTICE_NOTICE_TOP_UNDER_BANNER
	_practice_notice_label.offset_top = top
	_practice_notice_label.offset_bottom = top + 24.0
	_practice_notice_token += 1
	var token := _practice_notice_token
	_practice_notice_label.visible = true
	_practice_notice_label.modulate = Color(1, 1, 1, 1)
	# A second death mid-fade: the old fade would hide this notice early.
	if _practice_notice_tween and _practice_notice_tween.is_valid():
		_practice_notice_tween.kill()
	var tween := create_tween()
	_practice_notice_tween = tween
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(PRACTICE_NOTICE_DURATION)
	tween.tween_property(_practice_notice_label, "modulate:a", 0.0, 0.4)
	tween.finished.connect(func() -> void:
		if token == _practice_notice_token and _practice_notice_label != null:
			_practice_notice_label.visible = false
	)


func _style_parchment_button(button: Button) -> void:
	if button == null:
		return
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.93, 0.88, 0.78, 1)
	normal.border_color = Color(0.35, 0.24, 0.12, 1)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 6
	normal.content_margin_top = 4
	normal.content_margin_right = 6
	normal.content_margin_bottom = 4
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.82, 0.78, 0.7, 1)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", pressed)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	var bold := load("res://gui/fonts/Abaddon Bold.ttf")
	if bold:
		button.add_theme_font_override("font", bold)


func _create_tries_label() -> void:
	if challenge_vbox == null:
		return
	_tries_label = Label.new()
	_tries_label.name = "TriesLabel"
	_tries_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tries_label.add_theme_font_size_override("font_size", 18)
	_tries_label.add_theme_color_override("font_color", INK)
	challenge_vbox.add_child(_tries_label)


func _create_warmup_label() -> void:
	if challenge_vbox == null or _warmup_label != null:
		return
	_warmup_label = Label.new()
	_warmup_label.name = "WarmupLabel"
	_warmup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warmup_label.visible = false
	_warmup_label.text = ""
	var bold := load("res://gui/fonts/Abaddon Bold.ttf")
	if bold:
		_warmup_label.add_theme_font_override("font", bold)
	_warmup_label.add_theme_font_size_override("font_size", 16)
	_warmup_label.add_theme_color_override("font_color", INK)
	challenge_vbox.add_child(_warmup_label)
	# Above the "Say:" line when shown.
	challenge_vbox.move_child(_warmup_label, 0)


func _refresh_warmup_label() -> void:
	if _warmup_label == null:
		return
	var show_warmup := false
	var tracker := get_node_or_null("/root/ProgressTracker")
	var word_tracker := get_node_or_null("/root/WordTracker")
	if tracker \
			and word_tracker \
			and tracker.has_method("horde_warmup") \
			and tracker.has_method("horde_stuck_stage") \
			and bool(tracker.horde_warmup()) \
			and int(tracker.horde_stuck_stage()) == int(word_tracker.get("horde_stage")):
		show_warmup = true
	if show_warmup:
		_warmup_label.text = "Warm-up"
		_warmup_label.visible = true
	else:
		_warmup_label.text = ""
		_warmup_label.visible = false


func _create_listen_button() -> void:
	if challenge_vbox == null or _listen_row != null:
		return

	_listen_row = HBoxContainer.new()
	_listen_row.name = "ListenRow"
	_listen_row.alignment = BoxContainer.ALIGNMENT_CENTER

	_listen_button = Button.new()
	_listen_button.name = "ListenButton"
	_listen_button.text = "Listen"
	_listen_button.tooltip_text = "Hear the word"
	# Never steal focus from the typed fallback input on web.
	_listen_button.focus_mode = Control.FOCUS_NONE
	_listen_button.pressed.connect(_on_listen_pressed)
	_style_parchment_button(_listen_button)
	var bold := load("res://gui/fonts/Abaddon Bold.ttf")
	if bold:
		_listen_button.add_theme_font_override("font", bold)
	_listen_row.add_child(_listen_button)

	challenge_vbox.add_child(_listen_row)
	# Sit directly under the "Say:" line, above the transcript.
	if speech_challenge_label != null:
		challenge_vbox.move_child(_listen_row, speech_challenge_label.get_index() + 1)
	_apply_listen_button_size()
	_refresh_listen_button()


func _apply_listen_button_size() -> void:
	if _listen_button == null:
		return
	_listen_button.custom_minimum_size = Vector2(220, 48)


func _refresh_listen_button() -> void:
	if _listen_row == null or _listen_button == null:
		return

	var tts = get_node_or_null("/root/TTSManager")
	var available: bool = tts != null and tts.is_available()
	if not available and not _listen_warned:
		_listen_warned = true
		print("⚠️ PlayerHud: TTS unavailable, hiding Listen button.")

	_listen_row.visible = available and challenge_panel != null and challenge_panel.visible
	# Stays enabled while speaking: a second press restarts the phrase.
	_listen_button.disabled = (not available) or target_sentence.strip_edges().is_empty()


func _on_listen_pressed() -> void:
	var tts = get_node_or_null("/root/TTSManager")
	if tts == null or not tts.is_available():
		print("❌ PlayerHud: Listen pressed but TTS is unavailable.")
		_refresh_listen_button()
		return

	var text: String = target_sentence.strip_edges()
	if text.is_empty():
		return

	# Stop capture before any audio so the synthesizer never feeds the mic.
	# That includes the forgiveness clip: a TTS rendition of the target would
	# score ~100 against the target phonemes and hand out a free pass.
	_drop_scorer_clip(target_sentence)
	var stt = get_node_or_null("/root/STTManager")
	if stt != null and stt.has_method("end_challenge_listen"):
		stt.end_challenge_listen()

	# Invalidate the previous press before stopping so its finish cannot
	# re-arm the mic for this one.
	_listen_token += 1
	_listen_pending = false
	tts.stop()
	_listen_pending_token = _listen_token
	_listen_pending = true
	_refresh_listen_button()

	if not tts.speech_finished.is_connected(_on_tts_speech_finished):
		tts.speech_finished.connect(_on_tts_speech_finished)

	# Keep this synchronous: web speech synthesis needs the button's user gesture.
	var ok: bool = tts.speak(text)
	if not ok:
		print("❌ PlayerHud: Listen failed, re-arming mic.")
		_listen_pending = false
		_rearm_challenge_capture(_listen_pending_token)
		_refresh_listen_button()
		return
	print("✅ PlayerHud: speaking target phrase for listening mode.")


func _on_tts_speech_finished() -> void:
	if not _listen_pending:
		return
	_listen_pending = false
	_rearm_challenge_capture(_listen_pending_token)
	_refresh_listen_button()


func _rearm_challenge_capture(token: int) -> void:
	if token != _listen_token:
		return
	if target_sentence.strip_edges().is_empty():
		return
	if challenge_panel == null or not challenge_panel.visible:
		return
	var word_tracker = get_node_or_null("/root/WordTracker")
	if word_tracker != null and not bool(word_tracker.speech_challenge_active):
		return
	var stt = get_node_or_null("/root/STTManager")
	if stt != null and stt.has_method("begin_challenge_listen"):
		stt.begin_challenge_listen()
	# Fresh clip for the post-TTS attempt, so the forgiveness pass scores the
	# player and not the synthesizer.
	_restart_scorer_clip()


func _drop_scorer_clip(target: String) -> void:
	var pm := get_node_or_null("/root/PronunciationManager")
	if pm == null or not pm.has_method("can_score") or not pm.can_score(target):
		return
	var scorer = pm.get_scorer()
	if scorer != null and scorer.has_method("abandon_capture") and scorer.is_capturing():
		scorer.abandon_capture()


func _restart_scorer_clip() -> void:
	if target_sentence.strip_edges().is_empty():
		return
	var pm := get_node_or_null("/root/PronunciationManager")
	if pm == null or not pm.has_method("can_score") or not pm.can_score(target_sentence):
		return
	var scorer = pm.get_scorer()
	if scorer != null and scorer.has_method("begin_capture") and not scorer.is_capturing():
		scorer.begin_capture()


func _stop_tts() -> void:
	_listen_token += 1
	_listen_pending = false
	var tts = get_node_or_null("/root/TTSManager")
	if tts != null:
		tts.stop()
	if _listen_button != null:
		_refresh_listen_button()


func set_challenge_tries(remaining: int) -> void:
	_challenge_tries_remaining = remaining
	if _tries_label == null:
		return
	if remaining <= 0:
		_tries_label.text = ""
		_tries_label.visible = false
		return
	_tries_label.text = "Tries: " + str(remaining)
	_tries_label.visible = true


func show_score_feedback(score: int, tries_left: int) -> void:
	# Score-based verdict for a speech challenge attempt (Task 10 wires real
	# phoneme scores in; thresholds mirror the planned 75 pass mark).
	var verdict := "Not quite — try again!"
	var color := Color(0.8, 0.15, 0.08, 1)
	if score >= 75:
		verdict = "Good enough! (score %d)" % score
		color = Color(0.05, 0.45, 0.15, 1)
	elif score >= 50:
		verdict = "Close! (score %d) — try again" % score
		color = Color(0.95, 0.75, 0.1, 1)
	if challenge_feedback_label != null:
		challenge_feedback_label.text = verdict
		challenge_feedback_label.add_theme_color_override("font_color", color)
		challenge_feedback_label.visible = true


func _create_challenge_status_label() -> void:
	if challenge_vbox == null or _challenge_status_label != null:
		return
	_challenge_status_label = Label.new()
	_challenge_status_label.name = "ChallengeStatus"
	_challenge_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_challenge_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_challenge_status_label.add_theme_font_size_override("font_size", 16)
	_challenge_status_label.add_theme_color_override("font_color", INK)
	var bold := load("res://gui/fonts/Abaddon Bold.ttf")
	if bold:
		_challenge_status_label.add_theme_font_override("font", bold)
	_challenge_status_label.visible = false
	challenge_vbox.add_child(_challenge_status_label)
	challenge_vbox.move_child(_challenge_status_label, 0)


func _create_stt_indicator() -> void:
	var control := get_node_or_null("Control") as Control
	if control == null:
		return

	_stt_plate = PanelContainer.new()
	_stt_plate.name = "SttIndicator"
	_stt_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stt_plate.anchor_left = 1.0
	_stt_plate.anchor_right = 1.0
	_stt_plate.anchor_top = 0.0
	_stt_plate.anchor_bottom = 0.0
	_stt_plate.offset_left = -176.0
	_stt_plate.offset_top = 8.0
	_stt_plate.offset_right = -8.0
	_stt_plate.offset_bottom = 36.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.9)
	style.border_color = Color(0.92, 0.92, 0.88, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	_stt_plate.add_theme_stylebox_override("panel", style)

	_stt_indicator_row = HBoxContainer.new()
	_stt_indicator_row.name = "SttIndicatorRow"
	_stt_indicator_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_stt_indicator_row.add_theme_constant_override("separation", 6)

	_stt_dot = ColorRect.new()
	_stt_dot.name = "SttDot"
	_stt_dot.custom_minimum_size = Vector2(14, 14)
	_stt_indicator_row.add_child(_stt_dot)

	_stt_label = Label.new()
	_stt_label.name = "SttLabel"
	_stt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_stt_label.add_theme_font_size_override("font_size", 14)
	_stt_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.92, 1))
	_stt_label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.02, 1))
	_stt_label.add_theme_constant_override("outline_size", 3)
	_stt_indicator_row.add_child(_stt_label)

	_stt_plate.add_child(_stt_indicator_row)
	control.add_child(_stt_plate)
	set_stt_state(SttState.STT_IDLE)


func _challenge_status_text(state: SttState) -> String:
	match state:
		SttState.STT_LISTENING:
			return "Listening"
		SttState.STT_PROCESSING:
			return "Processing"
		SttState.STT_ERROR:
			return "Mic blocked — type it or tap Speak"
		SttState.STT_UNAVAILABLE:
			return "Mic unavailable — type the phrase"
		_:
			return ""


func set_stt_state(state: SttState) -> void:
	_stt_state = state
	var on_card := challenge_panel != null and challenge_panel.visible
	if _stt_plate:
		_stt_plate.visible = not on_card
	if _challenge_status_label:
		var status := _challenge_status_text(state)
		_challenge_status_label.text = status
		_challenge_status_label.visible = on_card and not status.is_empty()

	if _stt_indicator_row == null or _stt_dot == null or _stt_label == null:
		return

	if _stt_tween and _stt_tween.is_valid():
		_stt_tween.kill()
	_stt_tween = null

	match state:
		SttState.STT_IDLE:
			_stt_dot.visible = true
			_stt_label.visible = true
			_stt_label.text = "Mic off"
			_stt_dot.color = Color(0.4, 0.4, 0.4, 1)
			_stt_dot.modulate = Color(1, 1, 1, 1)

		SttState.STT_LISTENING:
			_stt_dot.visible = true
			_stt_label.visible = true
			_stt_label.text = "Listening"
			_stt_dot.color = Color(0.9, 0.15, 0.15, 1)
			_stt_dot.modulate = Color(1, 1, 1, 1)
			_stt_tween = _stt_dot.create_tween()
			_stt_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			_stt_tween.set_loops()
			_stt_tween.tween_property(_stt_dot, "modulate:a", 0.35, 0.5)
			_stt_tween.tween_property(_stt_dot, "modulate:a", 1.0, 0.5)

		SttState.STT_PROCESSING:
			_stt_dot.visible = true
			_stt_label.visible = true
			_stt_label.text = "Processing"
			_stt_dot.color = Color(0.95, 0.75, 0.1, 1)
			_stt_dot.modulate = Color(1, 1, 1, 1)

		SttState.STT_ERROR:
			_stt_dot.visible = true
			_stt_label.visible = true
			_stt_label.text = "Mic error"
			_stt_dot.color = Color(0.8, 0.1, 0.1, 1)
			_stt_dot.modulate = Color(1, 1, 1, 1)

		SttState.STT_UNAVAILABLE:
			_stt_dot.visible = true
			_stt_label.visible = true
			_stt_label.text = "Mic unavailable"
			_stt_dot.color = Color(0.5, 0.5, 0.5, 1)
			_stt_dot.modulate = Color(1, 1, 1, 1)


func set_mic_state(listening: bool) -> void:
	if listening:
		set_stt_state(SttState.STT_LISTENING)
	else:
		set_stt_state(SttState.STT_IDLE)
