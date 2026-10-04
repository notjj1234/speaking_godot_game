class_name SttProvider
extends Node

signal listening_completed(result: String)
signal partial_transcript(result: String)
signal error(error_code)
signal listening_started
signal listening_stopped


func is_available() -> bool:
	return false


func listen() -> void:
	pass


func stop() -> void:
	pass


func set_language(_lang: String) -> void:
	pass
