# enemy.gd

class_name Enemy
extends CharacterBody2D

signal direction_changed(new_direction: Vector2)
signal enemy_damaged(hurt_box: HurtBox)
signal enemy_destroyed(hurt_box: HurtBox)
## Boss only: a non-final phase was passed and the next bar is up. phase is 1-based.
signal boss_phase_changed(phase: int, phases: int)

const DIR_4 = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
## Kinds without a Chase (the Slime King) get one at this base speed; the
## horde's stage speed multiplier is applied on top after add_child.
const BOSS_SLIME_CHASE_SPEED := 34.0
## A boss stands still this long after it appears (its entrance).
const BOSS_ENTRANCE_SEC := 1.0
## Chase distance bands (hold, orbit, charge range) were tuned for 1x bodies;
## a 2x boss hugs the player unless they grow too. Less than BOSS_SCALE so
## the lunges (fixed speed x time) still reach.
const BOSS_REACH_SCALE := 1.5

@export var hp: int = 3
@export var move_speed: float = 30.0
@export var bounce_delay: float = 0.3  # Pause before bouncing

## When true, physics uses [member state_velocity] instead of
## direction * move_speed. Chase states with non-cardinal movement
## (orbit, retreat, charge) write state_velocity every tick. Default off
## keeps Goblin/Slime/Beetle movement exactly as before.
@export var uses_state_velocity: bool = false
## Random 1-in-400 chaos pause mid-movement. Disable for enemies whose states
## own their movement timing (a charge must not freeze mid-run).
@export var chaos_pauses_enabled: bool = true
## Slide collisions trigger the random-direction bounce. Disable for enemies
## whose states handle wall contact themselves (e.g. charge -> stagger).
@export var slide_bounce_enabled: bool = true

## Desired velocity written by state scripts; consumed by physics only when
## uses_state_velocity is true.
var state_velocity: Vector2 = Vector2.ZERO

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
## Set by EnemyStateDestroy. While dying, physics only carries the state's
## knockback: walking or bouncing would swap the one-shot destroy animation
## for a looping walk, so animation_finished (and queue_free) never comes.
var dying: bool = false
var player: Player
var invulnerable: bool = false
var practice_dummy: bool = false
var _tts_said_on_spawn: bool = false
var _tts_said_on_damage: bool = false

## Boss stages (HordeCurve.boss_for_stage). 0 phases = a normal enemy. Each
## phase is one bar of max_hp ending in a speech challenge; only the last
## pass emits enemy_destroyed.
var boss_phases: int = 0
var boss_phase: int = 0
var boss_name: String = ""
var _boss_sheet: String = ""
var _boss_tune: Dictionary = {}
var _boss_adds: int = 0
var _boss_ranged: Dictionary = {}
## Bosses: the body's room around props when pathing, and how often the path
## is recomputed while the straight line to the player is blocked.
const BOSS_CLEARANCE := 16.0
## Ordinary enemies' body half-width (capsule radius 5-8 px) for wall paths.
const ENEMY_CLEARANCE := 8.0
const REPATH_MSEC := 250
const WAYPOINT_REACHED := 8.0
var _path: PackedVector2Array = PackedVector2Array()
var _path_msec: int = -REPATH_MSEC
## Set by BossRangedAttack during its wind-up: the boss stands still.
var attack_hold: bool = false
## Split children only: a sheet to wear instead of the base art (same frame
## layout), and whether to chase the player for good. Set before add_child.
var minion_sheet: String = ""
var minion_chase: bool = false

var challenge_hurt_box: HurtBox  # Store the hurt_box during the speech challenge
var _last_partial_match: String = ""
## Speech challenge: failed attempts allowed before the enemy is restored to full HP.
const MAX_CHALLENGE_TRIES := 3
var challenge_tries_left: int = 0
var max_hp: int = 0
var _last_web_score: float = -1.0
var _attempt_in_flight: bool = false
## Non-web STT errors in a row. Android restarts listen() on every recoverable
## error with the typed box hidden; past this many, offer typing so a device
## that can never recognise (e.g. offline) cannot trap the paused challenge.
const STT_ERRORS_BEFORE_TYPED_FALLBACK := 3
var _stt_error_streak: int = 0

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $Sprite2D
@onready var hit_box: HitBox = $HitBox
@onready var state_machine: EnemyStateMachine = $EnemyStateMachine
@onready var player_hud: PlayerHudUI = PlayerHud  # Reference to Player HUD
var health_bar: EnemyHealthBar

