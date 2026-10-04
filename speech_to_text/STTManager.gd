extends Node2D

signal speech_result(success: bool)
signal listening_completed(result: String)
signal partial_transcript(result: String)
signal error(error_code)
signal listening_started
signal listening_stopped

var STT  # Kept for compatibility; prefer `provider`.
var provider: SttProvider = null

@onready var sheets_manager = get_node("/root/SheetsManager")
var mic_panel: Control = null

var mic_button: Button
var target_sentence: String = ""
var result_callback: Callable
var sentences: Array = []

var mic_test_passed := false
var mic_test_mode := false
var mic_test_result_received := false


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[STTManager] Ready.")
	_create_provider()
	_initialize_stt()

	if OS.get_name() != "Android":
		return

	print("[STTManager] Android: checking mic permission...")
	mic_test_passed = ProjectSettings.get_setting("stt/mic_test_passed", false)

	if "RECORD_AUDIO" in OS.get_granted_permissions():
		print("[STTManager] Mic permission already granted.")
		if not mic_test_passed:
			await get_tree().process_frame
			await _test_microphone()
	else:
		print("[STTManager] Requesting mic permission...")
		OS.request_permission("RECORD_AUDIO")
		await get_tree().create_timer(2.0).timeout

		if "RECORD_AUDIO" in OS.get_granted_permissions():
			print("[STTManager] Mic permission granted after prompt.")
			if not mic_test_passed:
				await get_tree().process_frame
				await _test_microphone()
		else:
			print("[STTManager] Mic permission denied.")
			show_restart_notice()


func is_speech_available() -> bool:
	return provider != null and provider.is_available()


func listen() -> void:
	if provider == null:
		print("[STTManager] listen() called with no provider.")
		return
	provider.listen()


func stop() -> void:
	if provider != null:
		provider.stop()


func set_language(lang: String) -> void:
	if provider != null:
		provider.set_language(lang)


func prime_web_permission() -> void:
	if not OS.has_feature("web"):
		return
	if provider is WebSTTProvider:
		(provider as WebSTTProvider).prime_permission()


func begin_challenge_listen() -> void:
	listen()


func end_challenge_listen() -> void:
	stop()


func _create_provider() -> void:
	if provider != null:
		return

	if Engine.has_singleton("SpeechToText"):
		provider = AndroidSTTProvider.new()
		print("[STTManager] Using Android SpeechToText plugin.")
	elif Engine.has_singleton("LoquiSpeechIOS"):
		provider = IosSTTProvider.new()
		print("[STTManager] Using iOS speech recognition plugin.")
	elif OS.has_feature("web"):
		provider = WebSTTProvider.new()
		print("[STTManager] Using Web Speech API provider.")
	else:
		provider = UnavailableSTTProvider.new()
		print("[STTManager] No STT backend on this platform.")

	add_child(provider)

	if provider is WebSTTProvider and not provider.is_available():
		print("[STTManager] Web Speech API not present. Falling back to unavailable provider.")
		provider.queue_free()
		provider = UnavailableSTTProvider.new()
		add_child(provider)


func _test_microphone():
	print("[STTManager] Testing mic functionality...")
	if not is_speech_available() or provider == null or not provider.has_method("listen"):
		print("[STTManager] Speech provider missing during mic test.")
		show_restart_notice()
		return

	mic_test_result_received = false
	mic_test_mode = true
	provider.listen()
	await get_tree().create_timer(3.0).timeout

	if mic_test_result_received:
		print("[STTManager] Mic test passed.")
		mic_test_passed = true
		ProjectSettings.set_setting("stt/mic_test_passed", true)
		ProjectSettings.save()
	else:
		print("[STTManager] No mic input detected during test.")
		mic_test_passed = false
		show_restart_notice()

	mic_test_mode = false


func _on_listening_completed(args):
	if mic_test_mode:
		mic_test_result_received = true
		print("[STTManager] Mic test result received.")
		return

	var recognized := String(args) if args != null else ""
	listening_completed.emit(recognized)

	if target_sentence.is_empty():
		return
	if args == null or args == "":
		_handle_result(false)
	else:
		_validate_speech(recognized.to_lower().strip_edges())


func _on_error(error_code) -> void:
	print("[STTManager] STT error: ", error_code)
	error.emit(error_code)


func _on_partial_transcript(args) -> void:
	var text := String(args) if args != null else ""
	if not text.strip_edges().is_empty():
		partial_transcript.emit(text)


func _on_listening_started() -> void:
	listening_started.emit()


func _on_listening_stopped() -> void:
	listening_stopped.emit()


func _resolve_mic_panel() -> Control:
	# Autoload _ready runs before any level scene exists, so resolve lazily
	var current := get_tree().current_scene
	if current:
		var panel = current.get_node_or_null("UILayer/UIRoot/MicPermissionPanel")
		if panel:
			return panel
	# Fallback: playground hard path (kept for older layouts)
	return get_node_or_null("/root/Playground/UILayer/UIRoot/MicPermissionPanel")


