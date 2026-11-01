# web_pronunciation_scorer.gd
#
# Web pronunciation scorer: captures mic audio in the browser (via the window
# facade `window.LQPron`) and scores captured audio against a target phoneme
# string using the in-browser wav2vec2 phoneme model (transformers.js, vendored).
#
# Bridge: GDScript registers a JS callback on window (`LQPronScoreCb`) that the
# window facade calls when the worker finishes scoring; the scorer awaits the
# capture_finished signal, which is emitted from the JS callback with the
# worker's scoring result.

class_name WebPronunciationScorer
extends PronunciationScorer

const _FACADE_READY_JS := "(function(){ return !!(window.LQPron && window.LQPron.isReady); })()"

var _capture_state: String = "idle"
var _js_window = null
var _score_cb = null
var _pending_on_done: Callable = Callable()


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	var window = JavaScriptBridge.get_interface("window")
	_js_window = window
	if window == null:
		_capture_state = "failed"
		return
	_score_cb = JavaScriptBridge.create_callback(_on_js_score)
	window.set("LQPronScoreCb", _score_cb)


func is_available() -> bool:
	if not OS.has_feature("web"):
		return false
	return bool(JavaScriptBridge.eval(_FACADE_READY_JS, true))


func begin_capture() -> void:
	if not bool(JavaScriptBridge.eval(_FACADE_READY_JS, true)):
		_capture_state = "failed"
		return
	_capture_state = "recording"
	JavaScriptBridge.eval("(function(){ return window.LQPron.beginCapture(); })()")
	capture_started.emit()


func abandon_capture() -> void:
	if _capture_state == "recording":
		JavaScriptBridge.eval("(function(){ return window.LQPron.abandonCapture(); })()")
	_capture_state = "idle"


func end_capture_and_score(target_phonemes: String, on_done: Callable) -> void:
	if _capture_state != "recording":
		last_result = {"score": -1, "phones": "", "ms": -1, "ok": false}
		capture_finished.emit(-1, "", -1, false)
		on_done.call(last_result)
		return
	_capture_state = "scoring"
	_pending_on_done = on_done
	var js_expr := "(function(){ var t = " + JSON.stringify(target_phonemes) + "; return window.LQPron.endCaptureAndScore(t, function(r){ window.LQPronScoreCb(r); }); })()"
	JavaScriptBridge.eval(js_expr, true)


func _on_js_score(_args: Array) -> void:
	var payload: Dictionary = {}
	if _args.size() > 0 and _args[0] is Dictionary:
		payload = _args[0] as Dictionary
	var ok: bool = true
	var score := -1
	var phones := ""
	var ms := -1
	if payload.has("ok"):
		ok = bool(payload.get("ok"))
	if payload.has("score"):
		score = int(payload.get("score"))
	if payload.has("phones"):
		phones = String(payload.get("phones"))
	if payload.has("ms"):
		ms = int(payload.get("ms"))
	var result: Dictionary = {"score": score, "phones": phones, "ms": ms, "ok": ok}
	last_result = result
	_capture_state = "idle"
	if _pending_on_done.is_valid():
		_pending_on_done.call(result)
	_pending_on_done = Callable()
	capture_finished.emit(score, phones, ms, ok)
