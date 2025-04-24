extends Control

@onready var label = $Panel/Label
@onready var button = $Panel/Button

signal popup_closed

func set_text(text: String) -> void:
	label.text = text

func _ready() -> void:
	button.pressed.connect(_on_button_pressed)

func _on_button_pressed() -> void:
	visible = false
	emit_signal("popup_closed")
