class_name ExplosionEffects
extends Node3D
## Bounded rocket bodies, expanding flashes and boom voices; no hit queries.

@export_group("Flight")
@export var rocket_size_m: Vector3 = Vector3(0.06, 0.06, 0.30)
@export var rocket_color: Color = Color(0.85, 0.55, 0.15)
@export_group("Blast")
@export_range(1, 32) var flash_capacity: int = 8
@export_range(0.05, 1.0, 0.01, "suffix:s") var flash_lifetime: float = 0.30
@export_range(0.01, 1.0, 0.01) var flash_radius_fraction: float = 0.35
@export_range(0.01, 1.0, 0.01, "suffix:m") var flash_start_radius_m: float = 0.15
@export var flash_color: Color = Color(1.0, 0.4, 0.08, 0.45)
@export_group("Sound")
@export_range(1, 16) var sound_capacity: int = 4
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var sound_volume_db: float = -10.0
@export_range(10.0, 200.0, 1.0, "suffix:Hz") var sound_pitch_hz: float = 40.0
@export_range(0.1, 2.0, 0.1, "suffix:s") var sound_duration: float = 0.6
@export_range(1.0, 100.0, 1.0, "suffix:m") var sound_unit_size_m: float = 30.0
@export_range(10.0, 1000.0, 10.0, "suffix:m") var sound_max_distance_m: float = 450.0

var _system: ProjectileSystem
var _rockets: MultiMesh
var _flashes: MultiMesh
var _points: PackedVector3Array = PackedVector3Array()
var _ages: PackedFloat32Array = PackedFloat32Array()
var _radii: PackedFloat32Array = PackedFloat32Array()
var _next_flash: int = 0
var _sounds: Array[AudioStreamPlayer3D] = []
var _next_sound: int = 0
var _rocket_count: int = 0
var _flash_count: int = 0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_points.resize(flash_capacity)
	_ages.resize(flash_capacity)
	_ages.fill(flash_lifetime)
	_radii.resize(flash_capacity)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = _material(Color.WHITE, true)
	_flashes = _batch(sphere, flash_capacity, true)
	for index: int in sound_capacity:
		var voice := AudioStreamPlayer3D.new()
		voice.stream = SfxFactory.gunshot(sound_pitch_hz, sound_duration)
		voice.bus = &"Effects"
		voice.volume_db = sound_volume_db
		voice.unit_size = sound_unit_size_m
		voice.max_distance = sound_max_distance_m
		add_child(voice)
		_sounds.append(voice)
	set_process(false)
	_bind.call_deferred()


func _bind() -> void:
	_system = get_tree().get_first_node_in_group(ProjectileSystem.GROUP) as ProjectileSystem
	if _system != null:
		var box := BoxMesh.new()
		box.size = rocket_size_m
		box.material = _material(rocket_color, false)
		_rockets = _batch(box, _system.capacity, false)
		_system.projectile_fired.connect(_on_fired)
	var explosions := get_tree().get_first_node_in_group(ExplosionSystem.GROUP) as ExplosionSystem
	if explosions != null:
		explosions.exploded.connect(show_explosion)


func show_explosion(point: Vector3, data: ExplosionData) -> void:
	_points[_next_flash] = point
	_ages[_next_flash] = 0.0
	_radii[_next_flash] = data.radius_m * flash_radius_fraction
	_next_flash = (_next_flash + 1) % flash_capacity
	var voice: AudioStreamPlayer3D = _sounds[_next_sound]
	_next_sound = (_next_sound + 1) % sound_capacity
	voice.global_position = point
	voice.play()
	set_process(true)


func _on_fired(_slot: int, _point: Vector3, _velocity: Vector3, spec: ProjectileSpec) -> void:
	if spec.explosion != null:
		set_process(true)


func _process(delta: float) -> void:
	_rocket_count = 0
	if _system != null:
		for slot: int in _system.capacity:
			var spec: ProjectileSpec = _system.get_slot_spec(slot)
			if spec == null or spec.explosion == null:
				continue
			var direction: Vector3 = _system.get_slot_velocity(slot).normalized()
			var up: Vector3 = Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
			var pose := Transform3D(Basis.looking_at(direction, up), _system.get_slot_position(slot))
			_rockets.set_instance_transform(_rocket_count, pose)
			_rocket_count += 1
		_rockets.visible_instance_count = _rocket_count
	_flash_count = 0
	for index: int in flash_capacity:
		if _ages[index] >= flash_lifetime:
			continue
		_ages[index] += delta
		if _ages[index] >= flash_lifetime:
			continue
		var progress: float = _ages[index] / flash_lifetime
		var radius: float = lerpf(flash_start_radius_m, _radii[index], progress)
		_flashes.set_instance_transform(_flash_count, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius), _points[index]))
		var color: Color = flash_color
		color.a *= 1.0 - progress
		_flashes.set_instance_color(_flash_count, color)
		_flash_count += 1
	_flashes.visible_instance_count = _flash_count
	if _rocket_count == 0 and _flash_count == 0:
		set_process(false)


func get_rocket_count() -> int:
	return _rocket_count


func get_flash_count() -> int:
	return _flash_count


func _material(color: Color, transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _batch(mesh: Mesh, count: int, colors: bool) -> MultiMesh:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = colors
	batch.mesh = mesh
	batch.instance_count = count
	batch.visible_instance_count = 0
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = batch
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-1000, -100, -1000), Vector3(2000, 200, 2000))
	add_child(instance)
	return batch
