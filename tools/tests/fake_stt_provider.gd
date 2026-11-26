extends SttProvider
## Test double: an STT backend that reports itself available (like Android)
## but never produces audio results. Tests drive STTManager's signals directly.

var listen_calls := 0


func is_available() -> bool:
	return true


func listen() -> void:
	listen_calls += 1
