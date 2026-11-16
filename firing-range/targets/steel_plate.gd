class_name SteelPlate
extends RigidBody3D
## A hanging plate constrained to a real Jolt hinge about its top edge.
## Only the existing projectile report can apply its bullet impulse.

signal rang

@export var plate_size: Vector3 = Vector3(0.6, 0.7, 0.06)
@export var plate_mass: float = 8.0
@export var impulse_scale: float = 1.0
@export var swing_limit_degrees: float = 65.0
@export var ring_volume_db: float = -4.0
@export var ring_unit_size: float = 60.0
## Projectile responsible for the ring event currently being emitted.
var last_hit: ProjectileHit
var hinge: HingeJoint3D
var _audio: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group(&"steel_plate")
	mass = plate_mass
	collision_layer = 1
	collision_mask = 1
	angular_damp = 0.5
	var shape := BoxShape3D.new()
	shape.size = plate_size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.27, 0.30, 0.33)
	material.metallic = 0.75
	material.roughness = 0.5
	var mesh := BoxMesh.new()
	mesh.size = plate_size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	add_child(instance)
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = SfxFactory.steel_ring()
	_audio.volume_db = ring_volume_db
	_audio.unit_size = ring_unit_size
	_audio.max_distance = 450.0
	add_child(_audio)
	# An unset second body anchors the joint to the world. Its local Z axis
	# becomes world X, letting the plate swing downrange instead of sideways.
	hinge = HingeJoint3D.new()
	hinge.position = position + Vector3.UP * plate_size.y * 0.5
	hinge.rotation.y = PI * 0.5
	get_parent().add_child(hinge)
	hinge.node_a = hinge.get_path_to(self)
	hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-swing_limit_degrees))
	hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(swing_limit_degrees))


func receive_hit(hit: ProjectileHit) -> void:
	var momentum: Vector3 = hit.velocity * (hit.spec.mass_grams * 0.001) * impulse_scale
	apply_impulse(momentum, hit.position - global_position)
	last_hit = hit
	_audio.play()
	rang.emit()
