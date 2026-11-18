class_name CasingPool
extends Node3D
## Pooled ejected casings and shells. Cosmetic only.
##
## A fixed number of small rigid bodies is built once. Each ejection reuses
## the oldest body: it is sized to the weapon's casing, thrown out of the
## ejection port, falls, settles and is put away after `lifetime_s` of
## gameplay time. Nothing is allocated per shot.
##
## Bodies sit on the debris layer and only scan the world, so projectiles,
## melee casts, blasts, the player and ragdolls never see them. They can
## never change a hit or a statistic.

const GROUP: StringName = &"casing_pool"

@export_range(1, 64) var capacity: int = 24
## Gameplay seconds before a casing is put away.
@export_range(0.5, 10.0, 0.1, "suffix:s") var lifetime_s: float = 2.0
## Mass per metre of casing length: a 45 mm rifle case weighs about 12 g.
@export_range(0.05, 1.0, 0.01, "suffix:kg/m") var mass_per_metre: float = 0.27
## Ejection speed range along the port's outward axis, with sideways and
## upward scatter.
@export var eject_speed: Vector2 = Vector2(1.6, 2.6)
@export_range(0.0, 4.0, 0.05, "suffix:m/s") var eject_lift: float = 1.2
@export_range(0.0, 2.0, 0.05, "suffix:m/s") var eject_scatter: float = 0.4
@export_range(0.0, 40.0, 0.5, "suffix:rad/s") var eject_spin: float = 18.0
@export_flags_3d_physics var debris_layer: int = 16
@export_flags_3d_physics var collision_mask: int = 1

## Materials are made once per distinct colour, up front for the colours the
## weapons use, so the first shot of a weapon builds nothing.
const KNOWN_COLORS: Array[Color] = [Color(0.8, 0.62, 0.25), Color(0.65, 0.12, 0.1)]

var _materials: Dictionary[Color, StandardMaterial3D] = {}
var _bodies: Array[RigidBody3D] = []
var _shapes: Array[BoxShape3D] = []
var _meshes: Array[MeshInstance3D] = []
var _ages: PackedFloat32Array = PackedFloat32Array()
var _active: Array[bool] = []
var _next: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(GROUP)
	_rng.randomize()
	var material := PhysicsMaterial.new()
	material.friction = 0.7
	material.bounce = 0.35
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	for known: Color in KNOWN_COLORS:
		_material_for(known)
	for index: int in capacity:
		var body := RigidBody3D.new()
		body.name = "Casing%d" % index
		body.physics_material_override = material
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
		body.collision_layer = 0
		body.collision_mask = 0
		body.visible = false
		body.can_sleep = true
		var shape := BoxShape3D.new()
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		var instance := MeshInstance3D.new()
		instance.mesh = unit
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(instance)
		add_child(body)
		_bodies.append(body)
		_shapes.append(shape)
		_meshes.append(instance)
		_ages.append(0.0)
		_active.append(false)


func _physics_process(delta: float) -> void:
	for index: int in _bodies.size():
		if not _active[index]:
			continue
		_ages[index] += delta
		if _ages[index] >= lifetime_s:
			_park(index)


## Throws a casing out of `port`, a world transform whose +X axis points out
## of the weapon's side. `size` is the casing's box (X, Y thickness; Z
## length). Returns the body used.
func eject(port: Transform3D, size: Vector3, color: Color, inherited_velocity: Vector3) -> RigidBody3D:
	if _bodies.is_empty():
		return null
	var index: int = _next
	_next = (_next + 1) % _bodies.size()
	var body: RigidBody3D = _bodies[index]

	_shapes[index].size = size.max(Vector3.ONE * 0.002)
	_meshes[index].scale = size
	var material: StandardMaterial3D = _material_for(color)
	_meshes[index].material_override = material
	body.mass = maxf(mass_per_metre * size.z, 0.002)

	# Unfreeze first: a frozen (static) body discards velocities set on it.
	body.freeze = false
	body.global_transform = Transform3D(port.basis.orthonormalized(), port.origin)
	var outward: Vector3 = port.basis.x.normalized()
	var up: Vector3 = port.basis.y.normalized()
	var back: Vector3 = port.basis.z.normalized()
	body.linear_velocity = inherited_velocity \
		+ outward * _rng.randf_range(eject_speed.x, eject_speed.y) \
		+ up * eject_lift \
		+ back * _rng.randf_range(-eject_scatter, eject_scatter) \
		+ up.cross(outward) * _rng.randf_range(-eject_scatter, eject_scatter)
	body.angular_velocity = Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).normalized() * eject_spin
	body.collision_layer = debris_layer
	body.collision_mask = collision_mask
	body.visible = true
	body.sleeping = false
	body.reset_physics_interpolation()
	_ages[index] = 0.0
	_active[index] = true
	return body


func active_count() -> int:
	return _active.count(true)


func get_bodies() -> Array[RigidBody3D]:
	return _bodies


func is_active(body: RigidBody3D) -> bool:
	var index: int = _bodies.find(body)
	return index >= 0 and _active[index]


func get_casing_size(body: RigidBody3D) -> Vector3:
	var index: int = _bodies.find(body)
	return _shapes[index].size if index >= 0 else Vector3.ZERO


## One shared material per distinct colour.
func _material_for(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.45
		material.metallic = 0.6
		_materials[color] = material
	return _materials[color]


func _park(index: int) -> void:
	var body: RigidBody3D = _bodies[index]
	body.freeze = true
	body.collision_layer = 0
	body.collision_mask = 0
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.visible = false
	_active[index] = false
