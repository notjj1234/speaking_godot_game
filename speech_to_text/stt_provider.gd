class_name SttProvider
extends Node

signal listening_completed(result: String)
signal error(error_code)


func is_available() -> bool:
	return false


func listen() -> void:
	pass


func stop() -> void:
	pass


func set_language(_lang: String) -> void:
	pass
