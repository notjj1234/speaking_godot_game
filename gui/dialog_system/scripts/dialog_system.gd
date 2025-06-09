@tool
@icon("res://gui/dialog_system/icons/star_bubble.svg")
class_name DialogSystemNode extends CanvasLayer

func _ready():
	if Engine.is_editor_hint():
		visible = false  # or queue_free() if you prefer
		return