func _ready() -> void:
	state_machine.Initialize(self)
	add_to_group("enemy")
	player = PlayerManager.player
	hit_box.damaged.connect(_take_damage)
	max_hp = hp
	health_bar = EnemyHealthBar.new()
	health_bar.position = Vector2(-20, -32)
	health_bar.z_index = 10
	# Constant on-screen size even for scaled enemies (e.g. split children).
	health_bar.scale = Vector2.ONE / maxf(scale.x, 0.0001)
	add_child(health_bar)
	health_bar.setup(max_hp)
	if is_boss():
		health_bar.set_phases(boss_phases, boss_phases)
		_attach_boss_art()
		_make_relentless()
	elif minion_sheet != "":
		_wear_minion_sheet()

# Start facing a random direction
	var directions = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	direction = directions[randi() % directions.size()]
	set_direction(direction)

# Brief TTS on spawn: speak the enemy type only (slime / goblin / beetle),
	# never the raw node name (which can be Slime2, @CharacterBody2D@…, etc.).
	var tts = TTSManager
	if tts and tts.is_available():
		var announce := _spawn_announce_name()
		if not announce.is_empty():
			_tts_said_on_spawn = true
			tts.speak(announce)

func _process(_delta): pass

func _physics_process(_delta):
	if practice_dummy:
		velocity = Vector2.ZERO
		return
	if dying:
		move_and_slide()
		return
	if attack_hold:
		velocity = Vector2.ZERO
		return
	if is_bouncing:
		return

	# Optional chaos pause mid-movement
	if chaos_pauses_enabled and randi() % 400 == 0:
		is_bouncing = true
		velocity = Vector2.ZERO
		await get_tree().create_timer(0.5).timeout
		is_bouncing = false
		return

	velocity = state_velocity if uses_state_velocity else direction * move_speed
	move_and_slide()

	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		if collision:
			# A chase or search steers around walls by path; a random bounce
			# would throw it off course and leave it pinned on the wall.
			if slide_bounce_enabled and not _hunting():
				_handle_bounce()
			break

func _hunting() -> bool:
	var st := state_machine.current_state if state_machine else null
	return st is EnemyStateChase or st is EnemyStateSearch


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
		child.minion_sheet = minion_sheet
		child.minion_chase = minion_chase
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
		child.reset_physics_interpolation()
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
	if is_boss():
		return pursuit_target(player_pos)
	if split_orbit_index < 0 or split_orbit_count <= 0:
		return pursuit_target(player_pos)
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
	var chase: Node = get_node_or_null("EnemyStateMachine/Chase")
	if chase == null and minion_chase:
		chase = _ensure_chase(chase_speed)
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


func _wear_minion_sheet() -> void:
	if not ResourceLoader.exists(minion_sheet):
		print("⚠️ Minion sheet missing (%s), keeping the base art" % minion_sheet)
		return
	sprite.texture = load(minion_sheet)


## Kinds without a Chase state (slimes) get one built here: no vision area and
## no exit, so the minion keeps after the player; a stun or idle returns to it.
## An existing Chase is returned as is (rewired the same way).
func _ensure_chase(chase_speed: float) -> EnemyStateChase:
	var existing := get_node_or_null("EnemyStateMachine/Chase") as EnemyStateChase
	if existing:
		_route_states_to(existing)
		return existing
	var chase := EnemyStateChase.new()
	chase.name = "Chase"
	chase.anim_name = "walk"
	chase.chase_speed = chase_speed
	chase.state_aggro_duration = 2.5
	state_machine.add_child(chase)
	chase.enemy = self
	chase.state_machine = state_machine
	state_machine.states.append(chase)
	chase.init()
	_route_states_to(chase)
	return chase


