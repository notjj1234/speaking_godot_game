# TTSManager.gd
#
# Autoload manager for text-to-speech. Selects a backend the same way
# STTManager selects STT providers (speech_to_text/STTManager.gd), so callers
# never special-case a platform.
#
# NOTE: no class_name — the autoload is already named TTSManager.

extends Node

signal speech_started
signal speech_finished

var provider: TTSSpeechProvider = null

var _speaking := false
var _speaking_since := 0
var _max_ms := 5000
var _idle_frames := 0
var _provider_label := "none"


func _ready() -> void:
	# Speech challenges run with the tree paused, so this must keep processing.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_provider()
	print("✅ TTSManager ready. Provider: ", _provider_label)
	set_process(false)


func is_available() -> bool:
	return provider != null and provider.is_available()


func speak(text: String) -> bool:
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		print("❌ TTSManager: empty text, not speaking.")
		return false
	if provider == null:
		print("❌ TTSManager: no provider, not speaking.")
		return false
	if not provider.is_available():
		print("⚠️ TTSManager: TTS unavailable, not speaking.")
		return false

	stop()
	if not provider.speak(cleaned):
		print("⚠️ TTSManager: provider refused to speak.")
		return false

	_speaking = true
	_speaking_since = Time.get_ticks_msec()
	_max_ms = clampi(4000 + cleaned.length() * 250, 5000, 20000)
	_idle_frames = 0
	set_process(true)
	speech_started.emit()
	return true


func stop() -> void:
	if provider != null:
		provider.stop()
	_finish_once()


func is_speaking() -> bool:
	return provider != null and provider.is_speaking()


func _process(_delta: float) -> void:
	if not _speaking or provider == null:
		set_process(false)
		return

	# Grace period: some engines report "not speaking" for a beat after starting.
	var elapsed := Time.get_ticks_msec() - _speaking_since
	if elapsed > 400 and not provider.is_speaking():
		_idle_frames += 1
		if _idle_frames >= 2:
			_finish_once()
			return
	else:
		_idle_frames = 0

	if elapsed > _max_ms:
		print("⚠️ TTSManager: speech watchdog expired, stopping.")
		provider.stop()
		_finish_once()


func _finish_once() -> void:
	if not _speaking:
		return
	_speaking = false
	_idle_frames = 0
	set_process(false)
	speech_finished.emit()


func _on_provider_started() -> void:
	if _speaking:
		return
	_speaking = true
	_speaking_since = Time.get_ticks_msec()
	set_process(true)


func _on_provider_finished() -> void:
	_finish_once()


func _create_provider() -> void:
	if provider != null:
		return

	if OS.has_feature("web"):
		provider = WebTTSProvider.new()
		_provider_label = "WebTTSProvider"
	elif OS.get_name() == "Android":
		provider = AndroidTTSProvider.new()
		_provider_label = "AndroidTTSProvider"
	else:
		provider = UnavailableTTSProvider.new()
		_provider_label = "UnavailableTTSProvider"
		print("⚠️ TTSManager: no TTS backend on this platform.")

	add_child(provider)

	if not provider.speech_started.is_connected(_on_provider_started):
		provider.speech_started.connect(_on_provider_started)
	if not provider.speech_finished.is_connected(_on_provider_finished):
		provider.speech_finished.connect(_on_provider_finished)
