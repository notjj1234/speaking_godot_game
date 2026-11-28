extends Level
## Guided Training: a hands-on, step-gated tutorial in the first horde arena,
## led by the camp Trainer. Each lesson unlocks only when the last one is done,
## and the last one opens the camp tour (TrainingState.tour_mode). The scene
## root is named "Training", which makes it a non-horde level: player deaths
## refill HP ("Practice — you can't die here!").

signal marker_reached
signal knocked_down
signal pickups_collected
signal wave_cleared
signal voice_done

const ARENA := preload("res://levels/endless_horde/arenas/arena_01.tscn")
const SLIME := preload("res://enemies/slime/slime.tscn")
const GOBLIN := preload("res://enemies/goblin/goblin.tscn")
const PICKUP := preload("res://items/item_pickup/item_pickup.tscn")
const GEM := preload("res://items/gem.tres")

const LESSON_IDS: Array[StringName] = [&"why", &"move", &"attack", &"speak", &"fallbacks",
	&"out_of_tries", &"voice", &"gems", &"wave", &"boss", &"hud", &"camp"]

const WALLS_LAYER := 16
const BOUNDS_INSET := 64.0
const PICKUP_PULL_SPEED := 280.0
const PICKUP_COLLECT_DISTANCE := 18.0
const PULL_AFTER_SEC := 3.0
const WAVE_INTERVAL := 1.25
const BOSS_PHASE_HP := 2
const NO_STT_SKIP_SEC := 2.5
const MIC_DENIED := -1
## Within this distance of the slime, touch players get a ring on the sword button.
const ATTACK_HINT_RANGE := 90.0

var coach: TrainingCoach
var banner: CoachBanner
var pointer: GuidePointer
var arena: HordeArena
## The patch the move lesson asks you to reach.
var marker: Node2D
## The enemy the current lesson is about (a target, or the mini-boss).
var current_target: Enemy

var _grass: TileMapLayer
var _patch_restore: Array[Dictionary] = []
var _watch_knockdown := false
var _watch_pickups := false
var _pull_timer := 0.0
var _watch_wave := false
var _wave_left := 0
var _voice_links: Array[Node] = []
var _voice_token := 0
## If no voice command arrives by then, the voice lesson becomes tap-to-continue.
var voice_tap_skip_sec := 15.0

@onready var _enemies: Node2D = $TrainingEnemies
@onready var _decor_layer: Node2D = $DecorLayer


func _ready() -> void:
	super()
	PlayerManager.revive_for_horde()
	await _load_arena()
	_set_word_tracker_stage(0)
	banner = CoachBanner.new()
	add_child(banner)
	pointer = GuidePointer.new()
	add_child(pointer)
	coach = TrainingCoach.new()
	add_child(coach)
	coach.pointer = pointer
	coach.lessons = _build_lessons()
	# Signals fire while the tree is paused (speech challenges), _process doesn't.
	get_tree().process_frame.connect(_tick)
	coach.start(banner)
	print("✅ Training: started")


func music_track() -> StringName:
	return &"tutorial"


func _free_level() -> void:
	if get_tree().process_frame.is_connected(_tick):
		get_tree().process_frame.disconnect(_tick)
	if banner:
		banner.clear()
	if pointer:
		pointer.clear()
	_drop_voice_links()
	_set_word_tracker_stage(0)
	var music := get_node_or_null("/root/MusicManager")
	if music:
		music.set_intensity(1)
	super()


func _exit_tree() -> void:
	if get_tree() and get_tree().process_frame.is_connected(_tick):
		get_tree().process_frame.disconnect(_tick)


# --- arena ------------------------------------------------------------------

func _load_arena() -> void:
	arena = ARENA.instantiate() as HordeArena
	arena.name = "Arena"
	add_child(arena)
	move_child(arena, 1)
	await get_tree().process_frame
	_grass = arena.ground
	var decor := arena.get_node_or_null("Decor")
	if decor:
		for sprite in decor.get_children():
			sprite.reparent(_decor_layer)
	var backdrop := get_node_or_null("GrassBackground") as CanvasItem
	if backdrop:
		backdrop.modulate = arena.ground_tint
	HordeArenaHelpers.add_top_barrier(self, _grass, WALLS_LAYER)
	PlayerManager.set_player_position(arena.spawn_point())


