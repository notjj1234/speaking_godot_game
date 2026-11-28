extends TTSSpeechProvider
## Test double: a read-aloud backend that "speaks" until finish() is called.

var spoken: Array[String] = []
var stops := 0
var talking := false


func is_available() -> bool:
	return true


func speak(text: String) -> bool:
	spoken.append(text)
	talking = true
	return true


func stop() -> void:
	stops += 1
	talking = false


func is_speaking() -> bool:
	return talking


## Ends the current line the way a device would.
func finish() -> void:
	talking = false
	speech_finished.emit()