## The horde Search state (built once, on first loss of sight).
func _ensure_search() -> EnemyStateSearch:
	var existing := get_node_or_null("EnemyStateMachine/Search") as EnemyStateSearch
	if existing:
		return existing
	var search := EnemyStateSearch.new()
	search.name = "Search"
	state_machine.add_child(search)
	search.enemy = self
	search.state_machine = state_machine
	state_machine.states.append(search)
	search.init()
	return search


func _route_states_to(chase: EnemyStateChase) -> void:
	for state in state_machine.states:
		if state is EnemyStateStun:
			state.next_state = chase
		elif state is EnemyStateIdle:
			state.after_idle_state = chase
		elif state is EnemyStateWander:
			state.next_state = chase


## Bosses hunt for good: always in Chase (a stun returns to it), no random
## pauses or wall bounces, and a ranged attack at EnemyStateMachine/Ranged.
func _make_relentless() -> void:
	chaos_pauses_enabled = false
	slide_bounce_enabled = false
	var chase := _ensure_chase(BOSS_SLIME_CHASE_SPEED)
	chase.relentless = true
	chase.scale_reach(BOSS_REACH_SCALE)
	state_machine.change_state(chase)
	# A relentless boss no longer uses its cone, and at 2x it tints half the screen.
	var vision := get_node_or_null("VisionArea") as VisionArea
	if vision:
		vision.hide_cone()
	_boss_entrance()
	if not _boss_ranged.is_empty():
		var ranged := BossRangedAttack.new()
		ranged.name = "Ranged"
		ranged.configure(_boss_ranged)
		state_machine.add_child(ranged)


func _boss_entrance() -> void:
	attack_hold = true
	await get_tree().create_timer(BOSS_ENTRANCE_SEC, false).timeout
	attack_hold = false


## The arena the boss paths in, or null (test scenes, non-horde levels).
func horde_arena() -> HordeArena:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("horde_arena") as HordeArena


## Straight at the target when the line is clear; otherwise toward the next
## reachable point of a grid path around walls and props, at the target's real
## distance so chase bands (hold, orbit) still read the true range.
func pursuit_target(player_pos: Vector2) -> Vector2:
	var arena := horde_arena()
	var clearance := BOSS_CLEARANCE if is_boss() else ENEMY_CLEARANCE
	if arena == null or arena.line_clear(global_position, player_pos, clearance):
		_path.clear()
		return player_pos
	var now := Time.get_ticks_msec()
	if _path.is_empty() or now - _path_msec >= REPATH_MSEC:
		_path = arena.boss_path(global_position, player_pos, clearance)
		_path_msec = now
	while _path.size() > 1 and global_position.distance_to(_path[0]) <= WAYPOINT_REACHED:
		_path.remove_at(0)
	if _path.is_empty():
		return player_pos
	# Skip ahead to the farthest waypoint already in a clear straight line.
	var waypoint := _path[0]
	for i in range(1, mini(_path.size(), 8)):
		if not arena.line_clear(global_position, _path[i], clearance):
			break
		waypoint = _path[i]
	return global_position + global_position.direction_to(waypoint) * global_position.distance_to(player_pos)


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


## Turns this enemy into a boss. Call before add_child: _ready copies hp into
## max_hp, which is one phase bar.
func make_boss(profile: Dictionary, phase_hp: int) -> void:
	boss_phases = HordeCurve.BOSS_PHASES
	boss_phase = 0
	hp = maxi(phase_hp, 1)
	boss_name = str(profile.get("name", "Boss"))
	_boss_sheet = str(profile.get("sheet", ""))
	_boss_tune = profile.get("tune", {})
	_boss_adds = int(profile.get("adds", 0))
	_boss_ranged = profile.get("ranged", {})
	minion_sheet = str(profile.get("add_sheet", ""))
	minion_chase = bool(profile.get("add_chase", false))
	scale = Vector2.ONE * HordeCurve.BOSS_SCALE
	splits_on_destroy = false
	# Adds land at net scale 1.0 (2.0 x 0.5), on the same pixel grid as the rest.
	split_scale = 1.0 / HordeCurve.BOSS_SCALE
	split_hp = maxi(1, hp / 4)
	name = boss_name.replace(" ", "")


