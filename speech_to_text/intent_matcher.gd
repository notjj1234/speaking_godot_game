class_name IntentMatcher
extends RefCounted
## Recognises what a player meant from a free-form transcript, using per-intent
## phrase lists: whole-word substring first, then the shared fuzzy matcher.

const FUZZY_MIN := 0.72


static func normalize(text: String) -> String:
	var cleaned := ""
	for i in text.length():
		var ch := text.substr(i, 1).to_lower()
		var code := ch.unicode_at(0)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57):
			cleaned += ch
		elif ch == " " or ch == "\t" or ch == "\n":
			cleaned += " "
	return " ".join(cleaned.split(" ", false))


static func contains_phrase(transcript: String, phrase: String) -> bool:
	var t := normalize(transcript)
	var p := normalize(phrase)
	if t == "" or p == "":
		return false
	if _has_whole_words(t, p):
		return true
	return PhoneticMatcher.transcript_contains_fuzzy(t, p, FUZZY_MIN)


## intents: {intent_id: Array of phrases}. Returns "" when nothing matches.
static func best_intent(transcript: String, intents: Dictionary) -> String:
	var t := normalize(transcript)
	if t == "":
		return ""
	var best_id := ""
	var best_len := 0
	for id in intents:
		for phrase in intents[id]:
			var p := normalize(str(phrase))
			if p != "" and p.length() > best_len and _has_whole_words(t, p):
				best_id = str(id)
				best_len = p.length()
	if best_id != "":
		return best_id
	for id in intents:
		for phrase in intents[id]:
			var p := normalize(str(phrase))
			if p != "" and PhoneticMatcher.transcript_contains_fuzzy(t, p, FUZZY_MIN):
				return str(id)
	return ""


static func _has_whole_words(normalized_transcript: String, normalized_phrase: String) -> bool:
	return (" %s " % normalized_transcript).contains(" %s " % normalized_phrase)
