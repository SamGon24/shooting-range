class_name DamageDirection
extends RefCounted
## Pure maths for the damage-direction indicator. Angles are on screen:
## 0 is straight ahead (top of the indicator ring), positive is clockwise
## (to the right), and ±PI is directly behind.


## World direction the damage travelled in, or zero if unknown. A blast or
## a swing reports where it came from; a bullet reports its velocity.
static func incoming(hit: ProjectileHit, victim_position: Vector3) -> Vector3:
	if hit.source_position.is_finite():
		return victim_position - hit.source_position
	if not hit.velocity.is_zero_approx():
		return hit.velocity
	return hit.impulse_override


## Screen angle of the attacker for a player looking along `yaw` (radians,
## as `PlayerController.yaw`: 0 faces -Z, positive turns left). Returns NAN
## when the damage has no horizontal direction.
static func screen_angle(incoming_direction: Vector3, yaw: float) -> float:
	var to_source := Vector2(-incoming_direction.x, -incoming_direction.z)
	if to_source.length_squared() < 0.000001:
		return NAN
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	return atan2(to_source.dot(right), to_source.dot(forward))
