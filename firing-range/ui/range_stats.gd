class_name RangeStats
extends RefCounted
## Node-free session statistics. Caller supplies physics-clock timestamps.

var shots: int = 0
var hits: int = 0
var headshots: int = 0
## -1 means no dummy has been killed since reset.
var last_time_to_kill: float = -1.0
var _first_hits: Dictionary[int, float] = {}


func record_shot() -> void:
	shots += 1


func record_hit(target_id: int, headshot: bool, killed: bool, now: float, tracks_life: bool = true) -> void:
	hits += 1
	if headshot:
		headshots += 1
	if not tracks_life:
		return
	if not _first_hits.has(target_id):
		_first_hits[target_id] = now
	if killed:
		last_time_to_kill = maxf(0.0, now - _first_hits[target_id])
		_first_hits.erase(target_id)


func accuracy_percent() -> float:
	return 100.0 * float(hits) / float(shots) if shots > 0 else 0.0


func headshot_percent() -> float:
	return 100.0 * float(headshots) / float(hits) if hits > 0 else 0.0


func end_life(target_id: int) -> void:
	_first_hits.erase(target_id)


func reset() -> void:
	shots = 0
	hits = 0
	headshots = 0
	last_time_to_kill = -1.0
	_first_hits.clear()
