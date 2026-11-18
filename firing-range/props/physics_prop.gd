class_name PhysicsProp
extends RigidBody3D
## Bounded range prop. Only the existing projectile report supplies bullets.

enum Kind { CRATE, BARREL }
@export var kind: Kind = Kind.CRATE
@export var crate_mass: float = 8.0
@export var barrel_mass: float = 12.0
@export var crate_size: float = 0.65
@export var barrel_radius: float = 0.30
@export var barrel_height: float = 0.9
@export var push_force: float = 60.0
@export var return_radius: float = 30.0
var _home: Transform3D


func _ready() -> void:
	add_to_group(&"physics_prop")
	mass = crate_mass if kind == Kind.CRATE else barrel_mass
	collision_layer = 1
	collision_mask = 3
	linear_damp = 0.2
	angular_damp = 0.4
	var shape: Shape3D
	var mesh: PrimitiveMesh
	if kind == Kind.CRATE:
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * crate_size
		shape = box
		var box_mesh := BoxMesh.new()
		box_mesh.size = box.size
		mesh = box_mesh
	else:
		var cylinder := CylinderShape3D.new()
		cylinder.radius = barrel_radius
		cylinder.height = barrel_height
		shape = cylinder
		var cylinder_mesh := CylinderMesh.new()
		cylinder_mesh.top_radius = barrel_radius
		cylinder_mesh.bottom_radius = barrel_radius
		cylinder_mesh.height = barrel_height
		cylinder_mesh.radial_segments = 12
		mesh = cylinder_mesh
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.48, 0.36, 0.22) if kind == Kind.CRATE else Color(0.28, 0.36, 0.32)
	material.roughness = 0.85
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	add_child(instance)
	_home = global_transform


func receive_hit(hit: ProjectileHit) -> void:
	apply_impulse(hit.momentum(), hit.position - global_position)


func push(direction: Vector3, player_velocity: Vector3, contact: Vector3, delta: float) -> void:
	var horizontal: Vector3 = Vector3(direction.x, 0.0, direction.z).normalized()
	var closing: float = maxf(0.0, (player_velocity - linear_velocity).dot(horizontal))
	apply_impulse(horizontal * minf(push_force * delta, closing * mass), contact - global_position)


func _physics_process(_delta: float) -> void:
	if global_position.y < -10.0 or global_position.distance_to(_home.origin) > return_radius:
		global_transform = _home
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		reset_physics_interpolation()
