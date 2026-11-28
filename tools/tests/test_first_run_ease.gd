extends Node2D
## First run only: stages 1-5 ramp 0.6 → 1.0; never eased after the first run.

var passes := 0
var failures := 0


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _ready() -> void:
	var e := func(stage: int, runs: int) -> float: return HordeCurve.first_run_ease(stage, runs)
	_check("first run s1 == 0.6", is_equal_approx(e.call(1, 1), 0.6), str(e.call(1, 1)))
	_check("first run s3 == 0.8", is_equal_approx(e.call(3, 1), 0.8), str(e.call(3, 1)))
	_check("first run s5 == 1.0", is_equal_approx(e.call(5, 1), 1.0), str(e.call(5, 1)))
	_check("first run s6 == 1.0", is_equal_approx(e.call(6, 1), 1.0))
	_check("second run s1 == 1.0", is_equal_approx(e.call(1, 2), 1.0))
	_check("runs 0 s1 == 0.6", is_equal_approx(e.call(1, 0), 0.6))
	_check("stage 0 == 1.0", is_equal_approx(e.call(0, 1), 1.0))
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
