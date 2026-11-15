class_name MovementMath
extends RefCounted
## Pure movement math. No nodes, no input, no engine state, so every function
## here is deterministic and unit-testable headless.
##
## Convention: "horizontal" means the XZ plane. Every function leaves the
## vertical (Y) component of the velocity untouched.

const EPSILON: float = 0.0001


static func horizontal(velocity: Vector3) -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)


static func horizontal_speed(velocity: Vector3) -> float:
	return Vector2(velocity.x, velocity.z).length()


## Returns `velocity` with its horizontal part rescaled to `new_speed`,
## keeping direction and the vertical component.
static func with_horizontal_speed(velocity: Vector3, new_speed: float) -> Vector3:
	var speed: float = horizontal_speed(velocity)
	if speed < EPSILON:
		return Vector3(0.0, velocity.y, 0.0)
	var scale: float = maxf(new_speed, 0.0) / speed
	return Vector3(velocity.x * scale, velocity.y, velocity.z * scale)


## Ground friction, integrated exactly so the result does not depend on the
## tick rate.
##
## Above `stop_speed`, speed decays exponentially: v(t) = v0 * exp(-friction * t).
## At or below `stop_speed`, it decays linearly at `stop_speed * friction`
## m/s^2 until it reaches zero. It never reverses direction.
static func apply_friction(velocity: Vector3, friction: float, stop_speed: float, delta: float) -> Vector3:
	var speed: float = horizontal_speed(velocity)
	if speed < EPSILON:
		return Vector3(0.0, velocity.y, 0.0)
	if friction <= 0.0 or delta <= 0.0:
		return velocity

	var remaining: float = delta
	var new_speed: float = speed

	if stop_speed <= 0.0:
		new_speed = speed * exp(-friction * remaining)
		return with_horizontal_speed(velocity, new_speed)

	if new_speed > stop_speed:
		var time_to_stop_speed: float = log(new_speed / stop_speed) / friction
		if remaining <= time_to_stop_speed:
			return with_horizontal_speed(velocity, new_speed * exp(-friction * remaining))
		new_speed = stop_speed
		remaining -= time_to_stop_speed

	new_speed = maxf(new_speed - stop_speed * friction * remaining, 0.0)
	return with_horizontal_speed(velocity, new_speed)


## Raw acceleration toward `wish_speed` along `wish_dir`. Gameplay uses
## `accelerate_capped`; this is the uncapped building block.
##
## Adds at most `accel * wish_speed * delta` of speed along `wish_dir`, and
## never pushes the speed along `wish_dir` past `wish_speed`. Velocity
## perpendicular to `wish_dir` is left alone (friction removes it on the
## ground), which is what gives direction changes their momentum.
static func accelerate(velocity: Vector3, wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> Vector3:
	var direction: Vector3 = horizontal(wish_dir)
	if wish_speed <= 0.0 or direction.length_squared() < EPSILON * EPSILON:
		return velocity
	direction = direction.normalized()

	var current_speed: float = velocity.dot(direction)
	var add_speed: float = wish_speed - current_speed
	if add_speed <= 0.0:
		return velocity

	var gain: float = minf(accel * wish_speed * delta, add_speed)
	return velocity + direction * gain


## Like `accelerate`, but the horizontal speed can never end up above
## max(speed before, wish_speed). Input can redirect momentum; it cannot
## create speed beyond the target. Without this cap, accelerating at an angle
## to the current velocity overshoots the target speed (the classic
## strafe-jump exploit, and a small overspeed when turning on the ground).
static func accelerate_capped(velocity: Vector3, wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> Vector3:
	var speed_before: float = horizontal_speed(velocity)
	var result: Vector3 = accelerate(velocity, wish_dir, wish_speed, accel, delta)
	var speed_cap: float = maxf(speed_before, wish_speed)
	if horizontal_speed(result) > speed_cap:
		result = with_horizontal_speed(result, speed_cap)
	return result


## One ground tick: friction first, then capped acceleration toward the wish
## velocity. Settles at exactly `wish_speed` as long as `accel > friction`.
static func ground_move(
	velocity: Vector3,
	wish_dir: Vector3,
	wish_speed: float,
	accel: float,
	friction: float,
	stop_speed: float,
	delta: float
) -> Vector3:
	var result: Vector3 = apply_friction(velocity, friction, stop_speed, delta)
	return accelerate_capped(result, wish_dir, wish_speed, accel, delta)


## Slide friction: constant deceleration (kinetic friction, mu * g), so speed
## falls linearly and stops at zero.
static func slide_decay(velocity: Vector3, deceleration: float, delta: float) -> Vector3:
	var speed: float = horizontal_speed(velocity)
	if speed < EPSILON:
		return Vector3(0.0, velocity.y, 0.0)
	return with_horizontal_speed(velocity, maxf(speed - deceleration * delta, 0.0))


## Velocity at the start of a slide: adds `boost` along the current direction
## without exceeding `max_speed`. Never slows the player down, even if they
## were already above `max_speed`.
static func slide_entry_velocity(velocity: Vector3, boost: float, max_speed: float) -> Vector3:
	var speed: float = horizontal_speed(velocity)
	if speed < EPSILON:
		return velocity
	var boosted: float = minf(speed + maxf(boost, 0.0), maxf(max_speed, speed))
	return with_horizontal_speed(velocity, boosted)


## Seconds a slide lasts from `entry_speed` until it reaches `end_speed`.
static func slide_duration(entry_speed: float, end_speed: float, deceleration: float) -> float:
	if deceleration <= 0.0 or entry_speed <= end_speed:
		return 0.0
	return (entry_speed - end_speed) / deceleration


## Metres covered by a slide from `entry_speed` until it reaches `end_speed`.
static func slide_distance(entry_speed: float, end_speed: float, deceleration: float) -> float:
	if deceleration <= 0.0 or entry_speed <= end_speed:
		return 0.0
	return (entry_speed * entry_speed - end_speed * end_speed) / (2.0 * deceleration)


## Initial upward velocity needed to reach `height` under `gravity`.
static func jump_velocity(height: float, gravity: float) -> float:
	return sqrt(2.0 * maxf(gravity, 0.0) * maxf(height, 0.0))
