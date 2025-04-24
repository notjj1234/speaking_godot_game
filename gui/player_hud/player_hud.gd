# player_hud.gd

class_name PlayerHudUI
extends CanvasLayer

var hearts: Array[HeartGUI] = []
var target_sentence: String = ""  # Added to store the target sentence for validation

@onready var speech_challenge_label: Label = $Control/SpeechChallengeLabel
@onready var live_transcript_label: Label = $Control/LiveTranscriptLabel
@onready var challenge_feedback_label: Label = $Control/ChallengeFeedbackLabel

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for child in $Control/HFlowContainer.get_children():
		if child is HeartGUI:
			hearts.append(child)
			child.visible = false
	live_transcript_label.visible = false  # Initially hide the live transcript label
	challenge_feedback_label.visible = false  # Initially hide the challenge feedback label
	pass

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

# Show the target sentence during the speech challenge
func show_speech_challenge(sentence: String) -> void:
	target_sentence = sentence  # Save the sentence for comparison
	speech_challenge_label.text = "Say: " + sentence
	speech_challenge_label.visible = true
	live_transcript_label.text = ""  # Clear any previous transcript
	live_transcript_label.visible = true  # Show the live transcript label during the challenge
	challenge_feedback_label.visible = false  # Hide feedback while the challenge is active

# Hide the target sentence and transcript after the challenge
func hide_speech_challenge() -> void:
	speech_challenge_label.visible = false
	live_transcript_label.visible = false  # Hide the live transcript label

# Update the live transcript dynamically
func update_live_transcript(transcript: String) -> void:
	live_transcript_label.text = transcript
	live_transcript_label.visible = true
	print("Live transcription updated: ", transcript)
	
	if transcript.strip_edges() == target_sentence.strip_edges():
		if has_node("/root/WordTracker"):  # Fix: Use get_node instead of Engine.get_singleton
			var word_tracker = get_node("/root/WordTracker")
			word_tracker.add_spoken_word(transcript)
		else:
			print("Error: WordTracker singleton not found! Cannot store the word.")

# Show feedback after the challenge
func show_feedback(success: bool) -> void:
	challenge_feedback_label.text = "Success!" if success else "Try Again!"
	challenge_feedback_label.visible = true
	call_deferred("_hide_feedback_after_delay")  # Use deferred call to ensure tree access

# Helper function to hide feedback after a delay
func _hide_feedback_after_delay() -> void:
	await get_tree().create_timer(2.0).timeout  # Wait for 2 seconds before hiding feedback
	challenge_feedback_label.visible = false
	target_sentence = ""  # Clear the saved sentence
