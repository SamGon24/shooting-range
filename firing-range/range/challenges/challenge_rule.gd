class_name ChallengeRule
extends Resource

enum Target { STATIONARY, ANY, STEEL, MOVING }

@export var id: StringName
@export var title: String
@export var objective: String
@export var target: Target
@export var seconds: int
## A shot-limited run waits for the final eligible shot groups to resolve.
@export var shots_allowed: int
@export var medals: Vector3i

func medal(score: int) -> String:
	if score >= medals.z:
		return "Gold"
	if score >= medals.y:
		return "Silver"
	if score >= medals.x:
		return "Bronze"
	return "No medal"

func score_text(score: int) -> String:
	return "%d%%" % score if shots_allowed > 0 else "%d hits" % score
