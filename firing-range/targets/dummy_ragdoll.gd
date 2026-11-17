class_name DummyRagdoll
extends Node3D
## Six prebuilt rigid parts and five pins, reused for every dummy life.
## This top-level subtree stays in world space when its rail carrier moves.

const ATTACHED_PARTS: PackedInt32Array = [0, 2, 3, 4, 5]
const ANCHORS: Array[Vector3] = [Vector3(0,1.49,0), Vector3(-0.27,1.43,0), Vector3(-0.14,0.88,0), Vector3(0.27,1.43,0), Vector3(0.14,0.88,0)]
@export var part_masses: PackedFloat32Array = PackedFloat32Array([4,24,3,8,3,8])
@export var impulse_scale: float = 1.0
@export var part_linear_damp: float = 0.25
@export var part_angular_damp: float = 1.0
var parts: Array[RigidBody3D] = []
var _joints: Array[PinJoint3D] = []
var active: bool = false


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	visible = false


func setup(transforms: Array[Transform3D], shapes: Array[Shape3D], meshes: Array[Mesh], owner_transform: Transform3D) -> void:
	for index: int in transforms.size():
		var body := RigidBody3D.new()
		body.mass = part_masses[index]
		body.freeze = true
		body.collision_layer = 0
		body.collision_mask = 0
		body.linear_damp = part_linear_damp
		body.angular_damp = part_angular_damp
		var collider := CollisionShape3D.new()
		collider.shape = shapes[index]
		body.add_child(collider)
		var instance := MeshInstance3D.new()
		instance.mesh = meshes[index]
		body.add_child(instance)
		add_child(body)
		body.global_transform = transforms[index]
		parts.append(body)
	for index: int in ATTACHED_PARTS.size():
		var joint := PinJoint3D.new()
		add_child(joint)
		joint.global_position = owner_transform * ANCHORS[index]
		_joints.append(joint)


func activate(transforms: Array[Transform3D], owner_transform: Transform3D, hit: ProjectileHit, part_index: int, carrier_velocity: Vector3) -> void:
	for index: int in parts.size():
		var part: RigidBody3D = parts[index]
		part.global_transform = transforms[index]
		part.reset_physics_interpolation()
		part.collision_layer = 4
		# Collide with world and props, excluding bullets, player and corpses.
		part.collision_mask = 1
		part.freeze = false
		part.linear_velocity = carrier_velocity
		part.angular_velocity = Vector3.ZERO
		part.sleeping = false
	for index: int in _joints.size():
		_joints[index].global_position = owner_transform * ANCHORS[index]
		_joints[index].node_a = _joints[index].get_path_to(parts[1])
		_joints[index].node_b = _joints[index].get_path_to(parts[ATTACHED_PARTS[index]])
	visible = true
	active = true
	var part: RigidBody3D = parts[clampi(part_index, 0, parts.size() - 1)]
	part.apply_impulse(hit.momentum() * impulse_scale, hit.position - part.global_position)


func deactivate() -> void:
	for joint: PinJoint3D in _joints:
		joint.node_b = NodePath()
		joint.node_a = NodePath()
	for part: RigidBody3D in parts:
		part.freeze = true
		part.collision_layer = 0
		part.collision_mask = 0
		part.linear_velocity = Vector3.ZERO
		part.angular_velocity = Vector3.ZERO
	visible = false
	active = false
