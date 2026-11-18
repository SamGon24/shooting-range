class_name DummyRagdoll
extends Node3D
## Six prebuilt rigid parts and five angle-limited joints, reused for every
## dummy life. This top-level subtree stays in world space when its rail
## carrier moves.
##
## Each joint is a cone-twist whose twist axis runs along the limb it holds
## (up for the neck, down for shoulders and hips), so the swing limit is how
## far the limb may leave its hanging pose and the twist limit is how far it
## may roll about its own length.

## Physics layer of an active corpse part (layer 3).
const CORPSE_LAYER: int = 4
const ATTACHED_PARTS: PackedInt32Array = [0, 2, 3, 4, 5]
const ANCHORS: Array[Vector3] = [Vector3(0,1.49,0), Vector3(-0.27,1.43,0), Vector3(-0.14,0.88,0), Vector3(0.27,1.43,0), Vector3(0.14,0.88,0)]
## Direction each joint's twist axis takes in the dummy's frame: the neck
## points up toward the head, the others down along the limb.
const AXES: Array[Vector3] = [Vector3.UP, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN]
@export var part_masses: PackedFloat32Array = PackedFloat32Array([4,24,3,8,3,8])
@export var impulse_scale: float = 1.0
@export var part_linear_damp: float = 0.25
@export var part_angular_damp: float = 1.0
## Per joint, in the order of `ATTACHED_PARTS`: neck, left arm, left leg,
## right arm, right leg. Swing is the half-angle of the cone the limb may
## leave its hanging pose by; twist is the roll either way about its length.
@export var swing_limit_degrees: PackedFloat32Array = PackedFloat32Array([40.0, 85.0, 55.0, 85.0, 55.0])
@export var twist_limit_degrees: PackedFloat32Array = PackedFloat32Array([50.0, 45.0, 30.0, 45.0, 30.0])
var parts: Array[RigidBody3D] = []
var _joints: Array[ConeTwistJoint3D] = []
var active: bool = false


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	visible = false


func setup(transforms: Array[Transform3D], shapes: Array[Shape3D], meshes: Array[Mesh], owner_transform: Transform3D) -> void:
	for index: int in transforms.size():
		var body := RagdollPart.new()
		body.ragdoll = self
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
		var joint := ConeTwistJoint3D.new()
		joint.swing_span = deg_to_rad(swing_limit_degrees[index])
		joint.twist_span = deg_to_rad(twist_limit_degrees[index])
		add_child(joint)
		_place_joint(joint, index, owner_transform)
		_joints.append(joint)


func activate(transforms: Array[Transform3D], owner_transform: Transform3D, hit: ProjectileHit, part_index: int, carrier_velocity: Vector3) -> void:
	for index: int in parts.size():
		var part: RigidBody3D = parts[index]
		part.global_transform = transforms[index]
		part.reset_physics_interpolation()
		# Layer 4 is in the projectile mask, so bullets stop on a corpse and
		# push it. It collides with world and props only, never the player or
		# other corpses.
		part.collision_layer = CORPSE_LAYER
		part.collision_mask = 1
		part.freeze = false
		part.linear_velocity = carrier_velocity
		part.angular_velocity = Vector3.ZERO
		part.sleeping = false
	for index: int in _joints.size():
		_place_joint(_joints[index], index, owner_transform)
		_joints[index].node_a = _joints[index].get_path_to(parts[1])
		_joints[index].node_b = _joints[index].get_path_to(parts[ATTACHED_PARTS[index]])
	visible = true
	active = true
	var part: RigidBody3D = parts[clampi(part_index, 0, parts.size() - 1)]
	part.apply_impulse(hit.momentum() * impulse_scale, hit.position - part.global_position)


## Puts a joint on its anchor with its twist axis (local X) along the limb.
func _place_joint(joint: ConeTwistJoint3D, index: int, owner_transform: Transform3D) -> void:
	var axis: Vector3 = AXES[index]
	var side: Vector3 = Vector3.LEFT if axis == Vector3.UP else Vector3.RIGHT
	var frame := Basis(axis, side, axis.cross(side))
	joint.global_transform = Transform3D(owner_transform.basis * frame, owner_transform * ANCHORS[index])


func deactivate() -> void:
	for joint: ConeTwistJoint3D in _joints:
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
