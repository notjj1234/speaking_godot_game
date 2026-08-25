extends Node2D

var STT  # Reference to SpeechToText plugin singleton
signal speech_result(success: bool)

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
	print("🟡 [STTManager] Ready. Checking mic permission...")

	# 🔄 Load mic test result from previous session
	mic_test_passed = ProjectSettings.get_setting("stt/mic_test_passed", false)

	if "RECORD_AUDIO" in OS.get_granted_permissions():
		print("✅ [STTManager] Mic permission already granted.")
		_initialize_stt()

		# Only test mic if it hasn’t passed before
		if not mic_test_passed:
			await get_tree().process_frame
			await _test_microphone()
	else:
		print("🎤 [STTManager] Requesting mic permission...")
		OS.request_permission("RECORD_AUDIO")
		await get_tree().create_timer(2.0).timeout

		# 🔁 Check again after delay
		if "RECORD_AUDIO" in OS.get_granted_permissions():
			print("✅ [STTManager] Mic permission granted after prompt.")
			_initialize_stt()
			await get_tree().process_frame
			await _test_microphone()
		else:
			print("❌ Mic permission denied.")
			show_restart_notice()

func _test_microphone():
	print("🎙️ [STTManager] Testing mic functionality...")
	if not Engine.has_singleton("SpeechToText"):
		print("❌ [STTManager] SpeechToText singleton missing during mic test.")
		show_restart_notice()
		return

	var test_STT = Engine.get_singleton("SpeechToText")
	if not test_STT.has_method("listen"):
		print("❌ [STTManager] STT.listen() not available.")
		show_restart_notice()
		return

	mic_test_result_received = false
	mic_test_mode = true

	if test_STT.is_connected("listening_completed", Callable(self, "_on_listening_completed")):
		test_STT.disconnect("listening_completed", Callable(self, "_on_listening_completed"))
	test_STT.connect("listening_completed", Callable(self, "_on_listening_completed"))

	test_STT.listen()
	await get_tree().create_timer(3.0).timeout

	if mic_test_result_received:
		print("✅ [STTManager] Mic test passed.")
		mic_test_passed = true

		# 🔒 Save result persistently
		ProjectSettings.set_setting("stt/mic_test_passed", true)
		ProjectSettings.save()
	else:
		print("❌ [STTManager] No mic input detected during test.")
		mic_test_passed = false
		show_restart_notice()

	mic_test_mode = false

func _on_listening_completed(args):
	if mic_test_mode:
		mic_test_result_received = true
		print("✅ [STTManager] Mic test result received.")
		return

	if args == null or args == "":
		_handle_result(false)
	else:
		var recognized_text = String(args).to_lower().strip_edges()
		_validate_speech(recognized_text)

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
		print("✅ Mic previously passed. Not showing panel again.")
		return

	mic_panel = _resolve_mic_panel()
	if mic_panel and mic_panel.has_node("VBoxContainer/ConfirmButton"):
		print("📢 [STTManager] Showing MicPermissionPanel...")
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
				print("❌ [STTManager] Failed to connect 'pressed' signal!")
			else:
				print("✅ [STTManager] Connected 'pressed' signal to _on_restart_confirmed.")
		else:
			print("🔄 [STTManager] Button already connected.")

		await get_tree().process_frame
		mic_panel.grab_focus()
	else:
		print("❌ [STTManager] MicPermissionPanel or ConfirmButton not found!")

func _on_restart_confirmed():
	print("🛑 [STTManager] Restart confirmed. Quitting app.")
	get_tree().quit()

func _initialize_stt():
	if Engine.has_singleton("SpeechToText"):
		STT = Engine.get_singleton("SpeechToText")
		STT.set_language("en")
		STT.connect("error", Callable(self, "_on_error"))
		STT.connect("listening_completed", Callable(self, "_on_listening_completed"))
		print("✅ STT initialized.")
	else:
		print("❌ SpeechToText singleton not found.")
		return

	sheets_manager.sentences_loaded.connect(_on_sentences_received)
	sheets_manager.fetch_sentences()

func _on_sentences_received(loaded_sentences: Array):
	if loaded_sentences.size() > 0:
		sentences = loaded_sentences
		print("✅ Loaded sentences from Google Sheets:", sentences)
	else:
		print("[WARNING] No sentences from Google Sheets. Using backup file.")
		load_sentences("res://SentenceData/sentences.txt")

func load_sentences(file_path: String):
	if not FileAccess.file_exists(file_path):
		print("❌ Sentences file not found:", file_path)
		return

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		print("❌ Could not open file:", file_path)
		return

	sentences.clear()
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line != "":
			sentences.append(line)
	file.close()

	if sentences.is_empty():
		print("⚠️ No sentences loaded from file.")
	else:
		print("✅ Loaded sentences from file:", sentences)

func get_random_sentence() -> String:
	if sentences.is_empty():
		print("❌ No sentences available.")
		return "No sentences available."
	var random_index = randi() % sentences.size()
	return sentences[random_index]

func start_speech_recognition(target_sentence: String, on_result_callback: Callable):
	if not Engine.has_singleton("SpeechToText"):
		print("❌ SpeechToText singleton not found.")
		on_result_callback.call(false)
		return

	self.target_sentence = target_sentence.to_lower().strip_edges()
	self.result_callback = on_result_callback

	var speech_scene_path = "res://SpeechToText/SpeechToText.tscn"
	if not FileAccess.file_exists(speech_scene_path):
		print("❌ Speech scene not found.")
		on_result_callback.call(false)
		return

	get_tree().change_scene_to_file(speech_scene_path)

	var current_scene = get_tree().current_scene
	if current_scene and current_scene.has_method("start_speech_recognition"):
		current_scene.start_speech_recognition(self.target_sentence, Callable(self, "_on_speech_result"))
	else:
		print("❌ Speech scene missing required method.")
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
