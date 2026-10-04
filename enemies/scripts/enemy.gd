# enemy.gd

class_name Enemy
extends CharacterBody2D

signal direction_changed(new_direction: Vector2)
signal enemy_damaged(hurt_box: HurtBox)
signal enemy_destroyed(hurt_box: HurtBox)

const DIR_4 = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]

@export var hp: int = 3
@export var move_speed: float = 30.0
@export var bounce_delay: float = 0.3  # Pause before bouncing

@export_category("Split On Destroy")
@export var splits_on_destroy: bool = false
@export var split_count: int = 2
@export var split_hp: int = 1
@export var split_scale: float = 0.65
@export var split_chase_speed: float = 75.0
@export var split_scene: PackedScene
@export var split_vision_scale: float = 1.35
## Seconds of invulnerability after spawning so a leftover swing / post-speech
## resume cannot immediately chain into another speech challenge.
@export var split_spawn_grace: float = 1.0
## How far split siblings try to stay apart (also used as orbit radius around the player).
@export var split_separation: float = 44.0

## Runtime spacing for split children (0 = disabled). Set by spawn_split_children.
var separation_distance: float = 0.0
var split_orbit_index: int = -1
var split_orbit_count: int = 0

var cardinal_direction: Vector2 = Vector2.DOWN
var direction: Vector2 = Vector2.ZERO
var is_bouncing: bool = false
var player: Player
var invulnerable: bool = false
var practice_dummy: bool = false

var challenge_hurt_box: HurtBox  # Store the hurt_box during the speech challenge
var _last_partial_match: String = ""

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $Sprite2D
@onready var hit_box: HitBox = $HitBox
@onready var state_machine: EnemyStateMachine = $EnemyStateMachine
@onready var player_hud: PlayerHudUI = PlayerHud  # Reference to Player HUD

func _ready() -> void:
	state_machine.Initialize(self)
	player = PlayerManager.player
	hit_box.damaged.connect(_take_damage)

	# Start facing a random direction
	var directions = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	direction = directions[randi() % directions.size()]
	set_direction(direction)

func _process(_delta): pass

func _physics_process(_delta):
	if practice_dummy:
		velocity = Vector2.ZERO
		return
	if is_bouncing:
		return

	# Optional chaos pause mid-movement
	if randi() % 400 == 0:
		is_bouncing = true
		velocity = Vector2.ZERO
		await get_tree().create_timer(0.5).timeout
		is_bouncing = false
		return

	velocity = direction * move_speed
	move_and_slide()

	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		if collision:
			_handle_bounce()
			break

func _handle_bounce() -> void:
	is_bouncing = true
	velocity = Vector2.ZERO

	var reverse_dir = -direction
	var possible_directions = DIR_4.duplicate()
	possible_directions.erase(reverse_dir)

	# Chaos mode: 20% chance to include all directions again
	if randi() % 5 == 0:
		possible_directions = DIR_4.duplicate()

	direction = possible_directions[randi() % possible_directions.size()]
	set_direction(direction)
	update_animation("walk")

	# 25% chance to look confused and idle
	if randi() % 4 == 0:
		await get_tree().create_timer(0.5).timeout

	await get_tree().create_timer(bounce_delay).timeout
	is_bouncing = false

func set_direction(_new_direction: Vector2) -> bool:
	direction = _new_direction
	if direction == Vector2.ZERO:
		return false

	var direction_id: int = int(round(
		(direction + cardinal_direction * 0.1).angle()
		/ TAU * DIR_4.size()
	))
	var new_dir = DIR_4[direction_id]

	if new_dir == cardinal_direction:
		return false

	cardinal_direction = new_dir
	direction_changed.emit(new_dir)
	sprite.scale.x = -1 if cardinal_direction == Vector2.LEFT else 1

	update_animation("walk")
	return true

func update_animation(state: String) -> void:
	animation_player.play(state + "_" + anim_direction())

func anim_direction() -> String:
	if cardinal_direction == Vector2.DOWN:
		return "down"
	elif cardinal_direction == Vector2.UP:
		return "up"
	else:
		return "side"


