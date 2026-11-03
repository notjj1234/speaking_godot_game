# web_tts_provider.gd
#
# Web TTS backend. Bridges to window.LQSpeak in export/web_shell.html, a thin
# wrapper over the browser speechSynthesis API. Mirrors the JavaScriptBridge
# usage of speech_scoring/web_pronunciation_scorer.gd.

class_name WebTTSProvider
extends TTSSpeechProvider

const _AVAILABLE_JS := "(function(){ return !!(window.LQSpeak && window.speechSynthesis && window.SpeechSynthesisUtterance); })()"
const _SPEAKING_JS := "(function(){ return !!(window.LQSpeak && window.LQSpeak.isSpeaking()); })()"
const _CANCEL_JS := "(function(){ if (window.LQSpeak) { window.LQSpeak.cancel(); } })()"

# JavaScriptBridge callbacks must be stored or they are garbage-collected.
var _end_cb = null
var _window = null
var _speaking := false
var _next_id := 0
var _active_id := 0


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_window = JavaScriptBridge.get_interface("window")
	if _window == null:
		print("❌ WebTTSProvider: window interface unavailable.")
		return
	_end_cb = JavaScriptBridge.create_callback(_on_js_end)
	_window.set("LQSpeakEndCb", _end_cb)


func is_available() -> bool:
	if not OS.has_feature("web"):
		return false
	# Re-evaluated on every call: never cache a false from a slow module load.
	return bool(JavaScriptBridge.eval(_AVAILABLE_JS, true))


func speak(text: String) -> bool:
	if not OS.has_feature("web"):
		return false
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		return false
	if _end_cb == null:
		print("❌ WebTTSProvider: LQSpeak callback missing.")
		return false
	if not is_available():
		print("❌ WebTTSProvider: LQSpeak facade missing.")
		return false

	_next_id += 1
	_active_id = _next_id
	var js := "(function(){ return window.LQSpeak.speak(%s, %d, function(uid){ window.LQSpeakEndCb(uid); }); })()" % [JSON.stringify(cleaned), _active_id]
	var ok := bool(JavaScriptBridge.eval(js, true))
	if not ok:
		print("❌ WebTTSProvider: speak() failed.")
		return false

	_speaking = true
	speech_started.emit()
	return true


func stop() -> void:
	if not OS.has_feature("web"):
		return
	# Invalidate the current utterance so a late callback cannot finish the next one.
	_active_id = 0
	JavaScriptBridge.eval(_CANCEL_JS, true)
	if _speaking:
		_speaking = false
		speech_finished.emit()


func is_speaking() -> bool:
	if not OS.has_feature("web") or not _speaking:
		return false
	return bool(JavaScriptBridge.eval(_SPEAKING_JS, true))


func _on_js_end(args: Array) -> void:
	var id := -1
	if not args.is_empty() and args[0] != null:
		id = int(args[0])
	if id != _active_id:
		return
	if not _speaking:
		return
	_speaking = false
	speech_finished.emit()