func _ground_point(pos: Vector2) -> Vector2:
	var p := HordeArenaHelpers.clamp_to_grass(_grass, pos, BOUNDS_INSET)
	if arena and arena.is_blocked(p):
		p = arena.nearest_open(p)
	return p


func _player_position() -> Vector2:
	if PlayerManager.player:
		return PlayerManager.player.global_position
	return global_position


# --- enemies ----------------------------------------------------------------

## A target that stands still and can't hurt you, `offset` from the player.
func spawn_target(offset: Vector2, hp: int, scene: PackedScene = SLIME) -> Enemy:
	var enemy: Enemy = scene.instantiate()
	enemy.hp = hp
	enemy.splits_on_destroy = false
	_enemies.add_child(enemy)
	enemy.global_position = _ground_point(_player_position() + offset)
	enemy.reset_physics_interpolation()
	enemy.make_training_target()
	current_target = enemy
	return enemy


## A real enemy at stage-1 strength, eased the way a first run is.
func _spawn_wave_enemy(scene: PackedScene, index: int, count: int) -> Enemy:
	var enemy: Enemy = scene.instantiate()
	var easing := HordeCurve.first_run_ease(1, 0)
	enemy.hp = maxi(1, roundi(float(enemy.hp) * easing))
	enemy.splits_on_destroy = false
	for hb: HurtBox in enemy.find_children("*", "HurtBox"):
		hb.damage = maxi(1, roundi(float(hb.damage) * easing))
	var angle := TAU * float(index) / float(maxi(count, 1))
	_enemies.add_child(enemy)
	enemy.global_position = _ground_point(_player_position() + Vector2.RIGHT.rotated(angle) * 120.0)
	enemy.reset_physics_interpolation()
	return enemy


func enemy_count() -> int:
	var alive := 0
	for child in _enemies.get_children():
		if is_instance_valid(child) and not child.is_queued_for_deletion() and child is Enemy:
			alive += 1
	return alive


func _pickups() -> Array[ItemPickup]:
	var found: Array[ItemPickup] = []
	for child in _enemies.get_children():
		if child is ItemPickup and is_instance_valid(child) and not child.is_queued_for_deletion():
			found.append(child)
	return found


# --- per-frame watchers (run while paused too) ------------------------------

func _tick() -> void:
	if not is_inside_tree():
		return
	var challenge := _speech_challenge_active()
	if banner:
		# One prompt at a time: the speech card or a dialog owns the screen.
		banner.set_suppressed(challenge or DialogSystem.is_open)
		if pointer:
			banner.set_avoid(pointer.world_target_rect())
	if _watch_knockdown and challenge:
		_watch_knockdown = false
		knocked_down.emit()
	if get_tree().paused or challenge:
		return
	var delta := get_process_delta_time()
	if _watch_pickups:
		_tick_pickups(delta)
	if _watch_wave and _wave_left <= 0 and enemy_count() == 0:
		if _pickups().is_empty():
			_watch_wave = false
			banner.say("Stage clear!", false, "Stage clear!")
			wave_cleared.emit()
		else:
			_pull_pickups(delta)


func _tick_pickups(delta: float) -> void:
	if enemy_count() > 0:
		return
	var pickups := _pickups()
	if pickups.is_empty():
		_watch_pickups = false
		pickups_collected.emit()
		return
	_pull_timer += delta
	if _pull_timer >= PULL_AFTER_SEC:
		_pull_pickups(delta)


func _pull_pickups(delta: float) -> void:
	var player := PlayerManager.player
	if player == null:
		return
	var dest := player.global_position
	for drop in _pickups():
		if drop.has_meta("training_collecting"):
			continue
		drop.velocity = Vector2.ZERO
		drop.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		drop.global_position = drop.global_position.move_toward(dest, PICKUP_PULL_SPEED * delta)
		if drop.global_position.distance_to(dest) <= PICKUP_COLLECT_DISTANCE:
			drop.set_meta("training_collecting", true)
			if drop.item_data and PlayerManager.INVENTORY_DATA \
					and PlayerManager.INVENTORY_DATA.add_item(drop.item_data):
				drop.item_picked_up()
			else:
				drop.queue_free()


