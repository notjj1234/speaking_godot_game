class_name IosSTTProvider
extends SttProvider

var _plugin = null
## A listen is in progress (no result, error or stop yet).
var _listening := false
var _resume_on_return := false


func _ready() -> void:
	_ensure_plugin()
	if _plugin == null:
		return
	if _plugin.has_signal("listening_completed") and not _plugin.listening_completed.is_connected(_on_plugin_listening_completed):
		_plugin.listening_completed.connect(_on_plugin_listening_completed)
	if _plugin.has_signal("error") and not _plugin.error.is_connected(_on_plugin_error):
		_plugin.error.connect(_on_plugin_error)


func is_available() -> bool:
	return Engine.has_singleton("LoquiSpeechIOS")


func listen() -> void:
	_ensure_plugin()
	if _plugin == null or not _plugin.has_method("listen"):
		error.emit(-1)
		return
	_listening = true
	_plugin.listen()


func stop() -> void:
	_listening = false
	_resume_on_return = false
	_ensure_plugin()
	if _plugin != null and _plugin.has_method("stop"):
		_plugin.stop()


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
	if _plugin == null and Engine.has_singleton("LoquiSpeechIOS"):
		_plugin = Engine.get_singleton("LoquiSpeechIOS")


func _on_plugin_listening_completed(result) -> void:
	_listening = false
	listening_completed.emit(String(result) if result != null else "")


func _on_plugin_error(error_code) -> void:
	_listening = false
	error.emit(error_code)
