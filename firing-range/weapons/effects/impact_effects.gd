class_name ImpactEffects
extends Node3D
## What you see and hear when a projectile hits: sparks, a mark on the
## surface, and a tick. Listens to `ProjectileSystem.projectile_hit`.
##
## Everything is pooled and created once in `_ready`. Marks are instances in
## a single MultiMesh (one draw call for all of them), and the oldest mark is
## overwritten when the pool is full. The Compatibility renderer has no Decal
## node, so marks are quads placed just off the surface.

const MARK_SHADER: Shader = preload("res://weapons/effects/impact_mark.gdshader")

@export_group("Marks")
## Marks kept in the world before the oldest is reused.
@export_range(8, 512) var mark_capacity: int = 96
@export_range(0.02, 0.5, 0.005, "suffix:m") var mark_size: float = 0.12
## Random size variation, as a fraction either side of `mark_size`.
@export_range(0.0, 0.5, 0.01) var mark_size_variation: float = 0.2
## Gap between the mark and the surface, to avoid z-fighting.
@export_range(0.001, 0.05, 0.001, "suffix:m") var mark_surface_offset: float = 0.01

@export_group("Sparks")
@export_range(1, 32) var spark_emitters: int = 8
@export_range(1, 32) var sparks_per_hit: int = 10
@export_range(0.05, 1.0, 0.01, "suffix:s") var spark_lifetime: float = 0.28
@export var spark_color: Color = Color(1.0, 0.72, 0.3)

@export_group("Sound")
@export_range(1, 16) var sound_players: int = 4
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var sound_volume_db: float = -8.0

var _marks: MultiMesh
## Script-side copy of each mark's transform. The headless renderer does not
## store MultiMesh data, so this is what tests and tools read back.
var _mark_transforms: Array[Transform3D] = []
var _next_mark: int = 0
var _sparks: Array[CPUParticles3D] = []
var _next_spark: int = 0
var _sounds: Array[AudioStreamPlayer3D] = []
var _next_sound: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_build_marks()
	_build_sparks()
	_build_sounds()
	_connect_to_projectiles.call_deferred()


## Shows the effects for one hit. Connected to the projectile system; also
## callable directly.
func show_impact(hit: ProjectileHit) -> void:
	_play_sparks(hit.position, hit.normal)
	_play_sound(hit.position)
	# Marks only stick to the static world; a mark on something that moves
	# would be left hanging in the air.
	if hit.collider is StaticBody3D:
		_place_mark(hit.position, hit.normal)


## Marks currently drawn.
func get_mark_count() -> int:
	return _marks.visible_instance_count


func get_mark_transform(index: int) -> Transform3D:
	return _mark_transforms[index]


func _connect_to_projectiles() -> void:
	var system := get_tree().get_first_node_in_group(ProjectileSystem.GROUP) as ProjectileSystem
	if system != null and not system.projectile_hit.is_connected(show_impact):
		system.projectile_hit.connect(show_impact)


func _place_mark(point: Vector3, normal: Vector3) -> void:
	var facing: Basis = _basis_facing(normal).rotated(normal, _rng.randf() * TAU)
	var size: float = mark_size * (1.0 + _rng.randf_range(-mark_size_variation, mark_size_variation))
	var transform := Transform3D(facing.scaled(Vector3.ONE * size), point + normal * mark_surface_offset)

	_mark_transforms[_next_mark] = transform
	_marks.set_instance_transform(_next_mark, transform)
	# Without this the instance would slide in from its previous position
	# for one tick, because physics interpolation is on.
	_marks.reset_instance_physics_interpolation(_next_mark)
	_marks.visible_instance_count = mini(_marks.visible_instance_count + 1, mark_capacity)
	_next_mark = (_next_mark + 1) % mark_capacity


func _play_sparks(point: Vector3, normal: Vector3) -> void:
	var emitter: CPUParticles3D = _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % _sparks.size()
	emitter.global_position = point + normal * 0.02
	emitter.reset_physics_interpolation()
	emitter.direction = normal
	emitter.restart()
	emitter.emitting = true


func _play_sound(point: Vector3) -> void:
	var player: AudioStreamPlayer3D = _sounds[_next_sound]
	_next_sound = (_next_sound + 1) % _sounds.size()
	player.global_position = point
	player.play()


## A basis whose +Z axis points along `normal` (the way a QuadMesh faces).
func _basis_facing(normal: Vector3) -> Basis:
	var up: Vector3 = Vector3.UP if absf(normal.y) < 0.99 else Vector3.RIGHT
	return Basis.looking_at(-normal, up)


func _build_marks() -> void:
	var material := ShaderMaterial.new()
	material.shader = MARK_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material

	_marks = MultiMesh.new()
	_marks.transform_format = MultiMesh.TRANSFORM_3D
	_marks.mesh = quad
	_marks.instance_count = mark_capacity
	_marks.visible_instance_count = 0
	_mark_transforms.resize(mark_capacity)

	var instance := MultiMeshInstance3D.new()
	instance.name = "Marks"
	instance.multimesh = _marks
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Marks can be anywhere on the range, so never cull the batch.
	instance.custom_aabb = AABB(Vector3(-1000.0, -100.0, -1000.0), Vector3(2000.0, 200.0, 2000.0))
	add_child(instance)


func _build_sparks() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = spark_color
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.012, 0.05)
	mesh.material = material

	for index: int in spark_emitters:
		var emitter := CPUParticles3D.new()
		emitter.name = "Sparks%d" % index
		emitter.mesh = mesh
		emitter.emitting = false
		emitter.one_shot = true
		emitter.amount = sparks_per_hit
		emitter.lifetime = spark_lifetime
		emitter.explosiveness = 1.0
		emitter.spread = 55.0
		emitter.gravity = Vector3(0.0, -9.81, 0.0)
		emitter.initial_velocity_min = 1.5
		emitter.initial_velocity_max = 5.0
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(emitter)
		_sparks.append(emitter)


func _build_sounds() -> void:
	var stream: AudioStreamWAV = SfxFactory.impact()
	for index: int in sound_players:
		var player := AudioStreamPlayer3D.new()
		player.name = "ImpactSound%d" % index
		player.stream = stream
		player.volume_db = sound_volume_db
		player.unit_size = 8.0
		player.max_distance = 150.0
		add_child(player)
		_sounds.append(player)
