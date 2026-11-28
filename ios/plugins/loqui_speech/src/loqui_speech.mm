#include "loqui_speech.h"

#include "core/config/engine.h"
#include "core/object/class_db.h"

#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>

@interface LoquiSpeechSession : NSObject
@property(nonatomic, strong) SFSpeechRecognizer *recognizer;
@property(nonatomic, strong) SFSpeechAudioBufferRecognitionRequest *request;
@property(nonatomic, strong) SFSpeechRecognitionTask *task;
@property(nonatomic, strong) AVAudioEngine *engine;
@end

@implementation LoquiSpeechSession
@end

static LoquiSpeech *plugin = nullptr;

// The audio session as Godot configured it, saved before listen() switches it to
// Record. Record silences all playback, so stop() must put it back or the game
// stays mute after the first challenge.
static AVAudioSessionCategory saved_category = nil;
static AVAudioSessionMode saved_mode = nil;
static AVAudioSessionCategoryOptions saved_options = 0;

static void save_audio_session(AVAudioSession *audio) {
	if (saved_category != nil) {
		return;
	}
	saved_category = audio.category;
	saved_mode = audio.mode;
	saved_options = audio.categoryOptions;
}

static void restore_audio_session() {
	if (saved_category == nil) {
		return;
	}
	NSError *error = nil;
	[[AVAudioSession sharedInstance] setCategory:saved_category mode:saved_mode options:saved_options error:&error];
	if (error != nil) {
		NSLog(@"[LoquiSpeech] restoring audio session failed: %@", error);
	}
	saved_category = nil;
	saved_mode = nil;
	saved_options = 0;
}

extern "C" __attribute__((visibility("default"))) void loqui_speech_init() {
	ClassDB::register_class<LoquiSpeech>();
	plugin = memnew(LoquiSpeech);
	Engine::get_singleton()->add_singleton(Engine::Singleton("LoquiSpeechIOS", plugin));
}

extern "C" __attribute__((visibility("default"))) void loqui_speech_deinit() {
	if (plugin) {
		plugin->stop();
		memdelete(plugin);
		plugin = nullptr;
	}
}

void LoquiSpeech::_bind_methods() {
	ClassDB::bind_method(D_METHOD("listen"), &LoquiSpeech::listen);
	ClassDB::bind_method(D_METHOD("stop"), &LoquiSpeech::stop);
	ClassDB::bind_method(D_METHOD("set_language", "lang"), &LoquiSpeech::set_language);
	ADD_SIGNAL(MethodInfo("listening_completed", PropertyInfo(Variant::STRING, "result")));
	ADD_SIGNAL(MethodInfo("error", PropertyInfo(Variant::INT, "error_code")));
}

LoquiSpeech::LoquiSpeech() {}

LoquiSpeech::~LoquiSpeech() {
	stop();
}

void LoquiSpeech::emit_completed(const String &text) {
	_listening = false;
	emit_signal("listening_completed", text);
}

void LoquiSpeech::emit_failure(int code) {
	_listening = false;
	emit_signal("error", code);
}

void LoquiSpeech::set_language(const String &lang) {
	_language = lang.is_empty() ? String("en-US") : lang;
}

void LoquiSpeech::stop() {
	_listening = false;
	if (_session != nullptr) {
		LoquiSpeechSession *session = (__bridge_transfer LoquiSpeechSession *)_session;
		_session = nullptr;
		[session.task cancel];
		session.task = nil;
		[session.engine stop];
		[session.engine.inputNode removeTapOnBus:0];
		[session.request endAudio];
		session.request = nil;
		session.engine = nil;
		session.recognizer = nil;
	}
	restore_audio_session();
}

void LoquiSpeech::listen() {
	stop();
	_listening = true;

	CharString locale_utf8 = _language.utf8();
	NSString *localeId = [NSString stringWithUTF8String:locale_utf8.get_data()];
	NSLocale *locale = [NSLocale localeWithLocaleIdentifier:localeId];
	SFSpeechRecognizer *recognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
	if (recognizer == nil || !recognizer.isAvailable) {
		emit_failure(-1);
		return;
	}

	LoquiSpeech *self_ptr = this;
	[SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
		if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
			dispatch_async(dispatch_get_main_queue(), ^{
				self_ptr->emit_failure(-1);
			});
			return;
		}
		AVAudioSession *audio = [AVAudioSession sharedInstance];
		[audio requestRecordPermission:^(BOOL granted) {
			if (!granted || !self_ptr->_listening) {
				dispatch_async(dispatch_get_main_queue(), ^{
					self_ptr->emit_failure(-1);
				});
				return;
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				if (!self_ptr->_listening) {
					return;
				}
				NSError *sessionError = nil;
				save_audio_session(audio);
				[audio setCategory:AVAudioSessionCategoryRecord mode:AVAudioSessionModeMeasurement options:AVAudioSessionCategoryOptionDuckOthers error:&sessionError];
				[audio setActive:YES error:&sessionError];
				if (sessionError != nil) {
					restore_audio_session();
					self_ptr->emit_failure(-1);
					return;
				}

				LoquiSpeechSession *session = [LoquiSpeechSession new];
				session.recognizer = recognizer;
				session.engine = [AVAudioEngine new];
				session.request = [SFSpeechAudioBufferRecognitionRequest new];
				session.request.shouldReportPartialResults = NO;
				self_ptr->_session = (__bridge_retained void *)session;

				AVAudioInputNode *input = session.engine.inputNode;
				AVAudioFormat *format = [input outputFormatForBus:0];
				[input installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
					[session.request appendAudioPCMBuffer:buffer];
				}];

				// The handler runs on a Speech framework queue. Godot signals and the
				// audio session are only safe to touch on the main thread.
				session.task = [session.recognizer recognitionTaskWithRequest:session.request resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
					BOOL final_result = result != nil && result.isFinal;
					NSString *text = final_result ? result.bestTranscription.formattedString : nil;
					if (error == nil && !final_result) {
						return;
					}
					dispatch_async(dispatch_get_main_queue(), ^{
						// Ignore a late callback for a session that stop() or a newer
						// listen() already replaced.
						if (!self_ptr->_listening || self_ptr->_session != (__bridge void *)session) {
							return;
						}
						if (error != nil) {
							self_ptr->stop();
							self_ptr->emit_failure(1);
							return;
						}
						const char *utf8 = text.UTF8String;
						String spoken = String::utf8(utf8 != nullptr ? utf8 : "");
						self_ptr->stop();
						self_ptr->emit_completed(spoken);
					});
				}];

				NSError *startError = nil;
				[session.engine prepare];
				[session.engine startAndReturnError:&startError];
				if (startError != nil) {
					self_ptr->stop();
					self_ptr->emit_failure(-1);
				}
			});
		}];
	}];
}
