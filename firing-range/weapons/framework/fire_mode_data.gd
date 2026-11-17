class_name FireModeData
extends Resource

enum Kind { FULL_AUTO, SEMI_AUTO, BOLT_ACTION, PUMP_ACTION }
@export var kind: Kind = Kind.FULL_AUTO


func wants_shot(held: bool, pressed: bool) -> bool:
	return held if kind == Kind.FULL_AUTO else pressed


func interval(rpm: float, cycle_seconds: float) -> float:
	return maxf(60.0 / rpm, cycle_seconds)
