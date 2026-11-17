class_name ConeSpread
extends RefCounted
## Shared deterministic cone sampling; gameplay and pellet delivery use
## one seeded stream. No collision or damage logic lives here.


static func sample(direction: Vector3, spread: float, rng: RandomNumberGenerator) -> Vector3:
	var forward: Vector3 = direction.normalized()
	if spread <= 0.0:
		return forward
	var angle: float = deg_to_rad(spread) * sqrt(rng.randf())
	var around: float = rng.randf() * TAU
	var side: Vector3 = forward.cross(Vector3.UP)
	if side.length_squared() < 0.000001:
		side = forward.cross(Vector3.RIGHT)
	side = side.normalized()
	var tilt_axis: Vector3 = side.rotated(forward, around)
	return forward.rotated(tilt_axis, angle)