func show_restart_notice():
	if mic_test_passed:
		print("[STTManager] Mic previously passed. Not showing panel again.")
		return

	mic_panel = _resolve_mic_panel()
	if mic_panel and mic_panel.has_node("VBoxContainer/ConfirmButton"):
		print("[STTManager] Showing MicPermissionPanel...")
		mic_button = mic_panel.get_node("VBoxContainer/ConfirmButton")
		mic_panel.visible = true
		# Ensure the parent UILayer is visible so the panel can be seen
		var ui_layer = mic_panel.get_parent().get_parent() if mic_panel.get_parent() else null
		if ui_layer:
			ui_layer.visible = true

		var screen_size = get_viewport().get_visible_rect().size
		mic_panel.set_anchors_preset(Control.PRESET_CENTER)
		mic_panel.set_position(screen_size / 2 - mic_panel.size / 2)

		if not mic_button.is_connected("pressed", Callable(self, "_on_restart_confirmed")):
			var success = mic_button.connect("pressed", Callable(self, "_on_restart_confirmed"))
			if success != OK:
				print("[STTManager] Failed to connect 'pressed' signal!")
			else:
				print("[STTManager] Connected 'pressed' signal to _on_restart_confirmed.")
		else:
			print("[STTManager] Button already connected.")

		await get_tree().process_frame
		mic_panel.grab_focus()
	else:
		print("[STTManager] MicPermissionPanel or ConfirmButton not found!")


func _on_restart_confirmed():
	print("[STTManager] Restart confirmed. Quitting app.")
	get_tree().quit()


func _initialize_stt():
	if provider == null:
		_create_provider()

	if provider != null:
		STT = provider
		var settings = get_node_or_null("/root/SettingsManager")
		var lang := "en"
		if settings:
			lang = settings.stt_language
		provider.set_language(lang)
		if not provider.listening_completed.is_connected(_on_listening_completed):
			provider.listening_completed.connect(_on_listening_completed)
		if not provider.partial_transcript.is_connected(_on_partial_transcript):
			provider.partial_transcript.connect(_on_partial_transcript)
		if not provider.error.is_connected(_on_error):
			provider.error.connect(_on_error)
		if not provider.listening_started.is_connected(_on_listening_started):
			provider.listening_started.connect(_on_listening_started)
		if not provider.listening_stopped.is_connected(_on_listening_stopped):
			provider.listening_stopped.connect(_on_listening_stopped)
		print("[STTManager] STT initialized. available=", is_speech_available())
	else:
		print("[STTManager] No STT provider.")

	call_deferred("_fetch_sentences")


func _fetch_sentences() -> void:
	if sheets_manager == null:
		sheets_manager = get_node_or_null("/root/SheetsManager")
	if sheets_manager == null:
		print("[STTManager] SheetsManager not found.")
		return
	if not sheets_manager.sentences_loaded.is_connected(_on_sentences_received):
		sheets_manager.sentences_loaded.connect(_on_sentences_received)
	sheets_manager.fetch_sentences()


func _on_sentences_received(loaded_sentences: Array):
	if loaded_sentences.size() > 0:
		sentences = loaded_sentences
		print("[STTManager] Loaded sentences from Google Sheets:", sentences)
	else:
		print("[WARNING] No sentences from Google Sheets. Using backup file.")
		load_sentences("res://sentence_data/sentences.txt")


func load_sentences(file_path: String):
	if not FileAccess.file_exists(file_path):
		print("[STTManager] Sentences file not found:", file_path)
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		print("[STTManager] Could not open file:", file_path)
		return

	sentences.clear()
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line != "":
			sentences.append(line)
	file.close()

	if sentences.is_empty():
		print("[STTManager] No sentences loaded from file.")
	else:
		print("[STTManager] Loaded sentences from file:", sentences)


func get_random_sentence() -> String:
	if sentences.is_empty():
		print("[STTManager] No sentences available.")
		return "No sentences available."
	var random_index = randi() % sentences.size()
	return sentences[random_index]


func start_speech_recognition(target_sentence: String, on_result_callback: Callable):
	if not is_speech_available():
		print("[STTManager] Speech not available.")
		on_result_callback.call(false)
		return

	self.target_sentence = target_sentence.to_lower().strip_edges()
	self.result_callback = on_result_callback

	var speech_scene_path = "res://SpeechToText/SpeechToText.tscn"
	if not FileAccess.file_exists(speech_scene_path):
		print("[STTManager] Speech scene not found.")
		on_result_callback.call(false)
		return

	get_tree().change_scene_to_file(speech_scene_path)

	var current_scene = get_tree().current_scene
	if current_scene and current_scene.has_method("start_speech_recognition"):
		current_scene.start_speech_recognition(self.target_sentence, Callable(self, "_on_speech_result"))
	else:
		print("[STTManager] Speech scene missing required method.")
		on_result_callback.call(false)


func _validate_speech(recognized_text: String):
	if recognized_text == target_sentence:
		_handle_result(true)
	else:
		_handle_result(false)


func _handle_result(success: bool):
	emit_signal("speech_result", success)
	if result_callback and result_callback.is_valid():
		result_callback.call(success)