# --- guide arrows -------------------------------------------------------------

## What the current lesson's arrow / ring points at (for tests).
func point_target():
	return coach.current_point_target() if coach else null


func _point_marker():
	return marker if is_instance_valid(marker) else null


## The slime; on touch screens, the sword button once you're close enough.
func _point_attack():
	if not is_instance_valid(current_target):
		return null
	var player := PlayerManager.player
	if MobileSafeLayout.wants_touch_ui() and player \
			and player.global_position.distance_to(current_target.global_position) < ATTACK_HINT_RANGE:
		var controls := get_tree().get_first_node_in_group("touch_controls")
		if controls and controls.get("attack_button"):
			return controls.attack_button
	return current_target


## The slime; once the word card is up, its word tiles or Speak button.
func _point_speak():
	if PlayerHud.challenge_panel.visible:
		if PlayerHud.word_tiles_row and PlayerHud.word_tiles_row.is_visible_in_tree():
			return PlayerHud.word_tiles_row
		if PlayerHud.challenge_speak_button.is_visible_in_tree():
			return PlayerHud.challenge_speak_button
		return null
	return current_target if is_instance_valid(current_target) else null


func _point_mic():
	var controls := get_tree().get_first_node_in_group("touch_controls")
	if controls == null:
		return null
	var mic = controls.get("mic_button")
	return mic if mic is CanvasItem and (mic as CanvasItem).is_visible_in_tree() else null


func _point_gems():
	var gems := _pickups()
	if gems.is_empty():
		return current_target if is_instance_valid(current_target) else null
	return _nearest(gems)


func _point_wave():
	var alive: Array = []
	for child in _enemies.get_children():
		if child is Enemy and is_instance_valid(child) and not child.is_queued_for_deletion():
			alive.append(child)
	return _nearest(alive)


func _point_boss():
	return current_target if is_instance_valid(current_target) else null


func _point_hearts():
	return PlayerHud.get_node_or_null("Control/HFlowContainer")


func _nearest(nodes: Array) -> Node2D:
	var from := _player_position()
	var best: Node2D = null
	for n in nodes:
		if best == null or (n as Node2D).global_position.distance_to(from) < best.global_position.distance_to(from):
			best = n
	return best


# --- lessons ------------------------------------------------------------------

func _build_lessons() -> Array[Dictionary]:
	return [
		{"id": &"why", "goal": "Read on", "tap": true,
			"text": "Welcome, recruit! Here you beat monsters by speaking. Every word you get right is pronunciation practice."},
		{"id": &"move", "point": _point_marker, "goal": "Reach the patch", "begin": _begin_move,
			"text": "Walk to the glowing patch. (WASD)",
			"touch_text": "Use the stick to walk to the glowing patch."},
		{"id": &"attack", "point": _point_attack, "goal": "Hit the slime", "begin": _begin_attack,
			"text": "Hit the slime until it drops. (Press ,)",
			"touch_text": "Tap the sword button to hit the slime until it drops."},
		{"id": &"speak", "point": _point_speak, "goal": "Say the words", "begin": _begin_speak,
			"text": "Now say the words on the card out loud!" + (" You'll get a pronunciation score too." if OS.has_feature("web") else "")},
		{"id": &"fallbacks", "point": _point_speak, "goal": "Beat it (speak or tap)", "begin": _begin_fallbacks,
			"text": "Mic can't hear you? Tap Speak to try again, or tap the right words on the card. Beat this one!"},
		{"id": &"out_of_tries", "goal": "Read on", "tap": true,
			"text": "Run out of tries and the enemy heals to full. No problem - just knock it down again!"},
		{"id": &"voice", "point": _point_mic, "goal": "Say \"move left\"", "begin": begin_voice,
			"text": "You can also move by voice. Turn on the mic and say 'move left' or 'attack'."},
		{"id": &"gems", "point": _point_gems, "goal": "Grab the gems", "begin": _begin_gems,
			"text": "Beaten enemies drop gems. Beat this slime and walk over them. At camp, gems become points."},
		{"id": &"wave", "point": _point_wave, "goal": "Clear the wave", "begin": _begin_wave,
			"text": "Here comes a real wave! Clear them all."},
		{"id": &"boss", "point": _point_boss, "goal": "Beat the Slime King", "begin": _begin_boss,
			"text": "A boss! Bosses have 3 health bars, and each one ends with a word challenge."},
		{"id": &"hud", "point": _point_hearts, "goal": "Read on", "tap": true,
			"text": "Top middle: your hearts. Press Esc to pause - save, settings and your word journal.",
			"touch_text": "Top middle: your hearts. Tap PAUSE to save, change settings or read your word journal."},
		{"id": &"camp", "goal": "Off to camp", "begin": go_to_camp_tour,
			"text": "Well fought! Now let me show you our camp."},
	]


