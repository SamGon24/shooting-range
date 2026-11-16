class_name TargetDummy
extends Node3D
## Greybox humanoid: six non-overlapping colliders, one shared health state.

signal damaged(hit: ProjectileHit, zone: TargetSettings.Zone, amount: float)
signal killed
signal restored

@export var settings: TargetSettings = preload("res://targets/data/dummy_default.tres")
## -1 uses the Resource's count. Layout can select 0–3 without duplicating it.
@export_range(-1, 3) var armor_plates: int = -1

## Plates broken by the damage event currently being emitted.
var last_plate_breaks: int = 0
@export var ragdoll_enabled: bool = true
var ragdoll: DummyRagdoll
var _previous_position: Vector3
var _carrier_velocity: Vector3 = Vector3.ZERO
var state: TargetHealth
var zones: Array[TargetHitZone] = []
var _pivot: Node3D


func _ready() -> void:
	add_to_group(&"target_dummy")
	state = TargetHealth.new(settings, armor_plates)
	_pivot = Node3D.new()
	add_child(_pivot)
	_add_zone(TargetSettings.Zone.HEAD, Vector3(0.30, 0.30, 0.28), Vector3(0, 1.65, 0), Color(0.65, 0.65, 0.65))
	_add_zone(TargetSettings.Zone.TORSO, Vector3(0.48, 0.60, 0.28), Vector3(0, 1.18, 0), Color(0.48, 0.48, 0.48))
	for side: float in [-1.0, 1.0]:
		_add_zone(TargetSettings.Zone.LIMB, Vector3(0.16, 0.64, 0.22), Vector3(side * 0.35, 1.16, 0), Color(0.56, 0.56, 0.56))
		_add_zone(TargetSettings.Zone.LIMB, Vector3(0.19, 0.82, 0.24), Vector3(side * 0.14, 0.45, 0), Color(0.56, 0.56, 0.56))

	_previous_position = global_position
	ragdoll = DummyRagdoll.new()
	add_child(ragdoll)
	var transforms: Array[Transform3D] = []
	var shapes: Array[Shape3D] = []
	var meshes: Array[Mesh] = []
	for zone: TargetHitZone in zones:
		transforms.append(zone.global_transform)
		shapes.append((zone.get_child(0) as CollisionShape3D).shape)
		meshes.append((zone.get_child(1) as MeshInstance3D).mesh)
	ragdoll.setup(transforms, shapes, meshes, global_transform)


func _physics_process(delta: float) -> void:
	_carrier_velocity = (global_position - _previous_position) / delta
	_previous_position = global_position
	advance(delta)


func advance(delta: float) -> void:
	if state.advance(delta):
		ragdoll.deactivate()
		_pivot.visible = true
		_pivot.rotation.x = 0.0
		_set_hittable(true)
		reset_physics_interpolation()
		restored.emit()
	elif state.dead and not ragdoll.active:
		_pivot.rotation.x = -PI * 0.5 * clampf(state.down_time / settings.pop_seconds, 0.0, 1.0)


func receive_hit(hit: ProjectileHit, zone: TargetSettings.Zone) -> void:
	if state.dead:
		return
	var amount: float = hit.damage * settings.multiplier(zone, hit.spec)
	var plates_before: int = state.remaining_plates()
	state.apply_damage(amount)
	last_plate_breaks = plates_before - state.remaining_plates()
	damaged.emit(hit, zone, amount)
	if state.dead:
		_set_hittable(false)
		if ragdoll_enabled:
			var transforms: Array[Transform3D] = []
			for body: TargetHitZone in zones:
				transforms.append(body.global_transform)
			var index: int = zones.find(hit.collider)
			if index < 0:
				index = 0 if zone == TargetSettings.Zone.HEAD else 1
			ragdoll.activate(transforms, global_transform, hit, index, _carrier_velocity)
			_pivot.visible = false
		killed.emit()


func _set_hittable(enabled: bool) -> void:
	for zone: TargetHitZone in zones:
		zone.collision_layer = 1 if enabled else 0


func _add_zone(kind: TargetSettings.Zone, size: Vector3, centre: Vector3, color: Color) -> void:
	var body := TargetHitZone.new()
	body.name = ["Head", "Torso", "Limb"][kind]
	body.zone = kind
	body.dummy = self
	body.position = centre
	body.collision_layer = 1
	body.collision_mask = 0
	body.sync_to_physics = false
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	body.add_child(instance)
	_pivot.add_child(body, true)
	zones.append(body)
