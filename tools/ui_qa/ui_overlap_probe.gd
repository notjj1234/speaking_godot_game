extends Node
## Debug probe: prints every visible interactive node with its on-screen rect and
## every overlapping pair among the live ones. It covers what input_audit.py
## cannot: containers, anchors and runtime layout.
##
## Loaded by UiInputRouter only when asked: `?ui_probe` on the web URL,
## `-- --ui-probe` on desktop, or the loqui/debug/ui_probe project setting.
## Press F9 to dump the current screen. It also dumps by itself shortly after
## the scene or the top UI layer changes, for phones with no F9.

## Empty: the LeftCluster joystick is not a TouchScreenButton and has no
## allowlisted TSB overlaps. Keep in sync with docs/ui-input-rules.md and
## tools/ui_qa/input_audit.py (DPAD).
const DPAD: Array[String] = []
const SETTLE_SECONDS := 0.6
const MIN_TARGET := 44.0

var _last_key := ""
var _pending := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[ui-probe] on. F9 dumps; it also dumps when the screen or UI layer changes.")


func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	var key := "%s|%d" % [scene.name if scene else &"-", UiInputRouter.active_layer()]
	if key != _last_key:
		_last_key = key
		_pending = SETTLE_SECONDS
	elif _pending > 0.0:
		_pending -= delta
		if _pending <= 0.0:
			dump()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		dump()


func dump() -> int:
	var bound := {}
	for region in UiInputRouter.debug_regions():
		if region["item"] != null:
			bound[region["item"]] = region

	var rows: Array[Dictionary] = []
	for node in get_tree().root.find_children("*", "", true, false):
		var row := _describe(node, bound)
		if not row.is_empty():
			rows.append(row)

	var scene := get_tree().current_scene
	print("\n[ui-probe] ===== screen=%s top_layer=%s viewport=%s" % [
		scene.name if scene else &"-", UiInputRouter.active_layer_name(),
		get_viewport().get_visible_rect().size])
	for row in rows:
		var rect: Rect2 = row["rect"]
		var small: bool = row["live"] and (rect.size.x < MIN_TARGET - 0.5 or rect.size.y < MIN_TARGET - 0.5)
		print("[ui-probe] %-5s %-13s %s  rect=(%d,%d %dx%d)%s" % [
			"LIVE" if row["live"] else "inert", row["kind"], row["path"],
			rect.position.x, rect.position.y, rect.size.x, rect.size.y,
			"  SMALL" if small else ""])

	var bad := 0
	for i in rows.size():
		for j in range(i + 1, rows.size()):
			if not (rows[i]["live"] and rows[j]["live"]):
				continue
			var hit: Rect2 = (rows[i]["rect"] as Rect2).intersection(rows[j]["rect"])
			if hit.size.x < 0.5 or hit.size.y < 0.5:
				continue
			var verdict := "** CHECK **"
			if _is_dpad(rows[i]) and _is_dpad(rows[j]):
				verdict = "(allowed D-pad)"
			elif _is_backdrop_pair(rows[i]["node"], rows[j]["node"]):
				verdict = "(backdrop)"
			else:
				bad += 1
			print("[ui-probe] OVERLAP %s %dx%d  %s  <>  %s" % [
				verdict,
				hit.size.x, hit.size.y, rows[i]["path"], rows[j]["path"]])
	print("[ui-probe] ===== %d nodes, %d unexpected overlap(s)\n" % [rows.size(), bad])
	return bad


func _describe(node: Node, bound: Dictionary) -> Dictionary:
	if not (node is BaseButton or node is TouchScreenButton or node is Slider
			or node is LineEdit or bound.has(node)):
		return {}
	var item := node as CanvasItem
	if item == null or not item.is_visible_in_tree():
		return {}
	var kind := "visual-only"
	var live := false
	if bound.has(node):
		var region: Dictionary = bound[node]
		live = region["eligible"]
		kind = "router L%d" % region["layer"]
		if region["held_action"] != &"":
			kind = "held:%s" % region["held_action"]
	elif node is TouchScreenButton:
		if (node as TouchScreenButton).action != "":
			kind = "tsb:%s" % (node as TouchScreenButton).action
			live = node.can_process()
	elif (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		# Plain GUI. Under a modal layer a dimmer covers it, so it is not live.
		kind = "gui"
		live = node.can_process() and not (node is BaseButton and (node as BaseButton).disabled) \
				and not _covered_by_modal(item)
	var local: Rect2 = UiInputRouter.local_rect(item)
	var xform := item.get_global_transform_with_canvas()
	return {"path": str(node.get_path()), "kind": kind, "live": live, "rect": xform * local,
			"node": node}


## True when a visible full-screen STOP dimmer is drawn above `item`.
func _covered_by_modal(item: CanvasItem) -> bool:
	var view := get_viewport().get_visible_rect()
	for node in get_tree().root.find_children("*", "ColorRect", true, false):
		var dim := node as ColorRect
		if dim.mouse_filter == Control.MOUSE_FILTER_STOP and dim.is_visible_in_tree() \
				and dim.get_global_rect().encloses(view) \
				and not dim.is_ancestor_of(item) and _drawn_above(dim, item):
			return true
	return false


func _drawn_above(a: Node, b: Node) -> bool:
	var layer_a: int = UiInputRouter._canvas_layer_of(a)
	var layer_b: int = UiInputRouter._canvas_layer_of(b)
	return layer_a > layer_b if layer_a != layer_b else a.is_greater_than(b)


## A bound plain Control (dimmer, panel, banner) under something drawn above it
## is by design: the router picks the upper one. The reverse is a real bug.
func _is_backdrop_pair(a: Node, b: Node) -> bool:
	var lower := b if _drawn_above(a, b) else a
	return lower is Control and not (lower is BaseButton or lower is Range or lower is LineEdit)


func _is_dpad(row: Dictionary) -> bool:
	var node: Node = row["node"]
	return node is TouchScreenButton and String(node.name) in DPAD \
			and String(node.get_parent().name) == "LeftCluster"
