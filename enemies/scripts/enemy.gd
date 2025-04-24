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

	if Engine.has_singleton("SpeechToText"):
		var STT = Engine.get_singleton("SpeechToText")
		if STT.is_connected("listening_completed", Callable(self, "_on_listening_completed")):
			STT.disconnect("listening_completed", Callable(self, "_on_listening_completed"))
		if STT.is_connected("error", Callable(self, "_on_speech_error")):
			STT.disconnect("error", Callable(self, "_on_speech_error"))

		STT.connect("listening_completed", Callable(self, "_on_listening_completed"))
		STT.connect("error", Callable(self, "_on_speech_error"))

		STT.listen()
	else:
		print("Error: SpeechToText singleton not found.")
		_on_speech_result(false)

func _on_listening_completed(result: String) -> void:
	print("Listening completed: ", result)
	if player_hud:
		player_hud.update_live_transcript(result)

	if not has_node("/root/WordTracker"):
		print("Error: WordTracker singleton not found!")
		return

	var word_tracker = get_node("/root/WordTracker")
	var recognized_text = result.strip_edges().to_lower()
	var target_sentence = player_hud.target_sentence.strip_edges().to_lower()

	if target_sentence in recognized_text:
		print("✅ Target phrase detected in speech:", target_sentence)
		word_tracker.add_spoken_word(player_hud.target_sentence)
		_on_speech_result(true)
	else:
		print("❌ Target phrase NOT found in speech:", target_sentence)
		_on_speech_result(false)

func _on_speech_result(success: bool) -> void:
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

		#await get_tree().create_timer(0.1).timeout  # Give time to unpause
		queue_free()

	else:
		print("Speech challenge failed. Try again.")

	get_tree().paused = false

func _on_speech_error(error_code) -> void:
	print("Speech recognition error: ", error_code)

	if error_code is String:
		var converted = int(error_code) if error_code.is_valid_int() else -1
		error_code = converted

	if error_code != -1:
		print("Restarting speech recognition due to error.")
		if Engine.has_singleton("SpeechToText"):
			var STT = Engine.get_singleton("SpeechToText")
			STT.listen()
	else:
		print("Speech recognition failed with unknown error.")
		_on_speech_result(false)
