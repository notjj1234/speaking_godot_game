extends Node
## Shared base for the headless input tests: drives the real engine input
## pipeline (including emulate_touch_from_mouse) and counts check results.

var failures := 0
var passes := 0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func check(label: String, got: Variant, want: Variant) -> void:
	if got == want:
		passes += 1
		print("PASS ", label)
	else:
		failures += 1
		print("FAIL ", label, "  got=", got, " want=", want)


func frames(count: int = 3) -> void:
	for i in count:
		await get_tree().process_frame


## A physical mouse button edge in viewport coordinates. The engine adds the
## emulated ScreenTouch itself.
func mouse(pos: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	ev.pressed = down
	ev.position = get_tree().root.get_final_transform() * pos
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await frames()


func click(pos: Vector2) -> void:
	await mouse(pos, true)
	await mouse(pos, false)


## A finger edge, as a phone browser delivers it (no mouse twin).
func touch(pos: Vector2, down: bool, index: int = 0, canceled: bool = false) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = down
	ev.canceled = canceled
	ev.position = get_tree().root.get_final_transform() * pos
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await frames()


func tap(pos: Vector2, index: int = 0) -> void:
	await touch(pos, true, index)
	await touch(pos, false, index)


func move_mouse(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = get_tree().root.get_final_transform() * pos
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await frames()


func key_accept() -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ENTER
		ev.physical_keycode = KEY_ENTER
		ev.pressed = down
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await frames()


func finish() -> void:
	print("RESULT passes=", passes, " failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)
