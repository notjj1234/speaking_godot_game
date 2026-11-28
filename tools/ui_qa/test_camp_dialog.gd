extends "res://tools/ui_qa/pointer_driver.gd"
## DialogSystem conversation mode (camp NPCs). Run headless:
##   python3.13 tools/ui_qa/run_headless_tests.py

var left := 0
var picks: Array[String] = []


func centre(item: CanvasItem) -> Vector2:
	return item.get_global_transform_with_canvas() * UiInputRouter.local_rect(item).get_center()


## Click the middle of a node, after letting the 80 ms twin window lapse.
func press(item: CanvasItem) -> void:
	await get_tree().create_timer(0.12, true).timeout
	await click(centre(item))


func send_action(action: StringName) -> void:
	for down in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = down
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await frames()


func _ready() -> void:
	get_window().size = Vector2i(640, 480)
	await frames(10)
	await _conversation_basics()
	await _cancel_closes()
	await _linear_still_advances()
	await _say_box()
	finish()


func _conversation_basics() -> void:
	DialogSystem.show_conversation("Smith", null, 1, func(): left += 1)
	await frames()
	check("conv: dialog open", DialogSystem.is_open, true)
	check("conv: player frozen", PlayerManager.dialog_open, true)
	check("conv: in conversation mode", DialogSystem.is_conversation(), true)
	DialogSystem.set_conversation_line("Back from the dead?")
	await send_action(&"interact")
	check("conv: interact does not close", DialogSystem.is_open, true)

	DialogSystem.set_choices([{"id": "yes", "label": "Yes"}, {"id": "no", "label": "No"}],
		func(id: String): picks.append(id))
	await frames(4)
	await press(DialogSystem.choice_row.get_child(0))
	check("conv: one press picks one chip", picks, ["yes"] as Array[String])

	await press(DialogSystem.leave_button)
	check("conv: Leave closes", DialogSystem.is_open, false)
	check("conv: Leave unfreezes player", PlayerManager.dialog_open, false)
	check("conv: Leave calls on_leave once", left, 1)
	check("conv: layer popped", UiInputRouter.active_layer(), 0)
	check("conv: mode cleared", DialogSystem.is_conversation(), false)


func _cancel_closes() -> void:
	left = 0
	DialogSystem.show_conversation("Cook", null, 1, func(): left += 1)
	await frames()
	await send_action(&"ui_cancel")
	check("conv: ui_cancel closes", DialogSystem.is_open, false)
	check("conv: ui_cancel calls on_leave once", left, 1)


func _linear_still_advances() -> void:
	DialogSystem.show_dialog("A", null, PackedStringArray(["one", "two"]), Callable(), 1)
	await frames()
	await send_action(&"interact")
	check("linear: interact advances", DialogSystem._index, 1)
	DialogSystem.close()
	await frames()


## The Say-it box sits above the dialog bar, inside the 640x480 design, and its
## Cancel is one press through the router.
func _say_box() -> void:
	var cancels := {"n": 0}
	var on_cancel := func(): cancels["n"] += 1
	DialogSystem.say_cancelled.connect(on_cancel)
	DialogSystem.show_conversation("Cook", null, 1, func(): left += 1)
	DialogSystem.set_conversation_line("Hungry?")
	DialogSystem.set_choices([{"id": "apple", "label": "A  Apple (2)"}, {"id": "potion", "label": "B  Potion (4)"}],
		func(_id: String): pass)
	DialogSystem.show_say_box("B", "Potion")
	await frames(4)
	var box := DialogSystem.say_box.get_global_rect()
	check("say box: open", DialogSystem.is_say_box_open(), true)
	check("say box: inside the 640x480 design", Rect2(0, 0, 640, 480).encloses(box), true)
	check("say box: above the dialog bar", box.end.y <= DialogSystem.dialog_bar.get_global_rect().position.y, true)
	check("say box: title names the letter", DialogSystem.say_title_label.text, "B - say it:")
	await press(DialogSystem.say_cancel_button)
	check("say box: Cancel closes the box", DialogSystem.is_say_box_open(), false)
	check("say box: Cancel fires once", cancels["n"], 1)
	check("say box: dialog stays open", DialogSystem.is_open, true)
	DialogSystem.say_cancelled.disconnect(on_cancel)
	DialogSystem.close()
	await frames()
