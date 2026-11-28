extends Node2D
## GuidePointer: a bobbing arrow over a world target, an edge arrow when the
## target is off screen, a pulsing ring around a button, nothing for null, and
## it stays out of the pause menu.

var passes := 0
var failures := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _frames(n: int = 2) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	await _frames(4)  # let the player camera settle
	var view := get_viewport().get_visible_rect()
	# World point drawn at the screen centre (the player camera moves the canvas).
	var mid := get_viewport().get_canvas_transform().affine_inverse() * view.get_center()
	var pointer := GuidePointer.new()
	add_child(pointer)

	_check("idle: nothing shown", pointer.current_kind() == &"" and not pointer.is_showing())

	var target := Node2D.new()
	add_child(target)
	target.global_position = mid
	pointer.follow(func(): return target)
	await _frames()
	_check("on-screen world target: bobbing arrow", pointer.current_kind() == &"world", str(pointer.current_kind()))
	var tip := pointer.arrow_position()
	_check("arrow sits just above the target", tip.y < view.get_center().y and tip.y > view.get_center().y - 90.0
		and absf(tip.x - view.get_center().x) < 2.0, str(tip))

	target.global_position = mid + Vector2(2000, 0)
	await _frames()
	_check("off-screen target: edge arrow", pointer.current_kind() == &"edge", str(pointer.current_kind()))
	var edge := pointer.arrow_position()
	_check("edge arrow stays on screen", view.grow(-20.0).has_point(edge), str(edge))
	_check("edge arrow points toward the target", absf(wrapf(pointer.arrow_angle(), -PI, PI)) < 0.3,
		str(pointer.arrow_angle()))

	pointer.follow(func(): return mid + Vector2(0, -3000))
	await _frames()
	_check("world point above: edge arrow points up", pointer.current_kind() == &"edge"
		and absf(wrapf(pointer.arrow_angle() + PI / 2.0, -PI, PI)) < 0.3, str(pointer.arrow_angle()))

	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var button := Button.new()
	button.position = Vector2(100, 100)
	button.size = Vector2(80, 44)
	layer.add_child(button)
	pointer.follow(func(): return button)
	await _frames()
	_check("button: pulsing ring", pointer.current_kind() == &"ui", str(pointer.current_kind()))
	_check("ring centred on the button", pointer.ring_rect().get_center().distance_to(Vector2(140, 122)) < 2.0,
		str(pointer.ring_rect()))
	_check("pointer never takes taps", pointer.overlay_mouse_filter() == Control.MOUSE_FILTER_IGNORE)
	_check("rectangular control: hugging frame, not a circle", pointer.is_wide_ring())

	button.visible = false
	await _frames()
	_check("hidden button: nothing shown", pointer.current_kind() == &"", str(pointer.current_kind()))

	pointer.follow(func(): return null)
	await _frames()
	_check("null: nothing shown", not pointer.is_showing())

	pointer.follow(func(): return target)
	target.global_position = mid
	PauseMenu.show_pause_menu()
	await _frames()
	_check("pause menu open: hidden", not pointer.is_showing())
	PauseMenu.hide_pause_menu()
	await _frames()
	_check("pause menu closed: back", pointer.is_showing() and pointer.current_kind() == &"world")

	# A speech challenge pauses the game: only button rings stay up.
	get_tree().paused = true
	await _frames()
	_check("paused for a challenge: world arrow hidden", not pointer.is_showing())
	button.visible = true
	pointer.follow(func(): return button)
	await _frames()
	_check("paused for a challenge: button ring shown", pointer.is_showing() and pointer.current_kind() == &"ui")
	get_tree().paused = false

	pointer.clear()
	await _frames()
	_check("clear: nothing shown", not pointer.is_showing() and pointer.current_kind() == &"")

	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
