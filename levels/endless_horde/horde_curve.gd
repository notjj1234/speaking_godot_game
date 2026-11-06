class_name HordeCurve
extends RefCounted

## Future: boss every N stages when is_boss_stage returns true.
## Future idle DPS: bonfire field idle_dps_rank (cap 5), cost 2+rank (gems),
## idle_dps_per_sec() == rank; tick once/sec via Enemy._take_damage (speech still
## required at 0 HP); never PROCESS_MODE_ALWAYS; never call enemy_destroyed.
const BOSS_EVERY := 10


static func spawn_total(stage: int) -> int:
	return clampi(2 + stage, 3, 12)


static func retry_quota(stage: int, short: bool) -> int:
	var full := spawn_total(stage)
	if not short:
		return full
	return maxi(3, int(ceil(float(full) / 2.0)))


static func alive_cap() -> int:
	return 6


static func spawn_interval(stage: int) -> float:
	return maxf(0.45, 1.25 - 0.04 * float(stage - 1))


static func hp_multiplier(stage: int) -> float:
	return 1.0 + 0.12 * float(stage - 1)


static func speed_multiplier(stage: int) -> float:
	return minf(1.35, 1.0 + 0.015 * float(stage - 1))


static func split_count_for(stage: int) -> int:
	if stage < 8:
		return 0
	return 2


static func kind_for(stage: int, index: int) -> String:
	if stage <= 2:
		return "slime"
	if stage <= 4:
		return "goblin" if index % 3 == 2 else "slime"
	if stage <= 7:
		match index % 3:
			0:
				return "slime"
			1:
				return "goblin"
			_:
				return "beetle"
	# stage 8+
	match index % 3:
		0, 2:
			return "goblin"
		_:
			return "beetle"


static func is_boss_stage(_stage: int) -> bool:
	# v1: always false. Future: stage > 0 and stage % BOSS_EVERY == 0
	return false


static func idle_dps_per_sec() -> float:
	# v1: off. Future: return float(idle_dps_rank) from PlayerManager.
	return 0.0


static func band_for_stage(stage: int) -> int:
	if stage <= 2:
		return 0
	if stage <= 5:
		return 1
	if stage <= 9:
		return 2
	return 3
