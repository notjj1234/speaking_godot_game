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

var cardinal_direction: Vector2 = Vector2.DOWN
var direction: Vector2 = Vector2.ZERO
var is_bouncing: bool = false
var player: Player
var invulnerable: bool = false

var challenge_hurt_box: HurtBox  # Store the hurt_box during the speech challenge

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

# Handle taking damage from the player or other sources
func _take_damage(hurt_box: HurtBox) -> void:
	if invulnerable:
		return
	hp -= hurt_box.damage
	if hp > 0:
		enemy_damaged.emit(hurt_box)
	else:
		print("Enemy defeated. Initiating speech challenge...")

		# ✅ Fetch challenge from `global_word_tracker.gd`
		var word_tracker = get_node("/root/WordTracker") if has_node("/root/WordTracker") else null
		if word_tracker:
			if word_tracker.speech_challenge_active:
				return
			word_tracker.speech_challenge_active = true
			var challenge = word_tracker.get_random_speech_challenge()
			_start_speech_challenge(challenge, hurt_box)
		else:
			print("[ERROR] WordTracker not found! Using fallback sentence.")
			_start_speech_challenge("No challenge available.", hurt_box)

# Start the speech challenge
func _start_speech_challenge(target_sentence: String, hurt_box: HurtBox) -> void:
	challenge_hurt_box = hurt_box  # Store hurt_box for later use

	get_tree().paused = true  # Pause the game
	if has_node("/root/WordTracker"):
		get_node("/root/WordTracker").speech_challenge_active = false

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

	else:
		print("Speech challenge failed. Try again.")

	get_tree().paused = false
	if _is_web():
		_end_web_challenge_mic()

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
	stt.error.connect(_on_speech_error)


func _disconnect_stt_signals() -> void:
	var stt = _stt_manager()
	if stt == null:
		return
	if stt.listening_completed.is_connected(_on_listening_completed):
		stt.listening_completed.disconnect(_on_listening_completed)
	if stt.error.is_connected(_on_speech_error):
		stt.error.disconnect(_on_speech_error)


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
