class_name MagazineDropPool
extends Node3D
## Physics copies of magazines released during reloads. Cosmetic only.
##
## A fixed number of rigid bodies is built once. Each release reuses the
## oldest body: it copies the released part's meshes (the native magazine
## plus any fitted magazine attachment), takes a box collider fitted around
## them, inherits the player's velocity, falls, settles and is put away
## again after `lifetime_s` of gameplay time. Nothing is allocated per
## reload.
##
## Bodies sit on their own debris layer and only scan the world layer, so
## projectiles, melee casts, blast queries, the player and ragdolls never
## see them. They can never change a hit or a stat.

const GROUP: StringName = &"magazine_drop_pool"

@export_range(1, 16) var capacity: int = 6
## Gameplay seconds before a dropped magazine is put away.
@export_range(0.5, 20.0, 0.1, "suffix:s") var lifetime_s: float = 4.0
@export_range(0.05, 3.0, 0.01, "suffix:kg") var mass_kg: float = 0.35
## Speed along the part's own down axis when it is let go.
@export_range(0.0, 5.0, 0.05, "suffix:m/s") var release_speed: float = 1.2
## Tumble around the part's own X axis when it is let go.
@export_range(0.0, 20.0, 0.1, "suffix:rad/s") var release_spin: float = 4.0
## Meshes copied per body: the native magazine plus fitted attachment parts.
@export_range(1, 8) var mesh_slots: int = 4
@export_flags_3d_physics var debris_layer: int = 16
@export_flags_3d_physics var collision_mask: int = 1

var _bodies: Array[RigidBody3D] = []
var _shapes: Array[BoxShape3D] = []
var _colliders: Array[CollisionShape3D] = []
var _slots: Array[Array] = []
var _ages: PackedFloat32Array = PackedFloat32Array()
var _active: Array[bool] = []
var _next: int = 0
var _scratch: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group(GROUP)
	var material := PhysicsMaterial.new()
	material.friction = 0.9
	material.bounce = 0.15
	for index: int in capacity:
		var body := RigidBody3D.new()
		body.name = "Drop%d" % index
		body.mass = mass_kg
		body.physics_material_override = material
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
		body.collision_layer = 0
		body.collision_mask = 0
		body.visible = false
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		var slots: Array[MeshInstance3D] = []
		for slot_index: int in mesh_slots:
			var slot := MeshInstance3D.new()
			slot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(slot)
			slots.append(slot)
		add_child(body)
		_bodies.append(body)
		_shapes.append(shape)
		_colliders.append(collider)
		_slots.append(slots)
		_ages.append(0.0)
		_active.append(false)


func _physics_process(delta: float) -> void:
	for index: int in _bodies.size():
		if not _active[index]:
			continue
		_ages[index] += delta
		if _ages[index] >= lifetime_s:
			_park(index)


## Drops a copy of `part` (and of the meshes under `follower`, if any) from
## where they are now. Returns the body used.
func release(part: Node3D, follower: Node3D, inherited_velocity: Vector3) -> RigidBody3D:
	if _bodies.is_empty() or part == null or not part.is_inside_tree():
		return null
	var index: int = _next
	_next = (_next + 1) % _bodies.size()
	var body: RigidBody3D = _bodies[index]

	_scratch.clear()
	if part is MeshInstance3D:
		_scratch.append(part as MeshInstance3D)
	if follower != null:
		_collect_meshes(follower)
	var origin: Transform3D = part.global_transform.orthonormalized()
	var inverse: Transform3D = origin.affine_inverse()
	var bounds := AABB()
	var slots: Array = _slots[index]
	for slot_index: int in slots.size():
		var slot: MeshInstance3D = slots[slot_index]
		if slot_index >= _scratch.size():
			slot.mesh = null
			continue
		var source: MeshInstance3D = _scratch[slot_index]
		slot.mesh = source.mesh
		slot.transform = inverse * source.global_transform
		var box: AABB = slot.transform * source.get_aabb()
		bounds = box if slot_index == 0 else bounds.merge(box)
	_shapes[index].size = bounds.size.max(Vector3.ONE * 0.01)
	_colliders[index].position = bounds.get_center()

	# Unfreeze first: a frozen (static) body discards velocities set on it.
	body.freeze = false
	body.global_transform = origin
	body.linear_velocity = inherited_velocity - origin.basis.y * release_speed
	body.angular_velocity = origin.basis.x * release_spin
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


func get_collision_size(body: RigidBody3D) -> Vector3:
	var index: int = _bodies.find(body)
	return _shapes[index].size if index >= 0 else Vector3.ZERO


func _collect_meshes(node: Node) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			_scratch.append(child as MeshInstance3D)
		_collect_meshes(child)


func _park(index: int) -> void:
	var body: RigidBody3D = _bodies[index]
	body.freeze = true
	body.collision_layer = 0
	body.collision_mask = 0
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.visible = false
	_active[index] = false