func _begin_move() -> Signal:
	var spot := _ground_point(_player_position() + Vector2(0, 120))
	var center := HordeArenaHelpers.paint_patch(_grass, spot, _patch_restore)
	marker = Node2D.new()
	marker.name = "MoveMarker"
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(56, 56)
	shape_node.shape = shape
	area.add_child(shape_node)
	marker.add_child(area)
	add_child(marker)
	marker.global_position = center
	HordeArenaHelpers.add_glow(marker, center, Vector2(64, 64))
	area.body_entered.connect(_on_marker_body)
	return marker_reached


func _on_marker_body(body: Node) -> void:
	if body != PlayerManager.player or marker == null:
		return
	HordeArenaHelpers.restore_patch(_grass, _patch_restore)
	marker.queue_free()
	marker_reached.emit()


func _begin_attack() -> Signal:
	spawn_target(Vector2(72, 0), 3)
	_watch_knockdown = true
	return knocked_down


func _begin_speak() -> Signal:
	if not is_instance_valid(current_target):
		return _already_done()
	return current_target.enemy_destroyed


func _begin_fallbacks() -> Signal:
	var target := spawn_target(Vector2(-72, 0), 2)
	return target.enemy_destroyed


## Voice commands. Without a working mic (e.g. Windows) it says so and moves on.
func begin_voice() -> Signal:
	_drop_voice_links()
	_voice_token += 1
	var stt := get_node_or_null("/root/STTManager")
	if stt == null or not stt.is_speech_available():
		_skip_voice("Voice commands need a working mic. Skipping this one for now.")
		return voice_done
	for node in get_tree().get_nodes_in_group("touch_controls"):
		if node.has_signal("voice_command_executed"):
			node.voice_command_executed.connect(_on_voice_command)
			_voice_links.append(node)
	# The speech API can exist with the mic still refused (web, Android).
	stt.error.connect(_on_voice_stt_error)
	_offer_voice_tap_later(_voice_token)
	return voice_done


func _skip_voice(note: String) -> void:
	_drop_voice_links()
	banner.say(note, false, "Skipping voice")
	var token := _voice_token
	await get_tree().create_timer(NO_STT_SKIP_SEC).timeout
	if is_instance_valid(self) and is_inside_tree() and token == _voice_token:
		voice_done.emit()


func _on_voice_stt_error(code) -> void:
	if int(code) == MIC_DENIED:
		_skip_voice("The mic is blocked, so voice commands can't work. Skipping this one for now.")


## Mic silently not working? Never trap the player: offer tap-to-continue.
func _offer_voice_tap_later(token: int) -> void:
	await get_tree().create_timer(voice_tap_skip_sec).timeout
	if not is_instance_valid(self) or not is_inside_tree() or token != _voice_token or _voice_links.is_empty():
		return
	banner.say("No command heard yet. You can try voice commands later.", true, "Read on")
	banner.continue_pressed.connect(_on_voice_tap_skip.bind(token), CONNECT_ONE_SHOT)


