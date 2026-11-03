# tts_provider.gd
#
# Abstract text-to-speech backend. Concrete providers are selected once by
# TTSManager._create_provider(), mirroring the STT provider pattern in
# speech_to_text/stt_provider.gd. Callers must never branch on platform.

class_name TTSSpeechProvider
extends Node

signal speech_started
signal speech_finished


func is_available() -> bool:
	return false


func speak(_text: String) -> bool:
	return false


func stop() -> void:
	pass


func is_speaking() -> bool:
	return false
