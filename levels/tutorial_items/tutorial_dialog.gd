# tutorial_dialog.gd

class_name TutorialDialog extends Control

@onready var dialog_label: Label = $DialogBackground/DialogLabel
@onready var dialog_panel := $DialogBackground
@onready var current_level := get_tree().current_scene.name

var tutorial_messages := {
	"Playground": [
		"Welcome to xxxxx Game's tutorial level!",
		"Try walking around using the Arrow buttons.",
		"Use the Attack button to destroy the bushes!",
		"To pick up items just run over it.",
		"When you are ready, you can move on to the next level."
	],
	"01": [
		"In this level, you will see some slimes.",
		"Kill them and see what happens."
	],
	"02": [
		"Oh no! Your movement and attack buttons are gone!",
		"Use your voice to go to the next level!",
	],
	"03": [
		"Kill the goblin!",
		"Don't worry you can't die in the tutorial."
	],
}

# Persistent help for level 02
var persistent_help := {
	"02": [
		"These are the commands",
		"move forward, move backwards, move left, move right"
	]
}

var messages = []
var current_index := 0
var auto_advance := true
var persistent := false
var advance_timer: Timer = null

func _ready():
	print("Current level name: ", current_level)
	if tutorial_messages.has(current_level):
		messages = tutorial_messages[current_level] as Array[String]

		# Set persistent and disable auto-advance for help-only mode
		if current_level == "02":
			auto_advance = true
			persistent = true
	else:
		messages = ["No tutorial available for this level."]

	show_message(current_index)
	dialog_label.add_theme_color_override("font_color", Color.WHITE)

	if auto_advance:
		advance_timer = Timer.new()
		advance_timer.wait_time = 4.0
		advance_timer.one_shot = false
		advance_timer.connect("timeout", _on_timer_timeout)
		add_child(advance_timer)
		advance_timer.start()

func show_message(index: int):
	if index >= 0 and index < messages.size():
		dialog_label.text = messages[index]
		visible = true
	else:
		if persistent and persistent_help.has(current_level):
			# Once normal messages are done, switch to persistent help
			dialog_label.text = "\n".join(persistent_help[current_level])
			visible = true
			if advance_timer:
				advance_timer.stop()
		else:
			hide_message()

func next_message():
	current_index += 1
	if current_index < messages.size():
		show_message(current_index)
	else:
		show_message(current_index)  # Handles switching to persistent help or hiding

func hide_message():
	visible = false
	if advance_timer:
		advance_timer.stop()

func _on_timer_timeout():
	next_message()

func _input(event):
	if event.is_action_pressed("ui_accept") and visible:
		next_message()

func show_custom_message(text: String, persist := false):
	dialog_label.text = text
	visible = true
	if advance_timer:
		advance_timer.stop()
	persistent = persist