func _on_voice_tap_skip(token: int) -> void:
	if token != _voice_token:
		return
	_drop_voice_links()
	voice_done.emit()


func _on_voice_command(_command: String) -> void:
	_drop_voice_links()
	voice_done.emit()


func _drop_voice_links() -> void:
	for node in _voice_links:
		if is_instance_valid(node) and node.voice_command_executed.is_connected(_on_voice_command):
			node.voice_command_executed.disconnect(_on_voice_command)
	_voice_links.clear()
	var stt := get_node_or_null("/root/STTManager")
	if stt and stt.error.is_connected(_on_voice_stt_error):
		stt.error.disconnect(_on_voice_stt_error)


func _begin_gems() -> Signal:
	var target := spawn_target(Vector2(72, 0), 1)
	target.enemy_destroyed.connect(_ensure_gem_drop.bind(target.global_position), CONNECT_ONE_SHOT)
	return pickups_collected


## Drops are random; the lesson needs at least one gem on the ground.
func _ensure_gem_drop(_hurt_box: HurtBox, at: Vector2) -> void:
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	if _pickups().is_empty():
		var gem: ItemPickup = PICKUP.instantiate()
		gem.item_data = GEM
		_enemies.add_child(gem)
		gem.global_position = at
	_pull_timer = 0.0
	_watch_pickups = true


func _begin_wave() -> Signal:
	_run_wave()
	return wave_cleared


func _run_wave() -> void:
	var scenes: Array[PackedScene] = [SLIME, SLIME, SLIME, GOBLIN]
	_wave_left = scenes.size()
	_watch_wave = true
	for i in scenes.size():
		if not is_inside_tree() or not _watch_wave:
			return
		_spawn_wave_enemy(scenes[i], i, scenes.size())
		_wave_left -= 1
		# Pausable: no spawns while a speech challenge (or the pause menu) is up.
		await get_tree().create_timer(WAVE_INTERVAL, false).timeout
		if not is_instance_valid(self):
			return


func _begin_boss() -> Signal:
	_watch_wave = false
	var boss: Enemy = SLIME.instantiate()
	boss.make_boss(HordeCurve.BOSSES[0], BOSS_PHASE_HP)
	_enemies.add_child(boss)
	# To the side, not straight up where the Trainer's bubble sits.
	boss.global_position = _ground_point(_player_position() + Vector2(150, -40))
	boss.reset_physics_interpolation()
	for hb: HurtBox in boss.find_children("*", "HurtBox"):
		hb.damage = mini(hb.damage, HordeCurve.BOSS_MAX_HIT)
	boss.boss_phase_changed.connect(_on_boss_phase)
	current_target = boss
	var music := get_node_or_null("/root/MusicManager")
	if music:
		music.play_track(&"boss_slime")
	boss.enemy_destroyed.connect(_on_boss_beaten, CONNECT_ONE_SHOT)
	return boss.enemy_destroyed


func _on_boss_phase(phase: int, phases: int) -> void:
	var music := get_node_or_null("/root/MusicManager")
	if music:
		music.set_intensity(phase)
	if banner:
		banner.say("Slime King %d/%d - knock it down and speak again!" % [phase, phases], false,
			"Slime King %d/%d" % [phase, phases])


func _on_boss_beaten(_hurt_box: HurtBox) -> void:
	var music := get_node_or_null("/root/MusicManager")
	if music:
		music.set_intensity(1)
		music.play_track(&"tutorial")


func go_to_camp_tour() -> void:
	TrainingState.tour_mode = true
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(TrainingState.CAMP_PATH, "", Vector2.ZERO)


## A signal that fires next frame, for a lesson whose condition already holds.
func _already_done() -> Signal:
	(func(): marker_reached.emit()).call_deferred()
	return marker_reached


func _speech_challenge_active() -> bool:
	var word_tracker := get_node_or_null("/root/WordTracker")
	return word_tracker != null and bool(word_tracker.speech_challenge_active)


func _set_word_tracker_stage(stage: int) -> void:
	var word_tracker := get_node_or_null("/root/WordTracker")
	if word_tracker:
		word_tracker.horde_stage = stage
