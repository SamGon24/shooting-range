class_name ChallengeAttempt
extends RefCounted

var rule: ChallengeRule
var remaining: float
var shots: int = 0
var hits: int = 0
var done: bool = false
var _live: Dictionary[int, bool] = {}

func _init(selected: ChallengeRule) -> void:
	rule = selected
	remaining = rule.seconds

func advance(delta: float) -> void:
	if done or rule.seconds == 0:
		return
	remaining = maxf(0, remaining - delta)
	done = remaining <= 0.000001

func launch(id: int) -> void:
	if done or (rule.shots_allowed > 0 and shots >= rule.shots_allowed):
		return
	shots += 1
	_live[id] = false

func contact(id: int, target: ChallengeRule.Target) -> void:
	if done or not _live.has(id) or _live[id]:
		return
	if rule.target == ChallengeRule.Target.ANY or rule.target == target:
		_live[id] = true
		hits += 1

func finish_shot(id: int) -> void:
	_live.erase(id)
	if rule.shots_allowed > 0 and shots == rule.shots_allowed and _live.is_empty():
		done = true

func score() -> int:
	if rule.shots_allowed > 0:
		return roundi(100.0 * hits / rule.shots_allowed)
	return hits