func spawn_split_children() -> void:
	if not splits_on_destroy:
		return
	# Prefer explicit scene; otherwise reload this enemy's own scene (avoids circular PackedScene refs).
	var scene: PackedScene = split_scene
	if scene == null and not scene_file_path.is_empty():
		scene = load(scene_file_path) as PackedScene
	if scene == null:
		print("⚠️ splits_on_destroy set but split_scene is null")
		return
	splits_on_destroy = false
	var parent_node := get_parent()
	if parent_node == null:
		return
	var ring_radius: float = maxf(split_separation, 36.0)
	for i in range(split_count):
		var child: Enemy = scene.instantiate() as Enemy
		if child == null:
			continue
		child.splits_on_destroy = false
		child.split_scene = null
		child.hp = split_hp
		child.scale = scale * split_scale
		child.separation_distance = split_separation
		child.split_orbit_index = i
		child.split_orbit_count = split_count
		# Block damage until the player re-engages — prevents instant speech after parent kill.
		child.invulnerable = true
		parent_node.add_child(child)
		var angle: float = TAU * float(i) / float(maxi(split_count, 1))
		var offset := Vector2.from_angle(angle) * ring_radius
		child.global_position = global_position + offset
		child.call_deferred(
			"_apply_split_aggro",
			split_chase_speed,
			split_vision_scale,
			split_spawn_grace
		)
		print("✅ Spawned split enemy at ", child.global_position)


func get_chase_target_position() -> Vector2:
	var player_node := PlayerManager.player
	if player_node == null:
		return global_position
	var player_pos: Vector2 = player_node.global_position
	if split_orbit_index < 0 or split_orbit_count <= 0:
		return player_pos
	# Hold a slot around the player so splits don't stack on the same pixel.
	var angle: float = TAU * float(split_orbit_index) / float(split_orbit_count)
	angle += Time.get_ticks_msec() * 0.00035
	var radius: float = maxf(separation_distance, 36.0)
	return player_pos + Vector2.from_angle(angle) * radius


func get_separation_vector() -> Vector2:
	if separation_distance <= 0.0:
		return Vector2.ZERO
	var parent_node := get_parent()
	if parent_node == null:
		return Vector2.ZERO
	var push := Vector2.ZERO
	for sibling in parent_node.get_children():
		if sibling == self or not (sibling is Enemy):
			continue
		var other := sibling as Enemy
		if other.invulnerable and other.hp <= 0:
			continue
		var delta: Vector2 = global_position - other.global_position
		var dist: float = delta.length()
		if dist < 0.001 or dist >= separation_distance:
			continue
		push += delta.normalized() * (1.0 - dist / separation_distance)
	if push.length_squared() > 1.0:
		push = push.normalized()
	return push


func _apply_split_aggro(chase_speed: float, vision_scale: float, spawn_grace: float = 1.0) -> void:
	move_speed = maxf(move_speed, chase_speed * 0.85)
	var chase := get_node_or_null("EnemyStateMachine/Chase")
	if chase:
		chase.set("chase_speed", chase_speed)
		chase.set("state_aggro_duration", 2.5)
	var vision := get_node_or_null("VisionArea")
	if vision:
		vision.scale = Vector2.ONE * vision_scale
	# Prefer chasing immediately if Chase state exists.
	if state_machine and chase:
		state_machine.change_state(chase)
	# Grace uses process_always so it ticks during any pause (e.g. speech challenge).
	if spawn_grace > 0.0:
		invulnerable = true
		await get_tree().create_timer(spawn_grace, true, true, true).timeout
	invulnerable = false


func make_practice_dummy() -> void:
	practice_dummy = true
	move_speed = 0.0
	velocity = Vector2.ZERO
	var hurt := get_node_or_null("HurtBox")
	if hurt is Area2D:
		hurt.set("monitoring", false)
		hurt.set("damage", 0)
	var idle: Node = get_node_or_null("EnemyStateMachine/Idle")
	if idle:
		idle.set("after_idle_state", null)
	if state_machine and idle is EnemyState:
		state_machine.change_state(idle)


# Handle taking damage from the player or other sources
func _take_damage(hurt_box: HurtBox) -> void:
	if invulnerable:
		return
	# One speech challenge at a time — ignore further hits while one is running
	# (also stops a single swing from farm-killing a clumped pack).
	var word_tracker = get_node_or_null("/root/WordTracker")
	if word_tracker and word_tracker.speech_challenge_active:
		return
	if get_tree().paused:
		return
	var dealt := hurt_box.damage
	var crit := hurt_box.was_crit
	if practice_dummy:
		DamageNumber.spawn(global_position + Vector2(randf_range(-8.0, 8.0), -22.0), dealt, crit, get_parent())
		enemy_damaged.emit(hurt_box)
		# Stay hittable so every swing can show a crit. The flinch still plays.
		invulnerable = false
		return
	hp -= dealt
	DamageNumber.spawn(global_position + Vector2(randf_range(-8.0, 8.0), -22.0), dealt, crit, get_parent())
	if hp > 0:
		enemy_damaged.emit(hurt_box)
	else:
		print("Enemy defeated. Initiating speech challenge...")

		if word_tracker:
			word_tracker.speech_challenge_active = true
			var challenge = word_tracker.get_random_speech_challenge()
			_start_speech_challenge(challenge, hurt_box)
		else:
			print("[ERROR] WordTracker not found! Using fallback sentence.")
			_start_speech_challenge("No challenge available.", hurt_box)

