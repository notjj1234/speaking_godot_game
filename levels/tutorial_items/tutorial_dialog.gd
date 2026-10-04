# tutorial_dialog.gd

class_name TutorialDialog extends Control

const BANNER_WIDTH := 520.0
const BANNER_HEIGHT := 84.0
const TOP_MARGIN := 12.0
const INK := Color(0.12, 0.08, 0.04, 1)
const BUBBLE := preload("res://gui/dialog_system/sprites/text-bubble.png")
const BODY_FONT := preload("res://gui/fonts/Abaddon Light.ttf")

@onready var dialog_label: Label = $DialogBackground/DialogLabel
@onready var dialog_panel := $DialogBackground
@onready var current_level := get_tree().current_scene.name

var tutorial_messages := {
	"01": [
		"In this level, you will see some slimes.",
		"Kill them and see what happens."
	],
	"02": [
		"Keyboard and mouse movement are locked.",
		"Use your voice to go to the next level!",
		"On a phone, arrows appear if voice fails a few times.",
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
	_apply_banner_style()
	_apply_banner_layout()
	call_deferred("_apply_banner_layout")
	_hide_duplicate_hud_chrome()

	if current_level == "Playground":
		messages = _playground_messages()
	elif tutorial_messages.has(current_level):
		messages = tutorial_messages[current_level] as Array[String]
		if current_level == "02":
			auto_advance = true
			persistent = true
	else:
		messages = ["No tutorial available for this level."]

	show_message(current_index)

	if auto_advance:
		advance_timer = Timer.new()
		advance_timer.wait_time = 4.0
		advance_timer.one_shot = false
		advance_timer.connect("timeout", _on_timer_timeout)
		add_child(advance_timer)
		advance_timer.start()


func _playground_messages() -> Array:
	if MobileSafeLayout.wants_touch_ui():
		return [
			"Welcome to Loqui Quest's tutorial level!",
			"Try walking around using the on-screen arrows.",
			"Use the Attack button to destroy the bushes!",
			"To pick up items, just run over them.",
			"When you are ready, you can move on to the next level.",
		]
	return [
		"Welcome to Loqui Quest's tutorial level!",
		"Try walking around using WASD or the arrow keys.",
		"Use comma or J to attack.",
		"To pick up items, just run over them.",
		"Nearby people are friendly. Press E to talk.",
		"When you are ready, you can move on to the next level.",
	]


func _apply_banner_style() -> void:
	if dialog_panel:
		dialog_panel.modulate = Color.WHITE
		var style := StyleBoxTexture.new()
		style.texture = BUBBLE
		style.content_margin_left = 14.0
		style.content_margin_top = 12.0
		style.content_margin_right = 14.0
		style.content_margin_bottom = 12.0
		style.texture_margin_left = 16.0
		style.texture_margin_top = 16.0
		style.texture_margin_right = 16.0
		style.texture_margin_bottom = 16.0
		dialog_panel.add_theme_stylebox_override("panel", style)
	if dialog_label:
		dialog_label.add_theme_font_override("font", BODY_FONT)
		dialog_label.add_theme_color_override("font_color", INK)
		dialog_label.add_theme_font_size_override("font_size", 15)
		dialog_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dialog_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dialog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _apply_banner_layout() -> void:
	var top := 88.0 if current_level == "02" else TOP_MARGIN
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -BANNER_WIDTH * 0.5
	offset_right = BANNER_WIDTH * 0.5
	offset_top = top
	offset_bottom = top + BANNER_HEIGHT

	if dialog_panel:
		dialog_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		dialog_panel.offset_left = 0
		dialog_panel.offset_top = 0
		dialog_panel.offset_right = 0
		dialog_panel.offset_bottom = 0
		dialog_panel.custom_minimum_size = Vector2.ZERO
	if dialog_label:
		dialog_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		dialog_label.offset_left = 14
		dialog_label.offset_top = 10
		dialog_label.offset_right = -14
		dialog_label.offset_bottom = -10


func _hide_duplicate_hud_chrome() -> void:
	var parent_hud := get_parent()
	if parent_hud == null:
		return
	var autoload := get_node_or_null("/root/PlayerHud")
	if autoload != null and parent_hud == autoload:
		return
	var sprite := parent_hud.get_node_or_null("Control/Sprite2D")
	if sprite:
		sprite.visible = false
	var hearts_row := parent_hud.get_node_or_null("Control/HFlowContainer")
	if hearts_row:
		hearts_row.visible = false
	var voice_banner := parent_hud.get_node_or_null("Control/VoiceOnlyBanner")
	if voice_banner:
		voice_banner.visible = false

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
	if PlayerManager.dialog_open:
		return
	if event.is_action_pressed("ui_accept") and visible:
		next_message()

func show_custom_message(text: String, persist := false):
	dialog_label.text = text
	visible = true
	if advance_timer:
		advance_timer.stop()
	persistent = persist
