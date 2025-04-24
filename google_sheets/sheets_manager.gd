# sheets_manager.gd

extends Node

const API_URL = "https://script.google.com/macros/s/AKfycbyqeyVMNfMOyTYBJAufy3WyBKtKFhPU5rhyiTi6LC5ybIWdSQ-z66_jGw0v90ShAk9LKA/exec"

signal sentences_loaded(sentences)
signal words_loaded(words)

# ✅ Fetch both sentences and words from Google Sheets
func fetch_sentences_and_words():
	var http = HTTPRequest.new()
	add_child(http)

	var request_url = API_URL + "?action=get_sentences_and_words"

	# ✅ Prevent duplicate listeners
	if http.request_completed.is_connected(_on_sentences_and_words_received):
		http.request_completed.disconnect(_on_sentences_and_words_received)
	
	http.request_completed.connect(_on_sentences_and_words_received.bind(http))
	var error = http.request(request_url)

	if error != OK:
		print("[ERROR] Failed to request sentences and words:", error)
	else:
		print("[INFO] Requesting sentences and words from Google Sheets...")

# ✅ Handle response for sentences & words fetch
func _on_sentences_and_words_received(result, response_code, headers, body, http):
	print("[DEBUG] Sentences & Words Response Code:", response_code)

	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		if response:
			if response.has("sentences"):
				emit_signal("sentences_loaded", response["sentences"])
				print("[INFO] Loaded sentences from Google Sheets:", response["sentences"])
			if response.has("words"):
				emit_signal("words_loaded", response["words"])
				print("[INFO] Loaded words from Google Sheets:", response["words"])
		else:
			print("[ERROR] Invalid response format:", response)
	else:
		print("[ERROR] Failed to fetch sentences and words! Response code:", response_code)

	# ✅ Free HTTPRequest node
	http.queue_free()

# ✅ Fetch sentences from Google Sheets
func fetch_sentences():
	var http = HTTPRequest.new()
	add_child(http)

	var request_url = API_URL + "?action=get_sentences"
	
	# ✅ Prevent duplicate listeners
	if http.request_completed.is_connected(_on_sentences_received):
		http.request_completed.disconnect(_on_sentences_received)
	
	http.request_completed.connect(_on_sentences_received.bind(http))
	var error = http.request(request_url)

	if error != OK:
		print("[ERROR] Failed to request sentences:", error)
	else:
		print("[INFO] Requesting sentences from Google Sheets...")

# ✅ Handle response for sentence fetch
func _on_sentences_received(result, response_code, headers, body, http):
	print("[DEBUG] Sentence Response Code:", response_code)
	
	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		if response and response.has("sentences"):
			emit_signal("sentences_loaded", response["sentences"])
			print("[INFO] Loaded sentences from Google Sheets:", response["sentences"])
		else:
			print("[ERROR] Invalid response format:", response)
	else:
		print("[ERROR] Failed to fetch sentences! Response code:", response_code)

	# ✅ Free HTTPRequest node
	http.queue_free()

# ✅ Fetch words from Google Sheets
func fetch_words():
	var http = HTTPRequest.new()
	add_child(http)

	var request_url = API_URL + "?action=get_words"

	# ✅ Prevent duplicate listeners
	if http.request_completed.is_connected(_on_words_received):
		http.request_completed.disconnect(_on_words_received)
	
	http.request_completed.connect(_on_words_received.bind(http))
	var error = http.request(request_url)

	if error != OK:
		print("[ERROR] Failed to request words:", error)
	else:
		print("[INFO] Requesting words from Google Sheets...")

# ✅ Handle response for word fetch
func _on_words_received(result, response_code, headers, body, http):
	print("[DEBUG] Word Response Code:", response_code)

	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		if response and response.has("words"):
			emit_signal("words_loaded", response["words"])
			print("[INFO] Loaded words from Google Sheets:", response["words"])
		else:
			print("[ERROR] Invalid response format:", response)
	else:
		print("[ERROR] Failed to fetch words! Response code:", response_code)

	# ✅ Free HTTPRequest node
	http.queue_free()

# ✅ Save a sentence to Google Sheets
func save_sentence_entry(sentence: String, count: int, device_id: String = "Unknown", device_name: String = "Unknown Device"):
	var http = HTTPRequest.new()
	add_child(http)

	var data = {
		"action": "save_sentence_entry",
		"sentence": sentence,
		"count": count,  
		"device_id": device_id,
		"device_name": device_name
	}
	
	var json = JSON.stringify(data)
	var headers = ["Content-Type: application/json"]

	# ✅ Prevent duplicate listeners
	if http.request_completed.is_connected(_on_request_completed):
		http.request_completed.disconnect(_on_request_completed)
	
	http.request_completed.connect(_on_request_completed.bind(http))
	var error = http.request(API_URL, headers, HTTPClient.METHOD_POST, json)

	if error != OK:
		print("[ERROR] Failed to send sentence request:", error)
	else:
		print("[INFO] Sent sentence to Google Sheets:", data)

# ✅ Save a word to Google Sheets
func save_word_entry(word: String, count: int, device_id: String = "Unknown", device_name: String = "Unknown Device"):
	var http = HTTPRequest.new()
	add_child(http)

	var data = {
		"action": "save_word_entry",
		"word": word,
		"count": count,  
		"device_id": device_id,
		"device_name": device_name
	}
	
	var json = JSON.stringify(data)
	var headers = ["Content-Type: application/json"]

	# ✅ Prevent duplicate listeners
	if http.request_completed.is_connected(_on_request_completed):
		http.request_completed.disconnect(_on_request_completed)
	
	http.request_completed.connect(_on_request_completed.bind(http))
	var error = http.request(API_URL, headers, HTTPClient.METHOD_POST, json)

	if error != OK:
		print("[ERROR] Failed to send word request:", error)
	else:
		print("[INFO] Sent word to Google Sheets:", data)

# ✅ Handle response and free request node
func _on_request_completed(result, response_code, headers, body, http):
	print("[DEBUG] Response Code:", response_code)

	var response_body = body.get_string_from_utf8()
	print("[DEBUG] Response Body:", response_body)

	# ✅ Fix: Check if the response is valid JSON before logging
	var parsed_response = JSON.parse_string(response_body)
	if parsed_response:
		print("[INFO] Google Sheets Response:", parsed_response)
	else:
		print("[ERROR] Failed to parse response JSON.")

	# ✅ Free HTTPRequest node
	http.queue_free()
