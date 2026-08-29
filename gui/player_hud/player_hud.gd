# player_hud.gd

class_name PlayerHudUI
extends CanvasLayer

signal fallback_submitted(text: String)
signal speak_pressed

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


func _ready() -> void:
	for child in $Control/HFlowContainer.get_children():
		if child is HeartGUI:
			hearts.append(child)
			child.visible = false
	hide_speech_challenge()
	challenge_fallback_submit.pressed.connect(_on_fallback_submit_pressed)
	challenge_fallback_input.text_submitted.connect(_on_fallback_text_submitted)
	challenge_speak_button.pressed.connect(_on_speak_pressed)


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
		show_typed_fallback()
		show_speak_button()
	else:
		hide_typed_fallback()
		hide_speak_button()


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

	if transcript.strip_edges() == target_sentence.strip_edges():
		if has_node("/root/WordTracker"):
			var word_tracker = get_node("/root/WordTracker")
			word_tracker.add_spoken_word(transcript)
		else:
			print("Error: WordTracker singleton not found! Cannot store the word.")


func show_feedback(success: bool) -> void:
	if not success:
		live_transcript_label.text = ""
	challenge_feedback_label.text = "Success!" if success else "Try Again!"
	challenge_feedback_label.visible = true
	if not challenge_panel.visible:
		challenge_panel.visible = true
		speech_challenge_label.visible = false
		live_transcript_label.visible = false
		hide_typed_fallback()
	_feedback_token += 1
	var token := _feedback_token
	_hide_feedback_after_delay(token)


func _hide_feedback_after_delay(token: int) -> void:
	await get_tree().create_timer(2.0).timeout
	if token != _feedback_token:
		return
	challenge_feedback_label.visible = false
	challenge_feedback_label.text = ""
	if not speech_challenge_label.visible:
		challenge_panel.visible = false
		target_sentence = ""
