class_name ProjectileMath
extends RefCounted
## Pure projectile integration. No nodes and no engine state, so it is
## deterministic and unit-testable.
##
## Without drag, `step_position` and `step_velocity` are exact: after any
## number of ticks they match the analytic parabola. With drag, `step_drag`
## integrates acceleration = gravity - k * |v| * v with one RK4 step per tick.
## The `flat_fire_*` functions are the analytic reference for a level shot
## with drag, used to check the integrator.

## Air density at sea level and 15 °C, kg/m³.
const SEA_LEVEL_AIR_DENSITY: float = 1.225


## Position after `delta` seconds of constant `acceleration`.
static func step_position(position: Vector3, velocity: Vector3, acceleration: Vector3, delta: float) -> Vector3:
	return position + velocity * delta + acceleration * (0.5 * delta * delta)


## Velocity after `delta` seconds of constant `acceleration`.
static func step_velocity(velocity: Vector3, acceleration: Vector3, delta: float) -> Vector3:
	return velocity + acceleration * delta


## Acceleration under gravity and quadratic drag with factor `drag` (1/m).
static func drag_acceleration(velocity: Vector3, gravity: Vector3, drag: float) -> Vector3:
	return gravity - velocity * (drag * velocity.length())


## One step under gravity and quadratic drag. Returns [position, velocity].
## With `drag` 0 this is the exact constant-acceleration step.
static func step_drag(position: Vector3, velocity: Vector3, gravity: Vector3, drag: float, delta: float) -> PackedVector3Array:
	if drag <= 0.0:
		return PackedVector3Array([
			step_position(position, velocity, gravity, delta),
			step_velocity(velocity, gravity, delta),
		])
	var half: float = delta * 0.5
	var a1: Vector3 = drag_acceleration(velocity, gravity, drag)
	var v2: Vector3 = velocity + a1 * half
	var a2: Vector3 = drag_acceleration(v2, gravity, drag)
	var v3: Vector3 = velocity + a2 * half
	var a3: Vector3 = drag_acceleration(v3, gravity, drag)
	var v4: Vector3 = velocity + a3 * delta
	var a4: Vector3 = drag_acceleration(v4, gravity, drag)
	var sixth: float = delta / 6.0
	return PackedVector3Array([
		position + (velocity + v2 * 2.0 + v3 * 2.0 + v4) * sixth,
		velocity + (a1 + a2 * 2.0 + a3 * 2.0 + a4) * sixth,
	])


## Seconds for a level shot to cover `distance` metres. `drag` is the drag
## factor in 1/m (0 for none).
static func time_to_distance(distance: float, speed: float, drag: float = 0.0) -> float:
	if speed <= 0.0:
		return INF
	if drag <= 0.0:
		return distance / speed
	return (exp(drag * distance) - 1.0) / (drag * speed)


## Speed of a level shot after `distance` metres.
static func speed_at_distance(distance: float, speed: float, drag: float = 0.0) -> float:
	return speed * exp(-drag * distance)


## Metres a level shot has fallen after `distance` metres.
##
## With drag this is the flat-fire solution: horizontal speed decays as
## v0 * e^(-k x), and the vertical velocity obeys the same drag. It treats
## |v| as the horizontal speed, which is exact to a few parts per million for
## rifle shots, where vertical speed stays tiny.
static func drop_at_distance(distance: float, speed: float, gravity: float, drag: float = 0.0) -> float:
	if drag <= 0.0:
		var time: float = time_to_distance(distance, speed)
		return 0.5 * gravity * time * time
	return gravity / (2.0 * drag * speed * speed) * ((exp(2.0 * drag * distance) - 1.0) / (2.0 * drag) - distance)