## The boss is a 2x enemy (hitboxes and animations scale with it), but its art
## is a sheet drawn at 2x resolution shown at 0.5, so one art pixel is one
## screen pixel like the player. It rides on the base sprite as a child: the
## base sprite's flip, position keys and modulate flashes all carry over, and
## only the base sprite's own pixels are hidden.
func _attach_boss_art() -> void:
	if _boss_sheet == "" or not ResourceLoader.exists(_boss_sheet):
		print("⚠️ Boss %s: sheet missing (%s), showing the base sprite at 2x" % [boss_name, _boss_sheet])
		return
	var art := Sprite2D.new()
	art.name = "BossSprite"
	art.texture = load(_boss_sheet)
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art.hframes = sprite.hframes
	art.vframes = sprite.vframes
	art.frame = sprite.frame
	art.centered = sprite.centered
	art.offset = sprite.offset * scale.x
	art.scale = Vector2.ONE / scale.x
	sprite.add_child(art)
	sprite.self_modulate.a = 0.0
	sprite.frame_changed.connect(func(): art.frame = sprite.frame)


func is_boss() -> bool:
	return boss_phases > 0


func _advance_boss_phase() -> void:
	boss_phase += 1
	hp = max_hp
	if health_bar:
		health_bar.set_phases(boss_phases - boss_phase, boss_phases)
		health_bar.update_bar(hp)
	var sfx := get_node_or_null("/root/Sfx")
	if sfx:
		sfx.play(&"phase")
	if player_hud:
		player_hud.show_notice("%s hit! Phase %d/%d" % [boss_name, boss_phase + 1, boss_phases])
	var ranged := get_node_or_null("EnemyStateMachine/Ranged") as BossRangedAttack
	if ranged:
		ranged.reset()
	for key in _boss_tune:
		var parts := str(key).split("/")
		if parts.size() != 2:
			continue
		var state := get_node_or_null("EnemyStateMachine/" + parts[0])
		if state and state.get(parts[1]) != null:
			state.set(parts[1], float(state.get(parts[1])) * float(_boss_tune[key]))
	if _boss_adds > 0:
		splits_on_destroy = true
		split_count = _boss_adds
		spawn_split_children()
	boss_phase_changed.emit(boss_phase + 1, boss_phases)
	print("✅ Boss %s: phase %d/%d" % [boss_name, boss_phase + 1, boss_phases])
	# Process-always grace (like split children): a swing landing as the game
	# resumes must not chain straight into the next phase's challenge.
	invulnerable = true
	await get_tree().create_timer(HordeCurve.BOSS_PHASE_GRACE, true, false, true).timeout
	invulnerable = false


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
		if health_bar:
			health_bar.update_bar(hp)
		return
	hp -= dealt
	DamageNumber.spawn(global_position + Vector2(randf_range(-8.0, 8.0), -22.0), dealt, crit, get_parent())
	if health_bar:
		health_bar.update_bar(hp)
	if hp > 0:
		enemy_damaged.emit(hurt_box)
	else:
		print("Enemy defeated. Initiating speech challenge...")

		if word_tracker:
			word_tracker.speech_challenge_active = true
			var challenge: String
			var stage := _horde_challenge_stage(word_tracker)
			if stage > 0 and is_boss():
				challenge = word_tracker.get_speech_challenge_for_stage(stage, HordeCurve.boss_phase_band(boss_phase))
				print("✅ Boss phase ", boss_phase + 1, " challenge:", challenge)
			elif stage > 0:
				challenge = word_tracker.get_speech_challenge_for_stage(stage)
				print("✅ Horde stage ", stage, " challenge:", challenge)
			else:
				challenge = word_tracker.get_random_speech_challenge()
			_start_speech_challenge(challenge, hurt_box)
		else:
			print("[ERROR] WordTracker not found! Using fallback sentence.")
			_start_speech_challenge("No challenge available.", hurt_box)

