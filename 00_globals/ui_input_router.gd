extends Node
## UiInputRouter — the only dispatcher for pointer input. See docs/ui-input-rules.md.
##
## Invariant: one physical press fires at most one interactive action, and it
## belongs to the topmost interactive element of the topmost UI layer.
##
## Why it exists: with emulate_touch_from_mouse on, a mouse click reaches the
## game twice (an emulated ScreenTouch, then the MouseButton). TouchScreenButton
## listens to the first and Button to the second, so any pair of them on one
## spot fires twice.
##
## The one exception is the D-pad (touch_controls.tscn Left/Right/Up/Down): its
## TouchScreenButtons keep their native `action`, and neighbouring arrows overlap
## on purpose so one thumb can press a diagonal.

## Emitted once per activation or held press. Used by tests and the overlap probe.
signal activated(item: Object)

const TWIN_WINDOW_MSEC := 80
const TWIN_SLOP := 3.0
const PROBE_PATH := "res://tools/ui_qa/ui_overlap_probe.gd"


class Region:
	var item: CanvasItem  # null for bind_rect regions
	var item_id: int = 0
	var rect_source: Callable
	var handler: Callable
	var held_action: StringName = &""
	var layer: int = 0
	var order: int = 0
	var entered_tree: bool = false


class Claim:
	var region: Region
	## A dead claim still swallows its release but can no longer act.
	var dead: bool = false


var _regions: Array[Region] = []
## Open layers, bottom to top: {id, name, owner}. Layer 0 is the base layer.
var _layers: Array[Dictionary] = []
var _next_layer_id: int = 1
var _next_order: int = 0
var _claims: Dictionary = {}  # pointer index -> Claim
var _multi_touch: Dictionary = {}  # item instance id -> group name
var _gameplay_enabled: bool = true
var _recent: Dictionary = {}  # pressed (bool) -> {is_touch, msec, pos, consumed}
var _hovered_id: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _probe_requested():
		var probe := load(PROBE_PATH) as GDScript
		if probe:
			add_child(probe.new())


# --- public API -------------------------------------------------------------

## Route pointer presses on `item` (a Control, or a TouchScreenButton used as a
## visual) to `handler`. Fires once, on release inside the item. Rebinding an
## item replaces its previous binding.
func bind(item: CanvasItem, handler: Callable, layer: int = 0) -> void:
	_add_region(item, handler, &"", layer)


## bind() plus the keyboard path: `pressed` covers ui_accept. The mouse can never
## reach `pressed` because bind() sets mouse_filter to IGNORE.
func bind_button(button: BaseButton, handler: Callable, layer: int = 0) -> void:
	if not button.pressed.is_connected(handler):
		button.pressed.connect(handler)
	bind(button, handler, layer)


## Same, for a region that has no node. `rect_source` returns viewport coords.
## Ranks below every node region on the same layer.
func bind_rect(rect_source: Callable, handler: Callable, layer: int = 0) -> void:
	var region := Region.new()
	region.rect_source = rect_source
	region.handler = handler
	region.layer = layer
	_store(region)


## Hold `action_name` while a pointer holds `item`. Delivered as InputEventAction
## through Input.parse_input_event, which both updates the action state and
## reaches is_action_pressed(event) consumers. Input.action_press() alone would
## not: pause, interact and attack are all read from events.
func bind_held(item: CanvasItem, action_name: StringName, layer: int = 0) -> void:
	_add_region(item, Callable(), action_name, layer)


func unbind(item: CanvasItem) -> void:
	var id := item.get_instance_id()
	for region in _regions.duplicate():
		if region.item_id == id:
			_drop_region(region)


## Open a modal layer. Only the newest open layer receives presses. Pass the
## overlay as `layer_owner` so a layer cannot outlive it (scene change, free).
func push_layer(layer_name: StringName, layer_owner: Node = null) -> int:
	var id := _next_layer_id
	_next_layer_id += 1
	_layers.append({
		"id": id,
		"name": layer_name,
		"owner": weakref(layer_owner) if layer_owner else null,
	})
	_sync_gameplay()
	return id


## Close a layer and forget everything bound to it. Safe to call with 0 or twice.
func pop_layer(id: int) -> void:
	for i in _layers.size():
		if _layers[i]["id"] == id:
			_layers.remove_at(i)
			for region in _regions.duplicate():
				if region.layer == id:
					_drop_region(region)
			_sync_gameplay()
			return


func active_layer() -> int:
	return 0 if _layers.is_empty() else int(_layers.back()["id"])


func active_layer_name() -> StringName:
	return &"base" if _layers.is_empty() else _layers.back()["name"]


func set_gameplay_enabled(enabled: bool) -> void:
	_gameplay_enabled = enabled
	_sync_gameplay()


func is_gameplay_suppressed() -> bool:
	return not _gameplay_enabled or not _layers.is_empty()


## Let several fingers hold this region at once. Declared for the D-pad only.
func allow_multi_touch(control: Control, group: StringName) -> void:
	_multi_touch[control.get_instance_id()] = group


