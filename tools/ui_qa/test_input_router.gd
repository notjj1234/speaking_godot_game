extends "res://tools/ui_qa/pointer_driver.gd"
## Behaviour tests for UiInputRouter. Run headless:
##   python3.13 tools/ui_qa/run_headless_tests.py

const A := Vector2(60, 60)    # button a only
const BOTH := Vector2(140, 60) # a and b overlap here; b is later in the tree
const B := Vector2(220, 60)   # button b only
const C := Vector2(400, 60)
const EMPTY := Vector2(600, 400)

var router: Node
## All real UI sits on a CanvasLayer; without one the player camera shifts hit rects.
var ui := CanvasLayer.new()
var hits: Dictionary = {}
var unhandled_mouse := 0
var action_events: Array[String] = []
var suppress_calls: Array[bool] = []


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		unhandled_mouse += 1
	if event is InputEventAction and event.action == &"attack":
		action_events.append("down" if event.pressed else "up")


## Stands in for TouchControls: the router must tell this group about overlays.
func set_gameplay_suppressed(value: bool) -> void:
	suppress_calls.append(value)


func _count(key: String) -> void:
	hits[key] = int(hits.get(key, 0)) + 1


func _hit_a() -> void: _count("a")
func _hit_b() -> void: _count("b")
func _hit_c() -> void: _count("c")
func _hit_top() -> void: _count("top")


func _button(label: String, rect: Rect2, parent: Node = null) -> Button:
	var button := Button.new()
	button.name = label
	button.position = rect.position
	button.size = rect.size
	(parent if parent else ui).add_child(button)
	return button


func _reset() -> void:
	hits.clear()
	# Let the 80 ms twin window lapse between cases.
	await get_tree().create_timer(0.12, true).timeout


