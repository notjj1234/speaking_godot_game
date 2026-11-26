extends Node
## F07 regression: the JS facade answers with JSON text, and the scorer must
## read the score from it (a JavaScriptObject never matched `is Dictionary`,
## so every score read as -1). Run headless on a scratch copy:
##   Godot --headless --path <copy> res://tools/tests/test_web_scorer_payload.tscn

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
	var scorer := WebPronunciationScorer.new()
	add_child(scorer)
	var got := {}
	scorer._capture_state = "scoring"
	scorer._pending_on_done = func(r: Dictionary) -> void: got.merge(r)
	scorer._on_js_score(['{"ok":true,"score":88,"phones":"h ə l oʊ","ms":5}'])
	_check("score read from JSON payload", int(scorer.last_result.get("score", -1)) == 88,
			str(scorer.last_result))
	_check("phones read from JSON payload", scorer.last_result.get("phones", "") == "h ə l oʊ")
	_check("on_done receives the result", int(got.get("score", -1)) == 88)
	_check("capture state back to idle", scorer._capture_state == "idle")

	scorer._on_js_score(['{"ok":false,"score":-1,"phones":"","ms":-1,"error":"not-recording"}'])
	_check("failure payload reads ok=false", scorer.last_result.get("ok", true) == false)

	scorer._on_js_score(["not json"])
	_check("unreadable payload falls back to -1", int(scorer.last_result.get("score", 0)) == -1)

	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)
