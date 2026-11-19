class_name PlateMotion
extends RefCounted
## Cosmetic plate-insert pose in camera space (-Z forward), driven only by
## insert progress 0..1, so its timeline always matches the Resource timing.
## The plate rises into view, is pushed down into the vest, then drops away.

## Phase boundaries as fractions of the insert.
const RISE_END: float = 0.3
const PUSH_END: float = 0.75

const START := Vector3(0.12, -0.60, -0.55)
const SHOWN := Vector3(0.05, -0.24, -0.55)
const PUSHED := Vector3(0.02, -0.40, -0.35)
const GONE := Vector3(0.0, -0.70, -0.30)
const TILT_SHOWN: float = -0.5
const TILT_PUSHED: float = -1.2


static func pose(progress: float) -> Transform3D:
	var t: float = clampf(progress, 0.0, 1.0)
	var origin: Vector3
	var tilt: float
	if t < RISE_END:
		var k: float = smoothstep(0.0, 1.0, t / RISE_END)
		origin = START.lerp(SHOWN, k)
		tilt = lerpf(TILT_PUSHED, TILT_SHOWN, k)
	elif t < PUSH_END:
		var k: float = smoothstep(0.0, 1.0, (t - RISE_END) / (PUSH_END - RISE_END))
		origin = SHOWN.lerp(PUSHED, k)
		tilt = lerpf(TILT_SHOWN, TILT_PUSHED, k)
	else:
		var k: float = smoothstep(0.0, 1.0, (t - PUSH_END) / (1.0 - PUSH_END))
		origin = PUSHED.lerp(GONE, k)
		tilt = TILT_PUSHED
	return Transform3D(Basis(Vector3.RIGHT, tilt), origin)
