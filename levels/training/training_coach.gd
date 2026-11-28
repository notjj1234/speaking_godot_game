class_name TrainingCoach
extends Node
## Runs Guided Training lessons strictly in order. A lesson is
##   { "id": StringName, "text": String, "touch_text": String (optional),
##     "tap": bool (optional), "begin": Callable (optional, may return a Signal),
##     "goal": String (optional: the short line on the shrunk pill),
##     "point": Callable (optional: what the GuidePointer points at, re-read
##              every frame; returns a Node2D / Vector2 / Control or null) }
## and ends on the first of: complete(), the Signal its begin returned, or the
## banner's continue_pressed when "tap" is set. Completions that belong to an
## earlier lesson are ignored.

signal lesson_started(index: int, id: StringName)
signal finished

var lessons: Array[Dictionary] = []

var _banner: CoachBanner
## Optional: arrows / rings toward each lesson's "point" target.
var pointer: GuidePointer
var _index := -1
var _token := 0
var _links: Array[Array] = []  # [Signal, Callable] pairs for the current lesson


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start(banner: CoachBanner) -> void:
	_banner = banner
	_run(0)


func complete() -> void:
	_done(_token)


func current_index() -> int:
	return _index


func current_id() -> StringName:
	if _index < 0 or _index >= lessons.size():
		return &""
	return lessons[_index].get("id", &"")


func _run(index: int) -> void:
	_drop_links()
	_token += 1
	_index = index
	if index >= lessons.size():
		if _banner:
			_banner.clear()
		if pointer:
			pointer.clear()
		print("✅ Training coach: all lessons done")
		finished.emit()
		return
	var lesson: Dictionary = lessons[index]
	var tap := bool(lesson.get("tap", false))
	if _banner:
		_banner.say(_text_for(lesson), tap, str(lesson.get("goal", "")))
		if tap:
			_link(_banner.continue_pressed)
	if pointer:
		pointer.follow(lesson.get("point", Callable()))
	print("✅ Training lesson %d: %s" % [index + 1, lesson.get("id", &"")])
	lesson_started.emit(index, lesson.get("id", &""))
	var begin: Callable = lesson.get("begin", Callable())
	if begin.is_valid():
		var token := _token
		var result = begin.call()
		if result is Signal and token == _token:
			_link(result)


## What the current lesson points at right now (null when nothing).
func current_point_target():
	if _index < 0 or _index >= lessons.size():
		return null
	var fn: Callable = lessons[_index].get("point", Callable())
	return fn.call() if fn.is_valid() else null


func _text_for(lesson: Dictionary) -> String:
	var touch := str(lesson.get("touch_text", ""))
	if touch != "" and MobileSafeLayout.wants_touch_ui():
		return touch
	return str(lesson.get("text", ""))


func _link(sig: Signal) -> void:
	var argc := _signal_argc(sig)
	var callable := _done.bind(_token)
	if argc > 0:
		callable = callable.unbind(argc)
	sig.connect(callable, CONNECT_ONE_SHOT)
	_links.append([sig, callable])


func _drop_links() -> void:
	for pair in _links:
		var sig: Signal = pair[0]
		var callable: Callable = pair[1]
		if not sig.is_null() and sig.is_connected(callable):
			sig.disconnect(callable)
	_links.clear()


func _signal_argc(sig: Signal) -> int:
	var owner := sig.get_object()
	if owner == null:
		return 0
	for info in owner.get_signal_list():
		if StringName(info.name) == sig.get_name():
			return (info.args as Array).size()
	return 0


func _done(token: int) -> void:
	if token != _token or _index < 0 or _index >= lessons.size():
		return
	_token += 1  # one completion per lesson
	call_deferred("_run", _index + 1)