func _ready() -> void:
	get_window().size = Vector2i(640, 480)
	await frames(5)
	router = get_node_or_null("/root/UiInputRouter")
	check("autoload UiInputRouter exists", router != null, true)
	if router == null:
		finish()
		return
	add_to_group("touch_controls")
	add_child(ui)

	var a := _button("a", Rect2(20, 20, 160, 80))
	var b := _button("b", Rect2(100, 20, 160, 80))
	var c := _button("c", Rect2(360, 20, 100, 80))
	router.bind_button(a, _hit_a)
	router.bind_button(b, _hit_b)
	router.bind_button(c, _hit_c)
	await frames()
	check("bind() makes the control mouse_filter IGNORE", a.mouse_filter, Control.MOUSE_FILTER_IGNORE)

	var dimmer := ColorRect.new()
	ui.add_child(dimmer)
	router.bind(dimmer, _hit_c)
	check("bind() leaves a bound dimmer STOP so it still blocks GUI below",
			dimmer.mouse_filter, Control.MOUSE_FILTER_STOP)
	dimmer.free()
	await frames()

	await _reset()
	await click(A)
	check("desktop click activates exactly once", hits, {"a": 1})

	await _reset()
	await tap(A)
	check("finger tap activates exactly once", hits, {"a": 1})

	await _reset()
	await mouse(A, true)
	check("nothing activates on press", hits, {})
	await mouse(A, false)
	check("activates on release", hits, {"a": 1})

	await _reset()
	await click(A)
	await click(A)
	check("two quick clicks are two activations", hits, {"a": 2})

	await _reset()
	await mouse(A, true)
	await mouse(C, false)
	check("release outside the claimed region does nothing", hits, {})

	await _reset()
	await touch(A, true)
	await touch(A, false, 0, true)
	check("canceled touch does nothing", hits, {})

	await _reset()
	await click(BOTH)
	check("overlap: later in tree order wins, only one fires", hits, {"b": 1})

	await _reset()
	a.z_index = 2
	await click(BOTH)
	check("overlap: higher z_index beats tree order", hits, {"a": 1})
	a.z_index = 0

	var overlay := CanvasLayer.new()
	overlay.layer = 5
	add_child(overlay)
	move_child(overlay, 0)  # earlier in the tree than the base buttons
	var top := _button("top", Rect2(20, 20, 160, 80), overlay)
	router.bind_button(top, _hit_top)
	await _reset()
	await click(A)
	check("overlap: higher CanvasLayer beats tree order", hits, {"top": 1})
	overlay.visible = false
	await _reset()
	await click(A)
	check("hidden CanvasLayer is inert", hits, {"a": 1})
	overlay.queue_free()
	await frames()

	b.visible = false
	await _reset()
	await click(BOTH)
	check("hidden region is inert", hits, {"a": 1})
	b.visible = true
	b.disabled = true
	await _reset()
	await click(B)
	check("disabled region is inert", hits, {})
	b.disabled = false
	await _reset()
	await mouse(B, true)
	b.disabled = true
	await mouse(B, false)
	check("disabled between press and release does nothing", hits, {})
	b.disabled = false

	await _reset()
	unhandled_mouse = 0
	await click(EMPTY)
	check("a miss is not consumed (world click reaches gameplay)", unhandled_mouse, 1)
	await _reset()
	unhandled_mouse = 0
	await click(A)
	check("a hit is consumed, including its mouse twin", unhandled_mouse, 0)

	await _reset()
	await touch(A, true, 0)
	await touch(C, true, 1)
	await touch(A, false, 0)
	await touch(C, false, 1)
	check("two fingers on two regions both work", hits, {"a": 1, "c": 1})

	await _reset()
	await touch(A, true, 0)
	await touch(A + Vector2(20, 0), true, 1)
	await touch(A, false, 0)
	await touch(A + Vector2(20, 0), false, 1)
	check("two fingers on one region activate once", hits, {"a": 1})

	# --- layers -------------------------------------------------------------
	suppress_calls.clear()
	var panel := _button("modal_button", Rect2(360, 200, 120, 60))
	var layer: int = router.push_layer(&"test_modal", panel)
	router.bind_button(panel, _hit_top, layer)
	await _reset()
	await click(A)
	check("a lower layer is inert while a layer is open", hits, {})
	await click(Vector2(420, 230))
	check("the top layer is live", hits, {"top": 1})
	check("gameplay is suppressed on push", suppress_calls.back() if suppress_calls else null, true)
	router.pop_layer(layer)
	check("gameplay is restored on pop", suppress_calls.back(), false)
	await _reset()
	await click(Vector2(420, 230))
	check("popping a layer unbinds its regions", hits, {})
	await click(A)
	check("the base layer is live again", hits, {"a": 1})

	var layer_owner := Node.new()
	add_child(layer_owner)
	router.push_layer(&"leaky", layer_owner)
	layer_owner.queue_free()
	await frames()
	await _reset()
	await click(A)
	check("a layer whose owner was freed cannot soft-lock input", hits, {"a": 1})

	await _reset()
	await mouse(A, true)
	var mid: int = router.push_layer(&"mid_press", self)
	await mouse(A, false)
	check("a layer opening mid-press cancels the older claim", hits, {})
	router.pop_layer(mid)

	# --- held actions -------------------------------------------------------
	var attack := _button("attack_pad", Rect2(20, 200, 100, 100))
	router.bind_held(attack, &"attack")
	await _reset()
	action_events.clear()
	await mouse(Vector2(70, 250), true)
	check("held: press sets action state", Input.is_action_pressed(&"attack"), true)
	check("held: press delivers one InputEventAction", action_events, ["down"] as Array[String])
	await mouse(Vector2(600, 400), false)
	check("held: release anywhere releases the action", Input.is_action_pressed(&"attack"), false)
	check("held: release delivers one InputEventAction", action_events, ["down", "up"] as Array[String])

	await _reset()
	action_events.clear()
	await touch(Vector2(70, 250), true)
	var held_layer: int = router.push_layer(&"over_held", self)
	await frames()
	check("held: opening a layer force-releases the action", Input.is_action_pressed(&"attack"), false)
	check("held: forced release is delivered once", action_events, ["down", "up"] as Array[String])
	await touch(Vector2(70, 250), false)
	check("held: the later finger-up adds nothing", action_events, ["down", "up"] as Array[String])
	router.pop_layer(held_layer)

	await _reset()
	await touch(Vector2(70, 250), true)
	attack.visible = false
	await frames()
	check("held: hiding the region releases the action", Input.is_action_pressed(&"attack"), false)
	await touch(Vector2(70, 250), false)
	attack.visible = true

	router.allow_multi_touch(attack, &"test_group")
	await _reset()
	action_events.clear()
	await touch(Vector2(50, 250), true, 0)
	await touch(Vector2(90, 250), true, 1)
	await touch(Vector2(50, 250), false, 0)
	check("multi-touch group: stays held while one finger remains", Input.is_action_pressed(&"attack"), true)
	await touch(Vector2(90, 250), false, 1)
	check("multi-touch group: one down, one up", action_events, ["down", "up"] as Array[String])

	router.set_gameplay_enabled(false)
	check("set_gameplay_enabled(false) suppresses gameplay", suppress_calls.back(), true)
	router.set_gameplay_enabled(true)
	check("set_gameplay_enabled(true) restores it", suppress_calls.back(), false)

	# --- paused tree, keyboard, hover, bind_rect ----------------------------
	get_tree().paused = true
	a.process_mode = Node.PROCESS_MODE_PAUSABLE
	c.process_mode = Node.PROCESS_MODE_ALWAYS
	await _reset()
	await click(A)
	await click(C)
	check("paused tree: only regions that can process are live", hits, {"c": 1})
	get_tree().paused = false

	await _reset()
	a.grab_focus()
	await key_accept()
	check("keyboard accept on a focused button activates once", hits, {"a": 1})

	await _reset()
	a.grab_focus()
	await move_mouse(C)
	check("hover focuses an IGNORE button", c.has_focus(), true)

	router.bind_rect(func() -> Rect2: return Rect2(500, 300, 60, 60), _hit_top)
	await _reset()
	await click(Vector2(530, 330))
	check("bind_rect region activates once", hits, {"top": 1})

	finish()
