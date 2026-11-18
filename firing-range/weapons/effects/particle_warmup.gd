class_name ParticleWarmup
extends RefCounted
## Pays a particle effect's first-draw cost at load instead of on the first
## shot.
##
## The first time a particle material is drawn, the renderer sets up its
## shader and buffers. On the target Intel GPU that took about half a second
## in total for the muzzle sparks, smoke and impact sparks: a visible freeze on
## the first shot of a session. A throwaway twin of each emitter, sharing its
## mesh and material, emits one particle of negligible size in front of the
## camera a few frames after load, then frees itself. It does nothing under
## the headless renderer, where there is nothing to compile.

const TINY_SCALE: float = 0.0001
const SETTLE_FRAMES: int = 3


## True when drawing happens at all, so warming is worth doing. The debug
## argument `--no-warmup` turns it off, to measure the cost it removes.
static func is_needed() -> bool:
	return DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().has("--no-warmup")


## Waits a few frames so the camera and the world exist.
static func settle(node: Node) -> void:
	for frame: int in SETTLE_FRAMES:
		await node.get_tree().process_frame


## Emits one invisible particle from a twin of `emitter`, placed at
## `world_position` when it is world-space, or at the parent's origin when it
## rides on a moving parent. Returns the twin (null when nothing was done).
static func warm(emitter: CPUParticles3D, world_position: Vector3, force: bool = false) -> CPUParticles3D:
	if (not force and not is_needed()) or not is_instance_valid(emitter) or not emitter.is_inside_tree():
		return null
	var twin := emitter.duplicate() as CPUParticles3D
	twin.name = "Warmup"
	twin.scale_amount_min = TINY_SCALE
	twin.scale_amount_max = TINY_SCALE
	twin.amount = 1
	twin.one_shot = true
	twin.emitting = false
	emitter.get_parent().add_child(twin)
	if not emitter.local_coords and emitter.get_parent() is Node3D:
		twin.global_position = world_position
	twin.restart()
	twin.emitting = true
	_free_later(twin)
	return twin


static func _free_later(twin: CPUParticles3D) -> void:
	await twin.get_tree().create_timer(twin.lifetime + 0.25).timeout
	if is_instance_valid(twin):
		twin.queue_free()
