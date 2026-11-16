class_name ProjectileMath
extends RefCounted
## Pure projectile integration. No nodes and no engine state, so it is
## deterministic and unit-testable.
##
## Under constant acceleration these two steps are exact: after any number of
## ticks the position and velocity match the analytic parabola, at any tick
## rate. Milestone 3 adds drag by changing the acceleration passed in.


## Position after `delta` seconds of constant `acceleration`.
static func step_position(position: Vector3, velocity: Vector3, acceleration: Vector3, delta: float) -> Vector3:
	return position + velocity * delta + acceleration * (0.5 * delta * delta)


## Velocity after `delta` seconds of constant `acceleration`.
static func step_velocity(velocity: Vector3, acceleration: Vector3, delta: float) -> Vector3:
	return velocity + acceleration * delta


## Seconds for a level shot to cover `distance` metres with no drag.
static func time_to_distance(distance: float, speed: float) -> float:
	if speed <= 0.0:
		return INF
	return distance / speed


## Metres a level shot has fallen after `distance` metres, with no drag.
static func drop_at_distance(distance: float, speed: float, gravity: float) -> float:
	var time: float = time_to_distance(distance, speed)
	return 0.5 * gravity * time * time
