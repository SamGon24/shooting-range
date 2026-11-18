class_name WeaponGuard
extends AnimatableBody3D
## One reusable shield collider follows fixed-tick gameplay aim.
var definition: GuardData
var _shape: BoxShape3D


func _ready() -> void:
	top_level = true
	sync_to_physics = false
	collision_layer = 0
	collision_mask = 0
	_shape = BoxShape3D.new()
	var collider := CollisionShape3D.new()
	collider.shape = _shape
	add_child(collider)


func configure(data: GuardData) -> void:
	if definition == data:
		return
	definition = data
	if data != null:
		_shape.size = data.size_m
	else:
		collision_layer = 0


func update_pose(eye: Vector3, aim: Basis, active: bool) -> void:
	var next_layer: int = definition.collision_layer if definition != null and active else 0
	if collision_layer != next_layer:
		collision_layer = next_layer
	if definition == null or not active:
		return
	var pose := Transform3D(aim, eye + aim * definition.eye_offset_m)
	if global_transform != pose:
		global_transform = pose
		force_update_transform()