# Start the speech challenge
func _start_speech_challenge(target_sentence: String, hurt_box: HurtBox) -> void:
	challenge_hurt_box = hurt_box  # Store hurt_box for later use
	_last_partial_match = ""

	get_tree().paused = true  # Pause the game

	if player_hud:
		player_hud.show_speech_challenge(target_sentence)

	_connect_stt_signals()
	var stt = _stt_manager()
	if _is_web():
		_begin_web_challenge_mic()
		_show_typed_fallback()
		_connect_speak_button()
		if stt != null and stt.is_speech_available():
			if stt.has_method("begin_challenge_listen"):
				stt.begin_challenge_listen()
			else:
				stt.listen()
		return
	if stt != null and stt.is_speech_available():
		stt.listen()
	else:
		print("STT unavailable. Showing typed fallback.")
		_show_typed_fallback()

func _on_listening_completed(result: String) -> void:
	print("Listening completed: ", result)
	if player_hud:
		player_hud.update_live_transcript(result)

	if not has_node("/root/WordTracker"):
		print("Error: WordTracker singleton not found!")
		return

	var word_tracker = get_node("/root/WordTracker")
	var recognized_text: String
	var target_sentence: String
	if _is_web():
		recognized_text = _normalize_web_text(result)
		target_sentence = _normalize_web_text(player_hud.target_sentence)
	else:
		recognized_text = result.strip_edges().to_lower()
		target_sentence = player_hud.target_sentence.strip_edges().to_lower()

	if target_sentence != "" and target_sentence in recognized_text:
		print("Target phrase detected in speech:", target_sentence)
		word_tracker.add_spoken_word(player_hud.target_sentence)
		_on_speech_result(true)
		return

	print("Target phrase NOT found in speech:", target_sentence)
	if _is_web():
		if player_hud:
			player_hud.show_feedback(false)
		_show_typed_fallback()
		var stt = _stt_manager()
		if stt != null and stt.is_speech_available():
			stt.listen()
		return
	_on_speech_result(false)

func _on_speech_result(success: bool) -> void:
	var stt = _stt_manager()
	if _is_web():
		if stt and stt.has_method("end_challenge_listen"):
			stt.end_challenge_listen()
		elif stt:
			stt.stop()
	elif stt:
		stt.stop()
	_disconnect_stt_signals()
	_disconnect_fallback()
	_disconnect_speak_button()
	if player_hud:
		player_hud.hide_speech_challenge()
		player_hud.show_feedback(success)

	if success:
		print("Speech challenge passed! Storing word:", player_hud.target_sentence)
		enemy_destroyed.emit(challenge_hurt_box)

		if has_node("/root/WordTracker"):
			var word_tracker = get_node("/root/WordTracker")
			word_tracker.add_spoken_word(player_hud.target_sentence)
		else:
			print("Error: WordTracker singleton not found! Cannot store the word.")
		# EnemyStateDestroy handles queue_free after the destroy animation finishes

		_resume_game_after_challenge()

	else:
		print("Speech challenge failed. Try again.")

	# On failure, keep paused and let player retry (web path handles re-arm in _on_listening_completed)
	if not success:
		await _wait_feedback_and_resume()


func _resume_game_after_challenge() -> void:
	get_tree().paused = false
	if has_node("/root/WordTracker"):
		get_node("/root/WordTracker").speech_challenge_active = false
	if _is_web():
		_end_web_challenge_mic()


func _wait_feedback_and_resume() -> void:
	if player_hud != null:
		await player_hud.feedback_closed
	else:
		await get_tree().create_timer(PlayerHudUI.FEEDBACK_DURATION).timeout
	_resume_game_after_challenge()

func _on_speech_error(error_code) -> void:
	print("Speech recognition error: ", error_code)

	if error_code is String:
		var converted = int(error_code) if error_code.is_valid_int() else -1
		error_code = converted

	if _is_web():
		_show_typed_fallback()
		if error_code == -1:
			print("Web speech permission/start failed. Keeping typed fallback.")
			return
		print("Restarting web speech recognition due to error.")
		var web_stt = _stt_manager()
		if web_stt != null and web_stt.is_speech_available():
			web_stt.listen()
		return

	if error_code != -1:
		print("Restarting speech recognition due to error.")
		var stt = _stt_manager()
		if stt != null and stt.is_speech_available():
			stt.listen()
		else:
			_show_typed_fallback()
	else:
		print("Speech recognition failed. Showing typed fallback.")
		_show_typed_fallback()


func _stt_manager():
	return get_node_or_null("/root/STTManager")