## Snapshot for tools/ui_qa/ui_overlap_probe.gd.
func debug_regions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for region in _regions:
		if region.item != null and not is_instance_valid(region.item):
			continue
		out.append({
			"item": region.item,
			"layer": region.layer,
			"eligible": _eligible(region),
			"held_action": region.held_action,
			"rect_source": region.rect_source,
		})
	return out


# --- input ------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if event.button_mask == 0:
			_hover(event.position)
		return
	var is_touch := event is InputEventScreenTouch
	if not is_touch:
		if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
			return
	var pressed: bool = event.pressed
	var pos: Vector2 = event.position
	if _swallow_twin(is_touch, pressed, pos):
		return
	var index: int = event.index if is_touch else 0
	var consumed := false
	if pressed:
		consumed = _press(index, pos)
		_remember(is_touch, pressed, pos, consumed)
	else:
		var claim: Claim = _claims.get(index)
		consumed = claim != null
		# Record before acting: the handler may open UI or change scene.
		_remember(is_touch, pressed, pos, consumed)
		if consumed:
			get_viewport().set_input_as_handled()
			_release(index, pos, event.is_canceled())
		return
	if consumed:
		get_viewport().set_input_as_handled()


## A mouse event and its emulated touch are one press. The second of the pair
## is swallowed only if the first was, so world clicks keep both.
func _swallow_twin(is_touch: bool, pressed: bool, pos: Vector2) -> bool:
	if not _recent.has(pressed):
		return false
	var first: Dictionary = _recent[pressed]
	var delta: Vector2 = (first["pos"] - pos).abs()
	if first["is_touch"] == is_touch \
			or Time.get_ticks_msec() - first["msec"] > TWIN_WINDOW_MSEC \
			or delta.x > TWIN_SLOP or delta.y > TWIN_SLOP:
		return false
	_recent.erase(pressed)
	if first["consumed"]:
		get_viewport().set_input_as_handled()
	return true


func _remember(is_touch: bool, pressed: bool, pos: Vector2, consumed: bool) -> void:
	_recent[pressed] = {
		"is_touch": is_touch, "msec": Time.get_ticks_msec(), "pos": pos, "consumed": consumed,
	}


func _press(index: int, pos: Vector2) -> bool:
	_prune()
	if _claims.has(index):
		# The release never arrived (window lost focus, browser gesture).
		var stale: Claim = _claims[index]
		_claims.erase(index)
		_end_held(stale)
	var region := _hit(pos)
	if region == null:
		return false
	var claim := Claim.new()
	claim.region = region
	var shared := _holders(region) > 0
	if shared and not _multi_touch.has(region.item_id):
		claim.dead = true  # second finger on a single-touch region
	_claims[index] = claim
	if not claim.dead and not shared and region.held_action != &"":
		activated.emit(region.item)
		_send_action(region.held_action, true)
	return true


func _release(index: int, pos: Vector2, canceled: bool) -> void:
	var claim: Claim = _claims[index]
	_claims.erase(index)
	if claim.dead:
		return
	var region := claim.region
	if region.held_action != &"":
		if _holders(region) == 0:
			_send_action(region.held_action, false)
		return
	if canceled or not _eligible(region) or not _contains(region, pos):
		return
	if region.handler.is_valid():
		activated.emit(region.item)
		region.handler.call()


func _hover(pos: Vector2) -> void:
	var region := _hit(pos)
	var id := 0 if region == null else region.item_id
	if id == _hovered_id:
		return  # only on change, so a resting mouse cannot fight the keyboard
	_hovered_id = id
	if region == null or not (region.item is Control):
		return
	var control := region.item as Control
	if control.focus_mode != Control.FOCUS_ALL or control.has_focus():
		return
	if control.get_viewport().gui_get_focus_owner() is LineEdit:
		return  # never pull the caret out of a text box
	control.grab_focus()


# --- hit testing ------------------------------------------------------------

func _hit(pos: Vector2) -> Region:
	var best: Region = null
	for region in _regions:
		if _eligible(region) and _contains(region, pos):
			if best == null or _is_above(region, best):
				best = region
	return best


func _eligible(region: Region) -> bool:
	if region.layer != active_layer():
		return false
	if region.item_id == 0:
		return region.rect_source.is_valid()
	if not is_instance_valid(region.item):
		return false
	var item := region.item
	if not item.is_inside_tree() or not item.is_visible_in_tree() or not item.can_process():
		return false
	if item is BaseButton and (item as BaseButton).disabled:
		return false
	var node: Node = item
	while node:
		if node.is_queued_for_deletion():
			return false
		node = node.get_parent()
	return true


func _contains(region: Region, pos: Vector2) -> bool:
	if region.item_id == 0:
		return (region.rect_source.call() as Rect2).has_point(pos)
	var xform := region.item.get_global_transform_with_canvas()
	if is_zero_approx(xform.determinant()):
		return false  # a cluster scaled to zero has no hit area
	return local_rect(region.item).has_point(xform.affine_inverse() * pos)


