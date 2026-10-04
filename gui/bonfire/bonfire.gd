extends CanvasLayer

const HORDE_PATH := "res://levels/endless_horde/endless_horde.tscn"
const TITLE_PATH := "res://levels/title_screen/title_screen.tscn"

var _busy := false
var _navigating := false
var _master_was_muted := false

@onready var vitality_label: Label = %VitalityLabel
@onready var might_label: Label = %MightLabel
@onready var haste_label: Label = %HasteLabel
@onready var crit_label: Label = %CritLabel
@onready var points_label: Label = %PointsLabel
@onready var feedback: Label = %Feedback
@onready var vitality_button: Button = %VitalityButton
@onready var might_button: Button = %MightButton
@onready var haste_button: Button = %HasteButton
@onready var crit_button: Button = %CritButton
@onready var equip_button: Button = %EquipButton
@onready var continue_button: Button = %ContinueButton
@onready var title_button: Button = %TitleButton
@onready var avatar_weapon: Sprite2D = %AvatarWeapon
@onready var touch_vitality: TouchScreenButton = %TouchVitality
@onready var touch_might: TouchScreenButton = %TouchMight
@onready var touch_haste: TouchScreenButton = %TouchHaste
@onready var touch_crit: TouchScreenButton = %TouchCrit
@onready var touch_equip: TouchScreenButton = %TouchEquip
@onready var touch_continue: TouchScreenButton = %TouchContinue
@onready var touch_title: TouchScreenButton = %TouchTitle


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_process(false)
	_bind(vitality_button, touch_vitality, _on_vitality)
	_bind(might_button, touch_might, _on_might)
	_bind(haste_button, touch_haste, _on_haste)
	_bind(crit_button, touch_crit, _on_crit)
	_bind(equip_button, touch_equip, _on_equip)
	_bind(continue_button, touch_continue, _on_continue)
	_bind(title_button, touch_title, _on_title)


func show_rest() -> void:
	if visible:
		return
	_busy = false
	_navigating = false
	_silence_all()
	var pause := get_node_or_null("/root/PauseMenu")
	if pause and pause.visible:
		pause.visible = false
		pause.is_paused = false
	visible = true
	get_tree().paused = true
	set_process(true)
	PlayerManager.convert_gems_to_points()
	PlayerManager.set_health(PlayerManager.horde_max_hp(), PlayerManager.horde_max_hp())
	_refresh()
	SaveManager.save_game()
	continue_button.grab_focus()


func _process(_delta: float) -> void:
	if not MobileSafeLayout.uses_touch_button_twins():
		return
	_align(vitality_button, touch_vitality)
	_align(might_button, touch_might)
	_align(haste_button, touch_haste)
	_align(crit_button, touch_crit)
	_align(equip_button, touch_equip)
	_align(continue_button, touch_continue)
	_align(title_button, touch_title)


func _bind(button: Button, touch: TouchScreenButton, handler: Callable) -> void:
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(handler)
	touch.pressed.connect(handler)
	touch.visible = true


func _align(button: Button, touch: TouchScreenButton) -> void:
	if button == null or touch == null:
		return
	var rect := button.get_global_rect()
	touch.global_position = rect.position + rect.size / 2.0
	if touch.shape is RectangleShape2D:
		(touch.shape as RectangleShape2D).size = rect.size


func _refresh() -> void:
	points_label.text = "Gems: %d" % PlayerManager.bonfire_points
	_set_row(vitality_label, vitality_button, "HP", PlayerManager.vitality_rank, false)
	_set_row(might_label, might_button, "Attack", PlayerManager.might_rank, false)
	_set_row(haste_label, haste_button, "Speed", PlayerManager.haste_rank, PlayerManager.haste_rank >= PlayerManager.HASTE_MAX)
	var crit_name := "Crit  %d%%" % int(round(PlayerManager.crit_chance() * 100.0))
	_set_row(crit_label, crit_button, crit_name, PlayerManager.crit_rank, PlayerManager.crit_rank >= PlayerManager.CRIT_MAX)
	var owned := PlayerManager.has_sword()
	equip_button.disabled = not owned
	if PlayerManager.sword_equipped:
		equip_button.text = "Unequip sword"
	else:
		equip_button.text = "Equip sword"
	avatar_weapon.visible = PlayerManager.sword_equipped


func _set_row(label: Label, button: Button, title: String, rank: int, capped: bool) -> void:
	if capped:
		label.text = "%s  rank %d  maxed" % [title, rank]
		button.disabled = true
		button.text = "Max"
		return
	label.text = "%s  rank %d  next %d" % [title, rank, 2 + rank]
	button.disabled = false
	button.text = "Upgrade"


func _on_vitality() -> void:
	_spend("vitality")


func _on_might() -> void:
	_spend("might")


func _on_haste() -> void:
	_spend("haste")


func _on_crit() -> void:
	_spend("crit")


func _spend(stat: String) -> void:
	if _busy or _navigating:
		return
	_busy = true
	var message := PlayerManager.try_upgrade(stat)
	feedback.text = "Upgraded." if message == "" else message
	_refresh()
	_busy = false


func _on_equip() -> void:
	if _busy or _navigating:
		return
	if not PlayerManager.has_sword():
		feedback.text = "No sword yet."
		return
	_busy = true
	PlayerManager.toggle_sword()
	feedback.text = "Sword equipped." if PlayerManager.sword_equipped else "Sword unequipped."
	_refresh()
	_busy = false


func _on_continue() -> void:
	_leave(HORDE_PATH)


func _on_title() -> void:
	_leave(TITLE_PATH)


func _leave(level_path: String) -> void:
	if _busy or _navigating:
		return
	_navigating = true
	_busy = true
	_restore_audio()
	visible = false
	set_process(false)
	PlayerManager.player_spawned = false
	LevelManager.load_new_level(level_path, "", Vector2.ZERO)


func _silence_all() -> void:
	var music := get_node_or_null("/root/MusicManager")
	if music and music.has_method("stop_for_menu"):
		music.stop_for_menu()
	var index := AudioServer.get_bus_index("Master")
	if index == -1:
		return
	_master_was_muted = AudioServer.is_bus_mute(index)
	AudioServer.set_bus_mute(index, true)


func _restore_audio() -> void:
	var index := AudioServer.get_bus_index("Master")
	if index == -1:
		return
	AudioServer.set_bus_mute(index, _master_was_muted)
