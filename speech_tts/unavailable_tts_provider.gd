# unavailable_tts_provider.gd
#
# No-op TTS backend for platforms without a usable speech synthesizer.
# Every call is harmless so callers can stay platform-agnostic.

class_name UnavailableTTSProvider
extends TTSSpeechProvider


func is_available() -> bool:
	return false


func speak(_text: String) -> bool:
	return false


func stop() -> void:
	pass


func is_speaking() -> bool:
	return false
