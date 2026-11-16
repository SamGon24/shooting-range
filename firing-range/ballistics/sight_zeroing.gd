class_name SightZeroing
extends RefCounted
## Low-arc sight calibration using the same RK4 steps and swept chords as
## ProjectileSystem. Coordinates are relative to a horizontal sight line.

const SOLVE_STEPS: int = 40
const MAX_ANGLE: float = PI / 4.0


## Signed height above the sight line at a downrange plane. NAN means the
## bullet cannot reach that plane within its configured lifetime.
static func height_at_distance(spec: ProjectileSpec, distance: float, sight_height: float, angle: float, gravity: float, density: float, tick: float) -> float:
	var position := Vector3(0.0, -sight_height, 0.0)
	var velocity: Vector3 = Vector3(0.0, sin(angle), -cos(angle)) * spec.muzzle_velocity
	var acceleration: Vector3 = Vector3.DOWN * gravity * spec.gravity_scale
	var drag: float = spec.drag_factor(density)
	for step: int in ceili(spec.max_lifetime / tick):
		var result: PackedVector3Array = ProjectileMath.step_drag(position, velocity, acceleration, drag, tick)
		var next: Vector3 = result[0]
		if -next.z >= distance:
			# Match the physics ray's straight segment at the plane, rather
			# than integrating a shorter final tick along a different curve.
			return lerpf(position.y, next.y, (-distance - position.z) / (next.z - position.z))
		position = next
		velocity = result[1]
	return NAN


## Radians above the sight line, found by bisection without approximating
## sin, cos or the drag model. 0 distance explicitly disables calibration.
## The bracket selects the practical low arc (0–45 degrees), not a lob.
static func solve(spec: ProjectileSpec, distance: float, sight_height: float, gravity: float, density: float, tick: float) -> float:
	if distance <= 0.0:
		return 0.0
	var low: float = 0.0
	var high: float = MAX_ANGLE
	var low_height: float = height_at_distance(spec, distance, sight_height, low, gravity, density, tick)
	var high_height: float = height_at_distance(spec, distance, sight_height, high, gravity, density, tick)
	if is_nan(low_height) or is_nan(high_height) or low_height > 0.0 or high_height < 0.0:
		return NAN
	for iteration: int in SOLVE_STEPS:
		var middle: float = (low + high) * 0.5
		if height_at_distance(spec, distance, sight_height, middle, gravity, density, tick) < 0.0:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5
