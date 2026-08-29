class_name WebSTTProvider
extends SttProvider

# JavaScriptBridge callbacks must be stored or they are garbage-collected.
var _recognition = null
var _on_result_cb = null
var _on_error_cb = null
var _on_end_cb = null
var _intentional_stop: bool = false
var _got_result: bool = false
var _skip_end_result: bool = false
var _setup_attempted: bool = false
var _session_active: bool = false
var _pending_restart: bool = false
var _lang: String = "en-US"


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_setup_recognition()


func is_available() -> bool:
	if not OS.has_feature("web"):
		return false
	if _setup_attempted:
		return _recognition != null
	return bool(JavaScriptBridge.eval("!!(window.SpeechRecognition || window.webkitSpeechRecognition)", true))


func prime_permission() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		"""
		(function() {
			if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
				navigator.mediaDevices.getUserMedia({ audio: true }).then(function(stream) {
					try {
						stream.getTracks().forEach(function(track) { track.stop(); });
					} catch (e) {}
				}).catch(function() {});
			}
		})()
		"""
	)


func listen() -> void:
	if not OS.has_feature("web"):
		error.emit(-1)
		return
	if _recognition == null:
		_setup_recognition()
	if _recognition == null:
		error.emit(-1)
		return
	_session_active = true
	_intentional_stop = false
	_got_result = false
	_skip_end_result = false
	_pending_restart = false
	_apply_language()
	var status := _eval_start()
	if status == "already":
		_pending_restart = true
		_eval_stop()
		return
	if status != "ok":
		_skip_end_result = true
		error.emit(-1)


func stop() -> void:
	_session_active = false
	_pending_restart = false
	if _recognition == null:
		return
	_intentional_stop = true
	_eval_stop()


func set_language(lang: String) -> void:
	if lang == "en" or lang.strip_edges().is_empty():
		_lang = "en-US"
	elif lang.length() == 2:
		_lang = lang.to_lower() + "-" + lang.to_upper()
	else:
		_lang = lang
	_apply_language()


func _apply_language() -> void:
	if _recognition == null:
		return
	_recognition.lang = _lang


func _setup_recognition() -> void:
	if not OS.has_feature("web"):
		return
	_setup_attempted = true
	if not bool(JavaScriptBridge.eval("!!(window.SpeechRecognition || window.webkitSpeechRecognition)", true)):
		return

	_on_result_cb = JavaScriptBridge.create_callback(_on_js_result)
	_on_error_cb = JavaScriptBridge.create_callback(_on_js_error)
	_on_end_cb = JavaScriptBridge.create_callback(_on_js_end)

	if bool(JavaScriptBridge.eval("typeof webkitSpeechRecognition !== 'undefined'", true)):
		_recognition = JavaScriptBridge.create_object("webkitSpeechRecognition")
	else:
		_recognition = JavaScriptBridge.create_object("SpeechRecognition")

	if _recognition == null:
		return

	# Keep a window handle so start/stop can be wrapped in try/catch via eval.
	var window = JavaScriptBridge.get_interface("window")
	window._godot_speech_recognition = _recognition

	_recognition.interimResults = false
	_recognition.continuous = false
	_recognition.maxAlternatives = 1
	_recognition.lang = _lang
	_recognition.onresult = _on_result_cb
	_recognition.onerror = _on_error_cb
	_recognition.onend = _on_end_cb


func _eval_start() -> String:
	return str(JavaScriptBridge.eval(
		"""
		(function() {
			try {
				if (!window._godot_speech_recognition) {
					return "missing";
				}
				window._godot_speech_recognition.start();
				return "ok";
			} catch (e) {
				var name = (e && e.name) ? String(e.name) : "";
				var msg = String(e);
				if (name === "InvalidStateError" || msg.indexOf("already") !== -1) {
					return "already";
				}
				return "fail";
			}
		})()
		""",
		true
	))


func _eval_stop() -> void:
	JavaScriptBridge.eval(
		"""
		(function() {
			try {
				if (window._godot_speech_recognition) {
					window._godot_speech_recognition.stop();
				}
			} catch (e) {}
		})()
		"""
	)


func _restart_if_session() -> void:
	if not _session_active or _intentional_stop:
		return
	_got_result = false
	_skip_end_result = false
	var status := _eval_start()
	if status == "already":
		_pending_restart = true
		_eval_stop()
	elif status != "ok":
		_skip_end_result = true
		error.emit(-1)


func _on_js_result(args: Array) -> void:
	if args.is_empty():
		return
	var event = args[0]
	if event == null:
		return
	var results = event.results
	if results == null or results.length == 0:
		return
	var last = results[results.length - 1]
	if last == null or last.length == 0:
		return
	var text := str(last[0].transcript)
	_got_result = true
	listening_completed.emit(text)


func _on_js_error(args: Array) -> void:
	var err_name := ""
	if not args.is_empty() and args[0] != null:
		err_name = str(args[0].error)
	print("[WebSTTProvider] recognition error: ", err_name)
	match err_name:
		"not-allowed", "service-not-allowed":
			_session_active = false
			_pending_restart = false
			_skip_end_result = true
			error.emit(-1)
		"aborted":
			_skip_end_result = true
		"no-speech":
			pass
		"network":
			_skip_end_result = true
			error.emit(1)
		_:
			_skip_end_result = true
			error.emit(1)


func _on_js_end(_args: Array) -> void:
	if _intentional_stop:
		return
	if _pending_restart:
		_pending_restart = false
		_restart_if_session()
		return
	if _session_active and not _got_result:
		# Keep the challenge mic open; do not fail on silence.
		_restart_if_session()
		return