# Start the speech challenge
func _start_speech_challenge(target_sentence: String, hurt_box: HurtBox) -> void:
	challenge_hurt_box = hurt_box  # Store hurt_box for later use
	_last_partial_match = ""
	_stt_error_streak = 0
	challenge_tries_left = MAX_CHALLENGE_TRIES
	if player_hud:
		player_hud.set_challenge_tries(challenge_tries_left)

	get_tree().paused = true  # Pause the game

	if player_hud:
		var title := ""
		if is_boss():
			title = "%s - phase %d/%d" % [boss_name, boss_phase + 1, boss_phases]
		player_hud.show_speech_challenge(target_sentence, title)

	_connect_stt_signals()
	# Every platform: the mic-toggle controls must not run challenge
	# transcripts as voice commands or restart the mic under the challenge.
	_begin_challenge_mic()
	var stt = _stt_manager()
	if _is_web():
		_show_typed_fallback()
		_connect_speak_button()
		if stt != null and stt.is_speech_available():
			if stt.has_method("begin_challenge_listen"):
				stt.begin_challenge_listen()
			else:
				stt.listen()
			# Record a mic clip for the phoneme forgiveness pass (scored only
			# if the transcript misses).
			_begin_web_scorer_capture()
		return
	if stt != null and stt.is_speech_available():
		stt.listen()
		if player_hud and player_hud.typed_test_input:
			_show_typed_fallback()
	else:
		print("STT unavailable. Showing typed fallback.")
		_show_typed_fallback()

func _on_listening_completed(result: String) -> void:
	# The scoring await below yields while STT signals stay connected; a second
	# final transcript (or partial match) firing mid-await would double-count
	# the attempt. Serialize attempts with this guard.
	if _attempt_in_flight:
		print("⚠️ Speech challenge: transcript ignored — an attempt is already in flight.")
		return
	_attempt_in_flight = true
	await _on_listening_completed_impl(result)
	_attempt_in_flight = false


func _on_listening_completed_impl(result: String) -> void:
	print("Listening completed: ", result)
	_stt_error_streak = 0
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

	var accepted := target_sentence != "" and target_sentence in recognized_text
	if not accepted and PhoneticMatcher.transcript_contains_fuzzy(recognized_text, target_sentence, 0.72):
		accepted = true

	if accepted:
		if target_sentence != "" and target_sentence in recognized_text:
			print("Target phrase detected in speech:", target_sentence)
			word_tracker.add_spoken_word(player_hud.target_sentence)
		_on_speech_result(true, 100)
		return

	print("Target phrase NOT found in speech:", target_sentence)
	# Speech missed the target: this attempt failed. Web scores the captured audio
	# against the target's phonemes; all platforms funnel the result into the try counter.
	var sim := -1.0
	if _is_web():
		await _score_web_attempt(target_sentence)
		sim = _last_web_score
	_register_challenge_attempt(sim)

func _on_speech_result(success: bool, score: int = -1) -> void:
	_end_challenge_io()
	if player_hud:
		player_hud.hide_speech_challenge()
		player_hud.show_feedback(success, score)
		player_hud.set_stt_state(PlayerHudUI.SttState.STT_IDLE)

	if success:
		print("Speech challenge passed! Storing word:", player_hud.target_sentence)
		if is_boss() and boss_phase < boss_phases - 1:
			_advance_boss_phase()
		else:
			var progress := get_node_or_null("/root/ProgressTracker")
			if progress and progress.has_method("record_kill"):
				progress.record_kill(_progress_kill_kind())
			enemy_destroyed.emit(challenge_hurt_box)

		if has_node("/root/WordTracker"):
			var word_tracker = get_node("/root/WordTracker")
			word_tracker.add_spoken_word(player_hud.target_sentence)
		else:
			print("Error: WordTracker singleton not found! Cannot store the word.")
		# EnemyStateDestroy handles queue_free after the destroy animation finishes

		_flash_challenge_success()
		# A short beat before unpausing so the flash and toast actually land —
		# an instant resume makes kills feel like an interruption, not a reward.
		await get_tree().create_timer(0.45, true, false, true).timeout
		_resume_game_after_challenge()

	else:
		await _register_challenge_attempt(score)