## The item's hit rect in its own coordinates (matches TouchScreenButton's).
static func local_rect(item: CanvasItem) -> Rect2:
	if item is Control:
		return Rect2(Vector2.ZERO, (item as Control).size)
	if item is TouchScreenButton:
		var button := item as TouchScreenButton
		if button.shape is RectangleShape2D:
			var size: Vector2 = (button.shape as RectangleShape2D).size
			var centre := Vector2.ZERO
			if button.shape_centered and button.texture_normal:
				centre = button.texture_normal.get_size() * 0.5
			return Rect2(centre - size * 0.5, size)
		if button.texture_normal:
			return Rect2(Vector2.ZERO, button.texture_normal.get_size())
	return Rect2()


## Draw order: CanvasLayer.layer, then effective z_index, then tree order.
func _is_above(a: Region, b: Region) -> bool:
	if a.item_id == 0 or b.item_id == 0:
		if a.item_id == 0 and b.item_id == 0:
			return a.order > b.order
		return b.item_id == 0
	var layer_a := _canvas_layer_of(a.item)
	var layer_b := _canvas_layer_of(b.item)
	if layer_a != layer_b:
		return layer_a > layer_b
	var z_a := _effective_z(a.item)
	var z_b := _effective_z(b.item)
	if z_a != z_b:
		return z_a > z_b
	return a.item.is_greater_than(b.item)


func _canvas_layer_of(node: Node) -> int:
	while node:
		if node is CanvasLayer:
			return (node as CanvasLayer).layer
		node = node.get_parent()
	return 0


func _effective_z(item: CanvasItem) -> int:
	var z := 0
	var node: Node = item
	while node is CanvasItem:
		var canvas_item := node as CanvasItem
		z += canvas_item.z_index
		if not canvas_item.z_as_relative:
			break
		node = node.get_parent()
	return z


# --- bookkeeping ------------------------------------------------------------

func _add_region(item: CanvasItem, handler: Callable, held_action: StringName, layer: int) -> void:
	unbind(item)
	var region := Region.new()
	region.item = item
	region.item_id = item.get_instance_id()
	region.handler = handler
	region.held_action = held_action
	region.layer = layer
	if item is Control:
		(item as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_store(region)


func _store(region: Region) -> void:
	_next_order += 1
	region.order = _next_order
	_regions.append(region)


func _drop_region(region: Region) -> void:
	_regions.erase(region)
	for claim: Claim in _claims.values():
		if claim.region == region:
			_end_held(claim)


## Kill a claim, releasing its held action if it was the last finger on it.
func _end_held(claim: Claim) -> void:
	if claim.dead:
		return
	claim.dead = true
	if claim.region.held_action != &"" and _holders(claim.region) == 0:
		_send_action(claim.region.held_action, false)


func _release_all_held() -> void:
	for claim: Claim in _claims.values():
		if claim.region.held_action != &"":
			_end_held(claim)


func _holders(region: Region) -> int:
	var count := 0
	for claim: Claim in _claims.values():
		if claim.region == region and not claim.dead:
			count += 1
	return count


func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)


func _sync_gameplay() -> void:
	var suppressed := is_gameplay_suppressed()
	if suppressed:
		_release_all_held()
	# Hiding the clusters also releases the D-pad: TouchScreenButton lets go
	# when it stops being visible.
	if is_inside_tree():
		get_tree().call_group("touch_controls", "set_gameplay_suppressed", suppressed)
		get_tree().call_group("pause_button", "set_gameplay_suppressed", suppressed)


func _prune() -> void:
	for layer in _layers.duplicate():
		var ref: WeakRef = layer["owner"]
		if ref == null:
			continue
		var node: Node = ref.get_ref()
		if node == null or node.is_queued_for_deletion() or not node.is_inside_tree():
			pop_layer(layer["id"])
	for region in _regions.duplicate():
		if region.item_id == 0:
			if not region.rect_source.is_valid():
				_drop_region(region)
		elif not is_instance_valid(region.item) or region.item.is_queued_for_deletion():
			_drop_region(region)
		elif region.item.is_inside_tree():
			region.entered_tree = true
		elif region.entered_tree:
			_drop_region(region)


func _process(_delta: float) -> void:
	_prune()
	for claim: Claim in _claims.values():
		if not claim.dead and claim.region.held_action != &"" and not _eligible(claim.region):
			_end_held(claim)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all_held()


## Off unless asked for: `-- --ui-probe` on desktop, `?ui_probe` in the web URL,
## or the loqui/debug/ui_probe project setting.
func _probe_requested() -> bool:
	if OS.get_cmdline_user_args().has("--ui-probe"):
		return true
	if bool(ProjectSettings.get_setting("loqui/debug/ui_probe", false)):
		return true
	if OS.has_feature("web"):
		return bool(JavaScriptBridge.eval("window.location.search.indexOf('ui_probe') !== -1", true))
	return false
