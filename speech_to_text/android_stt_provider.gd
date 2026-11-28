class_name AndroidSTTProvider
extends SttProvider

var _plugin = null
## A listen is in progress (no result, error or stop yet).
var _listening := false
var _resume_on_return := false


func _ready() -> void:
	if Engine.has_singleton("SpeechToText"):
		_plugin = Engine.get_singleton("SpeechToText")
		if _plugin.has_signal("listening_completed") and not _plugin.listening_completed.is_connected(_on_plugin_listening_completed):
			_plugin.listening_completed.connect(_on_plugin_listening_completed)
		if _plugin.has_signal("error") and not _plugin.error.is_connected(_on_plugin_error):
			_plugin.error.connect(_on_plugin_error)


func is_available() -> bool:
	return Engine.has_singleton("SpeechToText")


func listen() -> void:
	_ensure_plugin()
	if _plugin == null or not _plugin.has_method("listen"):
		error.emit(-1)
		return
	_listening = true
	_plugin.listen()
	# The plugin only signals results and errors, so the provider reports the
	# listening state itself (the challenge card and mic indicator use it).
	listening_started.emit()


func stop() -> void:
	_listening = false
	_resume_on_return = false
	_ensure_plugin()
	if _plugin != null and _plugin.has_method("stop"):
		_plugin.stop()
	listening_stopped.emit()


## Stops the plugin without listening_stopped: callers treat that signal as the
## end of a listen and could restart it while the app is in the background.
func suspend() -> void:
	if not _listening:
		return
	_resume_on_return = true
	_listening = false
	if _plugin != null and _plugin.has_method("stop"):
		_plugin.stop()


func resume() -> void:
	if not _resume_on_return:
		return
	_resume_on_return = false
	listen()


func set_language(lang: String) -> void:
	_ensure_plugin()
	if _plugin != null and _plugin.has_method("set_language"):
		_plugin.set_language(lang)


func _ensure_plugin() -> void:
	if _plugin == null and Engine.has_singleton("SpeechToText"):
		_plugin = Engine.get_singleton("SpeechToText")


## One-shot recognition: a result or an error ends the listen. Report stopped
## first, so a listen() restarted by the handlers below reads as listening.
func _on_plugin_listening_completed(result) -> void:
	_listening = false
	listening_stopped.emit()
	listening_completed.emit(String(result) if result != null else "")


func _on_plugin_error(error_code) -> void:
	_listening = false
	listening_stopped.emit()
	error.emit(error_code)