func _register_challenge_attempt(sim: float) -> void:
	# Score-based pass: a phoneme score >= the pass threshold (75) means the
	# utterance was good enough. Exact/fuzzy accepts enter here with sim = 100.
	if sim >= 75.0:
		_on_speech_result(true, int(roundi(sim)))
		return
	# Failed attempt → consume a try. The card stays up on every platform until
	# the tries run out. Match rules are unchanged.
	challenge_tries_left -= 1
	print("Speech challenge failed. Tries left: ", challenge_tries_left, "/", MAX_CHALLENGE_TRIES)
	if player_hud:
		player_hud.set_challenge_tries(challenge_tries_left)
		if challenge_tries_left > 0:
			player_hud.show_feedback(false)
	if challenge_tries_left > 0:
		if _is_web():
			_show_typed_fallback()
		var stt = _stt_manager()
		if stt != null and stt.is_speech_available():
			stt.listen()
			if _is_web():
				# Fresh clip for the next attempt's forgiveness pass.
				_begin_web_scorer_capture()
		elif not _is_web():
			_show_typed_fallback()
		return
	_host_challenge_fail()


## Every challenge exit (pass or out of tries) must release the mic and every
## per-challenge connection, or this enemy keeps judging later transcripts —
## including the next enemy's challenge, which it would tear down.
func _end_challenge_io() -> void:
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


func _host_challenge_fail() -> void:
	print("⚠️ Enemy restored to full HP. Speech challenge exhausted all tries (3/3).")
	_end_challenge_io()
	hp = max_hp
	if health_bar:
		health_bar.update_bar(hp)
	challenge_hurt_box = null
	challenge_tries_left = 0
	_last_partial_match = ""
	if player_hud:
		player_hud.set_challenge_tries(0)
		# Tell the player the runback cost — the heal is the punishment, so
		# it must be visible, not just a line in the console.
		player_hud.show_enemy_recovered()
	await _wait_feedback_and_resume()


func _flash_challenge_success() -> void:
	if sprite == null:
		return
	sprite.modulate = Color(2.5, 2.5, 2.5)
	var tween := sprite.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.4)


func _web_scorer():
	if not _is_web():
		return null
	var pm := get_node_or_null("/root/PronunciationManager")
	if pm == null:
		return null
	return pm.get_scorer()


func _begin_web_scorer_capture() -> void:
	# Record a mic clip for the phoneme forgiveness pass. Only starts when the
	# scorer is ready AND phoneme data exists for the target — otherwise the
	# clip could never be scored and we'd hold the mic for nothing.
	var scorer = _web_scorer()
	if scorer == null or not scorer.is_available():
		return
	if player_hud == null:
		return
	var target := player_hud.target_sentence
	if target.strip_edges().is_empty():
		return
	var pm := get_node_or_null("/root/PronunciationManager")
	if pm == null or pm.phonemes_for(target).is_empty():
		return
	if not scorer.is_capturing():
		scorer.begin_capture()


func _abandon_web_scorer_capture() -> void:
	var scorer = _web_scorer()
	if scorer != null and scorer.is_capturing():
		scorer.abandon_capture()


func _score_web_attempt(target_sentence: String) -> void:
	# Web: score the just-finished captured clip against the target's phonemes.
	# Stores the 0-100 score in _last_web_score (-1 when scoring is unavailable,
	# no phoneme data, no capture running, or scoring failed).
	_last_web_score = -1.0
	var pm := get_node_or_null("/root/PronunciationManager")
	if pm == null:
		return
	var scorer = pm.get_scorer()
	if scorer == null or not scorer.is_available():
		return
	var phonemes: String = pm.phonemes_for(target_sentence)
	if phonemes.is_empty():
		return
	# Nothing is recording, so there is no clip to score. Awaiting
	# capture_finished here would park the paused challenge forever.
	if not scorer.is_capturing():
		return
	# Ask the scorer to finish the clip, then bound the wait so a lost JS
	# callback cannot freeze the paused tree.
	var done := {"ok": false}
	var on_done := func(_r: Dictionary) -> void:
		done["ok"] = true
	scorer.end_capture_and_score(phonemes, on_done)
	if not done["ok"]:
		var timer := get_tree().create_timer(6.0, true, false, true)
		while not done["ok"] and timer.time_left > 0.0:
			await get_tree().process_frame
	_last_web_score = float(scorer.last_result.get("score", -1))


