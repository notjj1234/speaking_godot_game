extends Node2D
## TrainingCoach runs lessons strictly in order: a lesson ends only on its own
## condition, stale completions are ignored, and the banner shows while paused.

signal custom_done

var passes := 0
var failures := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var banner := CoachBanner.new()
	add_child(banner)
	var coach := TrainingCoach.new()
	add_child(coach)
	var finished := [false]
	coach.finished.connect(func(): finished[0] = true)
	var begun := []
	coach.lessons = [
		{"id": &"tap", "text": "Tap lesson", "tap": true},
		{"id": &"sig", "text": "Signal lesson", "begin": func():
			begun.append(&"sig")
			return custom_done},
		{"id": &"manual", "text": "Manual lesson", "touch_text": "Manual (touch)", "goal": "Do the thing"},
	]
	coach.start(banner)
	await _frames(2)
	_check("starts at lesson 0", coach.current_index() == 0 and coach.current_id() == &"tap")
	_check("banner shows lesson text", banner.visible and banner.current_text().begins_with("Tap lesson"),
		banner.current_text())
	await _frames(2)
	_check("tap lesson waits for continue", coach.current_index() == 0)
	banner.continue_pressed.emit()
	await _frames(2)
	_check("continue advances to lesson 1", coach.current_index() == 1 and begun == [&"sig"])
	banner.continue_pressed.emit()
	await _frames(2)
	_check("stale continue ignored", coach.current_index() == 1)
	custom_done.emit()
	await _frames(2)
	_check("signal lesson completes on its signal", coach.current_index() == 2)
	custom_done.emit()
	await _frames(2)
	_check("old lesson's signal ignored later", coach.current_index() == 2)
	_check("lesson goal reaches the banner", banner.current_goal() == "Do the thing", banner.current_goal())
	coach.complete()
	await _frames(2)
	_check("complete() finishes last lesson → finished", finished[0])

	get_tree().paused = true
	banner.say("x")
	await _frames(1)
	_check("banner shows while paused", banner.visible and banner.current_text() == "x")
	get_tree().paused = false
	_check("banner sits above HUD, below pause menu", banner.layer > 2 and banner.layer < 10, str(banner.layer))

	banner.flash("tip", 0.2)
	await get_tree().create_timer(0.45, true, false, true).timeout
	_check("flash hides itself", not banner.visible)
	var pressed := [0]
	banner.continue_pressed.connect(func(): pressed[0] += 1)
	var enter := InputEventAction.new()
	enter.action = &"ui_accept"
	enter.pressed = true
	banner.say("menu", true)
	var layer := UiInputRouter.push_layer(&"test_menu", self)
	banner._input(enter)
	_check("Enter ignored while a menu layer is open", pressed[0] == 0)
	UiInputRouter.pop_layer(layer)
	get_tree().paused = true
	banner._input(enter)
	_check("Enter ignored while paused", pressed[0] == 0)
	get_tree().paused = false
	banner._input(enter)
	_check("Enter continues during gameplay", pressed[0] == 1)

	banner.say("y", true)
	banner.clear()
	_check("clear hides", not banner.visible)

	await _test_pill(banner)

	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)


## The bubble gets out of the way: it shrinks to a small top-left pill with
## the goal, and a tap (or H) opens it again.
func _test_pill(banner: CoachBanner) -> void:
	banner.collapse_sec = 0.3
	banner.say("Walk to the glowing patch.", false, "Reach the patch")
	await _frames(1)
	_check("new lesson starts expanded", not banner.is_collapsed() and banner.visible)
	await get_tree().create_timer(0.6, true, false, true).timeout
	_check("collapses to the pill by itself", banner.is_collapsed() and banner.visible)
	_check("pill shows the goal", banner.pill_text().contains("Reach the patch"), banner.pill_text())
	var pill := banner.pill_rect()
	_check("pill sits top-left", pill.position.x <= 16.0 and pill.position.y <= 12.0 and pill.size.x <= 300.0, str(pill))
	_check("pill is big enough to read", pill.size.y >= 46.0, str(pill.size))
	_check("pill goal font is readable", banner.pill_font_size() >= 16, str(banner.pill_font_size()))
	var vis := get_viewport().get_visible_rect()
	for r in MobileSafeLayout._hud_rects(vis):
		_check("pill clear of HUD rect %s" % r, not pill.intersects(r), "pill %s" % pill)
	var pops: int = banner.pill_pops
	banner.say("Hit it.", false, "Hit the slime")
	banner.collapse()
	_check("a new goal pops the pill", banner.pill_pops == pops + 1, str(banner.pill_pops))
	banner.expand()
	banner.collapse()
	_check("same goal doesn't pop again", banner.pill_pops == pops + 1, str(banner.pill_pops))
	banner.say("Walk to the glowing patch.", false, "Reach the patch")
	banner.collapse()
	await _frames(1)
	var bubble_w: float = banner.bubble_width_for(Vector2(1280, 480))
	_check("expanded bubble is wide on desktop", bubble_w >= 480.0, str(bubble_w))
	_check("expanded bubble fits a phone", banner.bubble_width_for(Vector2(360, 640)) <= 336.0)
	var top: float = banner.pill_top_for(true, Rect2(8, 8, 108, 44))
	_check("portrait phones: pill below the pause button", top >= 58.0, str(top))

	banner._on_pill_tap()
	await _frames(1)
	_check("tapping the pill opens the bubble", not banner.is_collapsed())
	await get_tree().create_timer(0.6, true, false, true).timeout
	_check("re-opened bubble shrinks again", banner.is_collapsed())

	banner.collapse_sec = 30.0
	banner.say("Hit the slime.", false, "Hit the slime")
	Input.action_press("left")
	await _frames(3)
	Input.action_release("left")
	_check("moving shrinks the bubble at once", banner.is_collapsed())

	var toggle := InputEventAction.new()
	toggle.action = &"coach_toggle"
	toggle.pressed = true
	banner._input(toggle)
	_check("H opens the bubble", not banner.is_collapsed())
	banner._input(toggle)
	_check("H shrinks it again", banner.is_collapsed())

	banner.collapse_sec = 0.3
	banner.say("Read this.", true, "Read on")
	await get_tree().create_timer(0.6, true, false, true).timeout
	_check("tap-to-continue lessons stay open", not banner.is_collapsed())

	banner.say("Go.", false, "Go")
	banner.collapse()
	banner.set_suppressed(true)
	await _frames(1)
	_check("suppressed: nothing on screen", not banner.visible)
	banner.set_suppressed(false)
	await _frames(1)
	_check("unsuppressed: pill back", banner.visible and banner.is_collapsed())
	banner.clear()
