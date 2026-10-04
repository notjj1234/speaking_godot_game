#ifndef LOQUI_SPEECH_H
#define LOQUI_SPEECH_H

#include "core/object/object.h"

class LoquiSpeech : public Object {
	GDCLASS(LoquiSpeech, Object);

protected:
	static void _bind_methods();

public:
	void listen();
	void stop();
	void set_language(const String &lang);

	void emit_completed(const String &text);
	void emit_failure(int code);

	LoquiSpeech();
	~LoquiSpeech();

private:
	String _language = "en-US";
	bool _listening = false;
	void *_session = nullptr;
};

#endif
