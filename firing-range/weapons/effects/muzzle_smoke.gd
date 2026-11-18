class_name MuzzleSmoke
extends Node3D
## Pooled muzzle smoke puffs. Cosmetic only.
##
## A fixed number of one-shot particle emitters is built once. Each shot
## restarts the oldest one at the muzzle's world position; its particles
## stay where they were made, drift upward and fade. No node is created per
## shot and nothing here can touch gameplay.

const GROUP: StringName = &"muzzle_smoke"

@export_range(1, 32) var emitters: int = 8
@export_range(0.2, 3.0, 0.05, "suffix:s") var lifetime_s: float = 0.9
@export_range(0.0, 2.0, 0.05, "suffix:m/s") var rise_speed: float = 0.45
@export_range(0.0, 3.0, 0.05, "suffix:m/s") var burst_speed: float = 0.9
@export_range(0.02, 0.5, 0.01, "suffix:m") var puff_size: float = 0.14
@export_range(1.0, 8.0, 0.1) var growth: float = 3.2
@export var color: Color = Color(0.78, 0.78, 0.8, 0.30)
## The particle budget one emitter can show; a weapon asks for fewer.
@export_range(1, 32) var max_particles_per_puff: int = 12

var _emitters: Array[CPUParticles3D] = []
var _next: int = 0


func _ready() -> void:
	add_to_group(GROUP)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Without this the particle's scale is dropped and every quad draws at the
	# mesh's full 1 m size.
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	var fade := Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(1.0, 1.0))
	for index: int in emitters:
		var puff := CPUParticles3D.new()
		puff.name = "Puff%d" % index
		puff.mesh = quad
		puff.emitting = false
		puff.one_shot = true
		puff.amount = max_particles_per_puff
		puff.lifetime = lifetime_s
		puff.explosiveness = 0.85
		puff.local_coords = false
		puff.direction = Vector3(0.0, 0.4, -1.0)
		puff.spread = 35.0
		puff.gravity = Vector3(0.0, rise_speed, 0.0)
		puff.initial_velocity_min = burst_speed * 0.3
		puff.initial_velocity_max = burst_speed
		puff.damping_min = 1.6
		puff.damping_max = 2.4
		puff.scale_amount_min = puff_size * 0.8
		puff.scale_amount_max = puff_size * 1.3
		puff.scale_amount_curve = curve
		puff.color_ramp = fade
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(puff)
		_emitters.append(puff)
	_warm_up.call_deferred()


## Puffs `particles` of smoke from `position`, flying roughly along
## `direction` (the barrel axis). Zero particles is a no-op.
func puff(position: Vector3, direction: Vector3, particles: int) -> CPUParticles3D:
	if particles <= 0 or _emitters.is_empty():
		return null
	var emitter: CPUParticles3D = _emitters[_next]
	_next = (_next + 1) % _emitters.size()
	emitter.amount = mini(particles, max_particles_per_puff)
	emitter.global_position = position
	emitter.reset_physics_interpolation()
	emitter.direction = direction.normalized() + Vector3.UP * 0.4
	emitter.restart()
	emitter.emitting = true
	return emitter


## Pays the smoke's first-draw cost before the first shot.
func _warm_up() -> void:
	if not ParticleWarmup.is_needed():
		return
	await ParticleWarmup.settle(self)
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null:
		ParticleWarmup.warm(_emitters[0], camera.global_position - camera.global_basis.z * 2.0)


func get_emitters() -> Array[CPUParticles3D]:
	return _emitters
