extends Node2D
## The mic must be released when the page is hidden or closed (web) or the app
## goes to the background (Android/iOS), and a session that is still wanted must
## come back on return. Covers the provider state machines; the browser calls
## themselves are counted by overriding the JavaScriptBridge wrappers.
## Run headless on a scratch copy:
##   Godot --headless --path <copy> res://tools/tests/test_stt_suspend.tscn

var passes := 0
var failures := 0


class CountingWebProvider extends WebSTTProvider:
	var starts := 0
	var releases := 0

	func _web_runtime() -> bool:
		return true

	func _apply_language() -> void:
		pass

	func _eval_start() -> String:
		starts += 1
		return "ok"

	func _eval_stop() -> void:
		releases += 1


class FakePlugin extends RefCounted:
	var listens := 0
	var stops := 0

	func listen() -> void:
		listens += 1

	func stop() -> void:
		stops += 1


func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, (" — " + detail) if detail != "" else "")


func _ready() -> void:
	await _web_provider()
	_native_provider("android", AndroidSTTProvider.new())
	_native_provider("ios", IosSTTProvider.new())
	_manager_forwards_app_lifecycle()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	get_tree().quit(1 if failures else 0)


func _web_provider() -> void:
	var web := CountingWebProvider.new()
	add_child(web)
	web._recognition = RefCounted.new()

	web.listen()
	_check("web: listen starts recognition", web.starts == 1)
	web.suspend()
	_check("web: hiding the page releases the mic", web.releases == 1)
	web._on_js_end([])
	await get_tree().process_frame
	await get_tree().process_frame
	_check("web: the end event after release does not restart", web.starts == 1, "starts=%d" % web.starts)

	var started := [0]
	web.listening_started.connect(func(): started[0] += 1)
	web.listen()
	_check("web: listen while hidden does not grab the mic", web.starts == 1, "starts=%d" % web.starts)
	_check("web: listen while hidden still reports listening", started[0] == 1)
	web._on_js_end([])
	await get_tree().process_frame
	_check("web: a late end event while hidden does not restart", web.starts == 1, "starts=%d" % web.starts)

	web.resume()
	_check("web: visible again resumes the wanted session", web.starts == 2, "starts=%d" % web.starts)
	web.resume()
	_check("web: a second visible event does not double-start", web.starts == 2, "starts=%d" % web.starts)

	web.stop()
	web.suspend()
	web.resume()
	_check("web: no session wanted, nothing resumes", web.starts == 2, "starts=%d" % web.starts)
	_check("web: stop releases with abort path", web.releases == 3, "releases=%d" % web.releases)
	web.queue_free()


func _native_provider(label: String, provider: SttProvider) -> void:
	var plugin := FakePlugin.new()
	provider.set("_plugin", plugin)
	var stopped := [0]
	provider.listening_stopped.connect(func(): stopped[0] += 1)

	provider.suspend()
	_check(label + ": background with no listen touches nothing", plugin.stops == 0)

	provider.listen()
	var stopped_before: int = stopped[0]
	provider.suspend()
	_check(label + ": background stops the plugin", plugin.stops == 1)
	_check(label + ": background does not report the listen as ended", stopped[0] == stopped_before)
	provider.resume()
	_check(label + ": return restarts the listen", plugin.listens == 2, "listens=%d" % plugin.listens)
	provider.resume()
	_check(label + ": a second return does not double-start", plugin.listens == 2)

	provider.call("_on_plugin_listening_completed", "hello")
	provider.suspend()
	provider.resume()
	_check(label + ": a finished listen is not restarted", plugin.listens == 2 and plugin.stops == 1)

	provider.listen()
	provider.stop()
	provider.suspend()
	provider.resume()
	_check(label + ": a stopped listen is not restarted", plugin.listens == 3, "listens=%d" % plugin.listens)
	provider.free()


func _manager_forwards_app_lifecycle() -> void:
	var fake := CountingWebProvider.new()
	fake._recognition = RefCounted.new()
	var saved = STTManager.provider
	STTManager.provider = fake
	fake.listen()
	STTManager.notification(NOTIFICATION_APPLICATION_PAUSED)
	_check("manager: app paused suspends the provider", fake._suspended and fake.releases == 1)
	STTManager.notification(NOTIFICATION_APPLICATION_RESUMED)
	_check("manager: app resumed resumes the provider", not fake._suspended and fake.starts == 2)
	STTManager.provider = saved
	fake.free()
