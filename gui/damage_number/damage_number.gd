class_name DamageNumber
extends Node2D

const FONT := preload("res://gui/fonts/Abaddon Bold.ttf")


static func spawn(at: Vector2, amount: int, crit: bool, parent: Node) -> void:
	if parent == null or amount <= 0:
		return
	var popup := DamageNumber.new()
	popup.z_index = 40
	popup.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(popup)
	popup.global_position = at
	popup._show(amount, crit)


func _show(amount: int, crit: bool) -> void:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.02, 1))
	label.add_theme_constant_override("outline_size", 5)
	if crit:
		label.text = "CRIT -%d" % amount
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color(1, 0.86, 0.25, 1))
		scale = Vector2(1.15, 1.15)
	else:
		label.text = "-%d" % amount
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(0.98, 0.96, 0.9, 1))
	label.position = Vector2(-28, -8)
	add_child(label)

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "position", position + Vector2(0, -26), 0.65)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.3)
	tween.finished.connect(queue_free)
