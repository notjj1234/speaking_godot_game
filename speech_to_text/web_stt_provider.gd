class_name WebSTTProvider
extends SttProvider

# JavaScriptBridge callbacks must be stored or they are garbage-collected.
var _recognition = null
var _on_result_cb = null
var _on_error_cb = null
var _on_end_cb = null
var _on_visibility_cb = null
var _on_pagehide_cb = null
var _on_pageshow_cb = null
var _intentional_stop: bool = false
var _session_active: bool = false
## Page hidden or closing: the mic is released, and a session that is still
## wanted restarts when the page is visible again.
var _suspended: bool = false
var _setup_attempted: bool = false
var _lang: String = "en-US"
var _last_final_transcript: String = ""


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
	if not _web_runtime():
		error.emit(-1)
		return
	if _recognition == null:
		_setup_recognition()
	if _recognition == null:
		error.emit(-1)
		return
	_session_active = true
	_intentional_stop = false
	_last_final_transcript = ""
	_apply_language()
	if _suspended:
		# The page is hidden: resume() starts it once the page is visible again.
		listening_started.emit()
		return
	var status := _eval_start()
	# "already": recognition is still running (continuous mode keeps it alive
	# after a final result) or still stopping, in which case _on_js_end restarts
	# it now that the session is active again. Either way it is live — reporting
	# -1 here would read as a mic refusal to every caller.
	if status == "ok" or status == "already":
		listening_started.emit()
	else:
		error.emit(-1)


## Overridden by tests/test_stt_suspend.gd to drive the session logic off-browser.
func _web_runtime() -> bool:
	return OS.has_feature("web")


func stop() -> void:
	_session_active = false
	if _recognition == null:
		return
	_intentional_stop = true
	_eval_stop()
	listening_stopped.emit()


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

	_recognition.interimResults = true
	_recognition.continuous = true
	_recognition.maxAlternatives = 1
	_recognition.lang = _lang
	_recognition.onresult = _on_result_cb
	_recognition.onerror = _on_error_cb
	_recognition.onend = _on_end_cb
	_watch_page_lifecycle()


## Safari keeps the mic (and the orange indicator) for a hidden or closing page
## whose recognition is still running, so release it on those events instead of
## relying on the game loop, which the browser pauses while the page is hidden.
func _watch_page_lifecycle() -> void:
	_on_visibility_cb = JavaScriptBridge.create_callback(_on_js_visibility)
	_on_pagehide_cb = JavaScriptBridge.create_callback(_on_js_pagehide)
	_on_pageshow_cb = JavaScriptBridge.create_callback(_on_js_pageshow)
	var document = JavaScriptBridge.get_interface("document")
	var window = JavaScriptBridge.get_interface("window")
	if document == null or window == null:
		print("⚠️ [WebSTTProvider] No document/window: mic is not released when the page hides.")
		return
	document.addEventListener("visibilitychange", _on_visibility_cb)
	window.addEventListener("pagehide", _on_pagehide_cb)
	window.addEventListener("pageshow", _on_pageshow_cb)


func _on_js_visibility(_args: Array) -> void:
	if str(JavaScriptBridge.eval("document.visibilityState", true)) == "hidden":
		suspend()
	else:
		resume()


func _on_js_pagehide(_args: Array) -> void:
	suspend()


func _on_js_pageshow(_args: Array) -> void:
	# A page restored from the back/forward cache fires pageshow, not visibilitychange.
	if str(JavaScriptBridge.eval("document.visibilityState", true)) != "hidden":
		resume()


func suspend() -> void:
	if _suspended:
		return
	_suspended = true
	if _recognition == null:
		return
	_intentional_stop = true
	_eval_stop()
	print("🎤 [WebSTTProvider] Page hidden: microphone released.")


func resume() -> void:
	if not _suspended:
		return
	_suspended = false
	if _recognition == null or not _session_active:
		return
	_intentional_stop = false
	print("🎤 [WebSTTProvider] Page visible again: resuming listening.")
	_eval_start()


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


## abort(), not stop(): iOS Safari can keep capturing after stop() even once onend
## has fired, and stop()'s trailing result is discarded anyway (_on_js_result
## ignores results once the session is inactive).
func _eval_stop() -> void:
	JavaScriptBridge.eval(
		"""
		(function() {
			var r = window._godot_speech_recognition;
			if (!r) {
				return;
			}
			try {
				if (typeof r.abort === "function") {
					r.abort();
				} else {
					r.stop();
				}
			} catch (e) {
				console.warn("[WebSTTProvider] releasing recognition failed:", e);
			}
		})()
		"""
	)


func _on_js_result(args: Array) -> void:
	# A finalized result can still arrive after stop(); never score a ghost attempt.
	if not _session_active:
		return
	if args.is_empty():
		return
	var event = args[0]
	if event == null:
		return
	var results = event.results
	if results == null or results.length == 0:
		return
	
	# With continuous=true, we get all results since last start
	# The last result is the most recent (interim or final)
	var last_idx = results.length - 1
	var last = results[last_idx]
	if last == null or last.length == 0:
		return
	var text := str(last[0].transcript)
	
	if bool(last.isFinal):
		_last_final_transcript = text
		listening_completed.emit(text)
	else:
		partial_transcript.emit(text)


func _on_js_error(args: Array) -> void:
	var err_name := ""
	if not args.is_empty() and args[0] != null:
		err_name = str(args[0].error)
	print("[WebSTTProvider] recognition error: ", err_name)
	match err_name:
		"not-allowed", "service-not-allowed":
			_session_active = false
			error.emit(-1)
			listening_stopped.emit()
		"aborted":
			pass
		"no-speech":
			pass
		"network", "audio-capture":
			# Not recoverable by restarting (no recognizer service / no mic):
			# end the session so onend stops restarting, and report -1 so
			# callers fall back to typing instead of re-listening in a loop.
			_session_active = false
			error.emit(-1)
			listening_stopped.emit()
		_:
			error.emit(1)
			listening_stopped.emit()


func _on_js_end(_args: Array) -> void:
	if _intentional_stop or _suspended:
		return
	if _session_active:
		# With continuous=true, onend shouldn't fire unless stopped
		# But if it does (browser quirk), restart
		print("[WebSTTProvider] onend fired unexpectedly, restarting...")
		await get_tree().process_frame
		if _session_active and not _intentional_stop and not _suspended:
			_eval_start()