func _resume_game_after_challenge() -> void:
	_abandon_web_scorer_capture()
	if player_hud:
		player_hud.hide_speech_challenge()
	get_tree().paused = false
	if has_node("/root/WordTracker"):
		get_node("/root/WordTracker").speech_challenge_active = false
	_end_challenge_mic()


func _wait_feedback_and_resume() -> void:
	if player_hud != null:
		await player_hud.feedback_closed
	else:
		# Must tick while the challenge has the tree paused.
		await get_tree().create_timer(PlayerHudUI.FEEDBACK_DURATION, true).timeout
	_resume_game_after_challenge()

func _on_speech_error(error_code) -> void:
	print("Speech recognition error: ", error_code)

	if error_code is String:
		var converted = int(error_code) if error_code.is_valid_int() else -1
		error_code = converted

	if player_hud:
		player_hud.set_stt_state(PlayerHudUI.SttState.STT_ERROR)

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
		_stt_error_streak += 1
		if _stt_error_streak >= STT_ERRORS_BEFORE_TYPED_FALLBACK:
			print("⚠️ ", _stt_error_streak, " speech errors in a row. Offering typed fallback.")
			if _stt_error_streak == STT_ERRORS_BEFORE_TYPED_FALLBACK:
				var sfx := get_node_or_null("/root/Sfx")
				if sfx:
					sfx.play(&"error")
			_show_typed_fallback()
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


func _spawn_announce_name() -> String:
	## Clean spoken label for spawn TTS. "other" stays silent.
	var kind := _progress_kill_kind()
	match kind:
		"slime", "goblin", "beetle", "orc", "skeleton", "bandit":
			return kind
		_:
			return ""


func _horde_challenge_stage(word_tracker: Node) -> int:
	# Prefer the WordTracker flag set by Endless Horde; fall back to the live
	# scene stage so a missed assign still scales speech with the stage loop.
	if word_tracker != null:
		var flagged := int(word_tracker.get("horde_stage"))
		if flagged > 0:
			return flagged
	var scene := get_tree().current_scene
	if scene == null:
		return 0
	if String(scene.name) != "EndlessHorde":
		return 0
	var stage_val = scene.get("_stage")
	if stage_val == null:
		return 0
	return maxi(int(stage_val), 0)


func _progress_kill_kind() -> String:
	var n := String(name).to_lower()
	if "slime" in n:
		return "slime"
	if "goblin" in n:
		return "goblin"
	if "beetle" in n:
		return "beetle"
	if "orc" in n:
		return "orc"
	if "skeleton" in n:
		return "skeleton"
	if "bandit" in n:
		return "bandit"
	# Split children keep scene name; also check scene file path.
	var path := scene_file_path.to_lower()
	if "slime" in path:
		return "slime"
	if "goblin" in path:
		return "goblin"
	if "beetle" in path:
		return "beetle"
	if "orc" in path:
		return "orc"
	if "skeleton" in path:
		return "skeleton"
	if "bandit" in path:
		return "bandit"
	return "other"


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


func _begin_challenge_mic() -> void:
	for node in get_tree().get_nodes_in_group("touch_controls"):
		if node.has_method("begin_challenge_mic"):
			node.begin_challenge_mic()


func _end_challenge_mic() -> void:
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
		player_hud.set_stt_state(PlayerHudUI.SttState.STT_LISTENING)


func _on_stt_listening_stopped() -> void:
	if player_hud:
		player_hud.set_stt_state(PlayerHudUI.SttState.STT_IDLE)


func _on_partial_transcript(partial: String) -> void:
	if _attempt_in_flight:
		return
	if player_hud:
		player_hud.update_live_transcript(partial)

	if _is_web():
		var word_tracker = get_node_or_null("/root/WordTracker")
		if word_tracker and word_tracker.speech_challenge_active and player_hud:
			var normalized_partial = _normalize_web_text(partial)
			var target = _normalize_web_text(player_hud.target_sentence)
			if PhoneticMatcher.transcript_contains_fuzzy(normalized_partial, target, 0.72):
				if normalized_partial == _last_partial_match:
					_last_partial_match = ""
					_on_speech_result(true, 100)
					return
				_last_partial_match = normalized_partial
			else:
				_last_partial_match = ""


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
