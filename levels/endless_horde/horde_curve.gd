class_name HordeCurve
extends RefCounted

## Boss stages: the last stage of every arena block (BOSS_EVERY, below) is one
## boss with BOSS_PHASES health bars, each ending in a speech challenge.
## Future idle DPS: bonfire field idle_dps_rank (cap 5), cost 2+rank (gems),
## idle_dps_per_sec() == rank; tick once/sec via Enemy._take_damage (speech still
## required at 0 HP); never PROCESS_MODE_ALWAYS; never call enemy_destroyed.
static func spawn_total(stage: int) -> int:
	return clampi(2 + stage + int((stage - 1) / 3), 3, 22)


static func retry_quota(stage: int, short: bool) -> int:
	if is_boss_stage(stage):
		return 1
	var full := spawn_total(stage)
	if not short:
		return full
	return maxi(3, int(ceil(float(full) / 2.0)))


static func alive_cap(stage: int) -> int:
	return clampi(5 + int(stage / 3), 6, 12)


static func spawn_interval(stage: int) -> float:
	return maxf(0.3, 1.25 - 0.05 * float(stage - 1))


static func hp_multiplier(stage: int) -> float:
	return 1.0 + 0.12 * float(stage - 1)


static func speed_multiplier(stage: int) -> float:
	return minf(1.8, 1.0 + 0.04 * float(stage - 1))


static func damage_multiplier(stage: int) -> float:
	return minf(2.5, 1.0 + 0.08 * float(stage - 1))


static func split_count_for(stage: int) -> int:
	if stage < 8:
		return 0
	return 2


static func kind_for(stage: int, index: int) -> String:
	if is_boss_stage(stage):
		return str(boss_for_stage(stage).get("kind", "slime"))
	if stage <= 2:
		return "slime"
	if stage <= 4:
		return "goblin" if index % 3 == 2 else "slime"
	if stage <= 7:
		# Introduce orc alongside the original trio.
		match index % 4:
			0:
				return "slime"
			1:
				return "goblin"
			2:
				return "beetle"
			_:
				return "orc"
	if stage <= 10:
		match index % 4:
			0:
				return "goblin"
			1:
				return "beetle"
			2:
				return "orc"
			_:
				return "skeleton"
	# stage 11+: full roster, beetle/orc/skeleton/bandit-heavy
	match index % 5:
		0:
			return "beetle"
		1:
			return "orc"
		2:
			return "skeleton"
		3:
			return "bandit"
		_:
			return "goblin"


static func idle_dps_per_sec() -> float:
	# v1: off. Future: return float(idle_dps_rank) from PlayerManager.
	return 0.0


## Arenas: a new map every ARENA_STAGE_SPAN stages, cycling through ARENA_COUNT.
## 1-20 -> 0, 21-40 -> 1, 41-60 -> 2, 61-80 -> 3, 81+ cycles. Practice (stage 0) -> 0.
## Layout only: arenas never change the difficulty numbers above.
const ARENA_STAGE_SPAN := 20
const ARENA_COUNT := 4
const ARENA_NAMES := ["Meadow", "Stone Ruins", "Ashen Camp", "Frozen Hollow"]


static func arena_index_for(stage: int) -> int:
	return int((maxi(stage, 1) - 1) / ARENA_STAGE_SPAN) % ARENA_COUNT


static func arena_name_for(index: int) -> String:
	return str(ARENA_NAMES[posmod(index, ARENA_COUNT)])


## Bosses: the block's last stage (20, 40, 60...) is one boss, picked by arena so
## the roster cycles with the arenas. Add rows here to add bosses. Each phase
## re-applies "tune" (State/property: factor, skipped if missing) and spawns
## "adds" split children. Whole-number BOSS_SCALE keeps the pixel grid even.
## "ranged" configures BossRangedAttack (count grows by count_step per phase).
const BOSS_EVERY := ARENA_STAGE_SPAN
const BOSS_PHASES := 3
const BOSS_PHASE_BANDS := [2, 3, 3]
const BOSS_SCALE := 2.0
const BOSS_CLEAR_PAUSE := 1.5
const BOSS_PHASE_GRACE := 1.25
const BOSS_REWARD_BASE := 10
const BOSS_REWARD_STEP := 5
## No single boss hit (touch, thrust, charge, shot) takes more than a quarter
## of the base 20 HP: a relentless boss must not two-shot the player.
const BOSS_MAX_HIT := 5
## Bosses enter at least this far from the player, never under the top HUD band.
const BOSS_SPAWN_MIN_GAP := 200.0
const BOSS_SPAWN_TOP_BAND := 112.0
const BOSSES: Array[Dictionary] = [
	{"name": "Slime King", "kind": "slime", "sheet": "res://enemies/bosses/slime_king.png", "adds": 2,
		"tune": {"Chase/chase_speed": 1.15, "Ranged/cooldown": 0.85},
		"add_sheet": "res://enemies/bosses/slime_minion.png", "add_chase": true,
		"ranged": {"shape": "glob", "count": 3, "count_step": 1, "spread_deg": 40.0, "speed": 80.0,
			"cooldown": 3.2, "windup": 0.6}},
	{"name": "Bone Captain", "kind": "skeleton", "sheet": "res://enemies/bosses/bone_captain.png", "adds": 0,
		"tune": {"Chase/thrust_cooldown": 0.75, "Chase/thrust_speed": 1.15, "Ranged/cooldown": 0.85},
		"ranged": {"shape": "bone", "count": 1, "count_step": 1, "spread_deg": 15.0, "speed": 140.0,
			"cooldown": 2.6, "windup": 0.5}},
	{"name": "Orc Warlord", "kind": "orc", "sheet": "res://enemies/bosses/orc_warlord.png", "adds": 0,
		"tune": {"Chase/telegraph_duration": 0.8, "Chase/charge_speed": 1.15, "Chase/charge_cooldown": 0.8,
			"Ranged/cooldown": 0.85},
		"ranged": {"shape": "axe", "count": 1, "count_step": 1, "spread_deg": 25.0, "speed": 95.0,
			"cooldown": 3.0, "windup": 0.7}},
	{"name": "Frost Bandit", "kind": "bandit", "sheet": "res://enemies/bosses/frost_bandit.png", "adds": 0,
		"tune": {"Chase/dart_cooldown": 0.75, "Chase/dart_speed": 1.15, "Ranged/cooldown": 0.85},
		"ranged": {"shape": "shard", "count": 3, "count_step": 1, "spread_deg": 30.0, "speed": 120.0,
			"cooldown": 2.8, "windup": 0.4}},
]


static func is_boss_stage(stage: int) -> bool:
	return stage > 0 and stage % BOSS_EVERY == 0


static func boss_for_stage(stage: int) -> Dictionary:
	if not is_boss_stage(stage):
		return {}
	return BOSSES[arena_index_for(stage) % BOSSES.size()]


## One health bar. Base kind HP is ignored so every boss lasts about as long.
static func boss_phase_hp(stage: int) -> int:
	return maxi(4, roundi(3.0 * hp_multiplier(stage)))


static func boss_phase_band(phase: int) -> int:
	return int(BOSS_PHASE_BANDS[clampi(phase, 0, BOSS_PHASE_BANDS.size() - 1)])


static func boss_reward_gems(stage: int) -> int:
	if not is_boss_stage(stage):
		return 0
	return BOSS_REWARD_BASE + BOSS_REWARD_STEP * maxi(int(stage / BOSS_EVERY) - 1, 0)


static func band_for_stage(stage: int) -> int:
	if stage <= 2:
		return 0
	if stage <= 5:
		return 1
	if stage <= 9:
		return 2
	return 3
