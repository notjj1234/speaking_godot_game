class_name MuteLook
extends RefCounted
## The one look for a muted audio row (Settings and the pause menu): the
## button says "Unmute" in a red tint and its slider is dimmed.

const MUTED_TINT := Color(1.0, 0.55, 0.55)
const MUTED_SLIDER_ALPHA := 0.45


static func apply(button: Button, slider: Range, muted: bool) -> void:
	if button:
		button.text = "Unmute" if muted else "Mute"
		button.modulate = MUTED_TINT if muted else Color.WHITE
	if slider:
		slider.modulate.a = MUTED_SLIDER_ALPHA if muted else 1.0
