class_name ControllerMath
extends RefCounted

static func response(stick: Vector2, deadzone: float, dynamic: bool) -> Vector2:
	var magnitude: float = minf(stick.length(), 1.0)
	if magnitude <= deadzone:
		return Vector2.ZERO
	var amount: float = (magnitude - deadzone) / (1.0 - deadzone)
	if dynamic:
		amount = amount * amount * amount
	return stick.normalized() * amount

static func look(stick: Vector2, delta: float, speed: Vector2, deadzone: float, dynamic: bool, inverted: bool, ads: float, assist: float, over_target: bool) -> Vector2:
	var value: Vector2 = response(stick, deadzone, dynamic) * speed * delta * ads
	value *= 1.0 - clampf(assist, 0.0, 1.0) * 0.75 if over_target else 1.0
	return Vector2(-deg_to_rad(value.x), deg_to_rad(value.y) * (1.0 if inverted else -1.0))
