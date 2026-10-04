class_name IosSTTProvider
extends SttProvider

var _plugin = null


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
	_plugin.listen()


func stop() -> void:
	_ensure_plugin()
	if _plugin != null and _plugin.has_method("stop"):
		_plugin.stop()


func set_language(lang: String) -> void:
	_ensure_plugin()
	if _plugin != null and _plugin.has_method("set_language"):
		_plugin.set_language(lang)


func _ensure_plugin() -> void:
	if _plugin == null and Engine.has_singleton("LoquiSpeechIOS"):
		_plugin = Engine.get_singleton("LoquiSpeechIOS")


func _on_plugin_listening_completed(result) -> void:
	listening_completed.emit(String(result) if result != null else "")


func _on_plugin_error(error_code) -> void:
	error.emit(error_code)