func _is_web() -> bool:
	return OS.has_feature("web")


func _normalize_web_text(text: String) -> String:
	var cleaned := ""
	for i in text.length():
		var ch := text.substr(i, 1).to_lower()
		var code := ch.unicode_at(0)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57):
			cleaned += ch
		elif ch == " " or ch == "\t" or ch == "\n":
			cleaned += " "
	return " ".join(cleaned.split(" ", false))


func _begin_web_challenge_mic() -> void:
	for node in get_tree().get_nodes_in_group("touch_controls"):
		if node.has_method("begin_challenge_mic"):
			node.begin_challenge_mic()


func _end_web_challenge_mic() -> void:
	for node in get_tree().get_nodes_in_group("touch_controls"):
		if node.has_method("end_challenge_mic"):
			node.end_challenge_mic()


func _connect_stt_signals() -> void:
	var stt = _stt_manager()
	if stt == null:
		return
	_disconnect_stt_signals()
	stt.listening_completed.connect(_on_listening_completed)
	stt.partial_transcript.connect(_on_partial_transcript)
	stt.error.connect(_on_speech_error)
	stt.listening_started.connect(_on_stt_listening_started)
	stt.listening_stopped.connect(_on_stt_listening_stopped)


func _disconnect_stt_signals() -> void:
	var stt = _stt_manager()
	if stt == null:
		return
	if stt.listening_completed.is_connected(_on_listening_completed):
		stt.listening_completed.disconnect(_on_listening_completed)
	if stt.partial_transcript.is_connected(_on_partial_transcript):
		stt.partial_transcript.disconnect(_on_partial_transcript)
	if stt.error.is_connected(_on_speech_error):
		stt.error.disconnect(_on_speech_error)
	if stt.listening_started.is_connected(_on_stt_listening_started):
		stt.listening_started.disconnect(_on_stt_listening_started)
	if stt.listening_stopped.is_connected(_on_stt_listening_stopped):
		stt.listening_stopped.disconnect(_on_stt_listening_stopped)


func _on_stt_listening_started() -> void:
	if player_hud:
		player_hud.set_mic_state(true)


func _on_stt_listening_stopped() -> void:
	if player_hud:
		player_hud.set_mic_state(false)


func _on_partial_transcript(partial: String) -> void:
	if player_hud:
		player_hud.update_live_transcript(partial)

	if _is_web():
		var word_tracker = get_node_or_null("/root/WordTracker")
		if word_tracker and word_tracker.speech_challenge_active and player_hud:
			var normalized_partial = _normalize_web_text(partial)
			var target = _normalize_web_text(player_hud.target_sentence)
			if _contains_phrase(normalized_partial, target):
				if normalized_partial == _last_partial_match:
					_last_partial_match = ""
					_on_speech_result(true)
					return
				_last_partial_match = normalized_partial
			else:
				_last_partial_match = ""


func _contains_phrase(haystack: String, needle: String) -> bool:
	if needle.is_empty():
		return false
	var haystack_tokens = haystack.split(" ", false)
	var needle_tokens = needle.split(" ", false)
	if needle_tokens.size() > haystack_tokens.size():
		return false
	for i in range(haystack_tokens.size() - needle_tokens.size() + 1):
		var match = true
		for j in range(needle_tokens.size()):
			if haystack_tokens[i + j] != needle_tokens[j]:
				match = false
				break
		if match:
			return true
	return false


func _show_typed_fallback() -> void:
	if player_hud == null:
		return
	player_hud.show_typed_fallback()
	if _is_web():
		player_hud.show_speak_button()
	if not player_hud.fallback_submitted.is_connected(_on_listening_completed):
		player_hud.fallback_submitted.connect(_on_listening_completed)


func _disconnect_fallback() -> void:
	if player_hud == null:
		return
	if player_hud.fallback_submitted.is_connected(_on_listening_completed):
		player_hud.fallback_submitted.disconnect(_on_listening_completed)
	player_hud.hide_typed_fallback()
	player_hud.hide_speak_button()


func _connect_speak_button() -> void:
	if player_hud == null:
		return
	if not player_hud.speak_pressed.is_connected(_on_speak_pressed):
		player_hud.speak_pressed.connect(_on_speak_pressed)


func _disconnect_speak_button() -> void:
	if player_hud == null:
		return
	if player_hud.speak_pressed.is_connected(_on_speak_pressed):
		player_hud.speak_pressed.disconnect(_on_speak_pressed)


func _on_speak_pressed() -> void:
	if not _is_web():
		return
	var stt = _stt_manager()
	if stt != null and stt.is_speech_available():
		if stt.has_method("begin_challenge_listen"):
			stt.begin_challenge_listen()
		else:
			stt.listen()
