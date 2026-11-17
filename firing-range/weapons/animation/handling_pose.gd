class_name HandlingPose
extends RefCounted
## The sampled handling animation for one moment: an offset and rotation per
## part plus which parts are hidden. Reused every frame; `clear` keeps the
## dictionaries' storage.

var offsets: Dictionary[StringName, Vector3] = {}
## Radians, applied as Euler XYZ in the part's local space.
var rotations: Dictionary[StringName, Vector3] = {}
var hidden: Dictionary[StringName, bool] = {}
## Working storage for `HandlingTimeline.evaluate`, kept to avoid per-frame
## allocations.
var shown_scratch: Dictionary[StringName, bool] = {}
var hidden_scratch: Dictionary[StringName, bool] = {}


func clear() -> void:
	offsets.clear()
	rotations.clear()
	hidden.clear()
	shown_scratch.clear()
	hidden_scratch.clear()


func offset(part: StringName) -> Vector3:
	return offsets.get(part, Vector3.ZERO)


func rotation(part: StringName) -> Vector3:
	return rotations.get(part, Vector3.ZERO)


func is_hidden(part: StringName) -> bool:
	return hidden.get(part, false)


## The part's local transform for this pose, given its rest transform.
func apply_to(part: StringName, rest: Transform3D, hidden_scale: Vector3) -> Transform3D:
	var rotated: Basis = rest.basis * Basis.from_euler(rotation(part))
	if is_hidden(part):
		rotated = rotated * Basis.from_scale(hidden_scale)
	return Transform3D(rotated, rest.origin + offset(part))
