class_name ExplosionSystem
extends Node3D
## Contact-triggered radial delivery. Targets retain all armor/health logic.

signal exploded(point: Vector3, data: ExplosionData)
const GROUP: StringName = &"explosion_system"
@export_range(16, 256) var max_candidates: int = 128
var _sphere: SphereShape3D
var _query: PhysicsShapeQueryParameters3D
var _visibility: PhysicsRayQueryParameters3D


func _ready() -> void:
	add_to_group(GROUP)
	_sphere = SphereShape3D.new()
	_query = PhysicsShapeQueryParameters3D.new()
	_query.shape = _sphere
	# World / live zones, existing corpses, and the shield layer.
	_query.collision_mask = 1 | 4 | 8
	_visibility = PhysicsRayQueryParameters3D.new()
	_visibility.collision_mask = 1 | 8


func detonate(hit: ProjectileHit) -> bool:
	var data: ExplosionData = hit.spec.explosion
	if data == null or not data.is_armed(hit.travel_distance):
		return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	_sphere.radius = data.radius_m
	_query.transform = Transform3D(Basis.IDENTITY, hit.position)
	var targets: Dictionary[int, TargetDummy] = {}
	var bodies: Dictionary[int, RigidBody3D] = {}
	for result: Dictionary in space.intersect_shape(_query, max_candidates):
		var collider: Object = result["collider"]
		if collider is TargetHitZone:
			var dummy: TargetDummy = (collider as TargetHitZone).dummy
			targets[dummy.get_instance_id()] = dummy
		elif collider is RigidBody3D:
			var body := collider as RigidBody3D
			bodies[body.get_instance_id()] = body
	var ray_origin: Vector3 = hit.position + hit.normal * data.surface_offset_m
	for dummy: TargetDummy in targets.values():
		if dummy.state.dead:
			continue
		var torso: TargetHitZone = dummy.zones[1]
		var distance: float = hit.position.distance_to(torso.global_position)
		var amount: float = data.damage_at_distance(distance)
		if amount <= 0.0 or not _visible(space, ray_origin, torso.global_position, dummy, data):
			continue
		var splash := ProjectileHit.new()
		splash.shot_id = hit.shot_id
		splash.spec = hit.spec
		splash.source = DamageSource.Kind.SPLASH
		splash.collider = torso
		splash.position = torso.global_position
		splash.normal = hit.normal
		splash.travel_time = hit.travel_time
		splash.travel_distance = hit.travel_distance
		splash.damage = amount
		# Zero contact momentum: the radial pass below supplies blast impulse
		# once, including bodies activated by this very killing hit.
		torso.receive_hit(splash)
		if dummy.ragdoll.active:
			for part: RigidBody3D in dummy.ragdoll.parts:
				bodies[part.get_instance_id()] = part
	for body: RigidBody3D in bodies.values():
		if body.freeze:
			continue
		var displacement: Vector3 = body.global_position - hit.position
		var impulse: Vector3 = data.impulse_at(displacement)
		if impulse.is_zero_approx() or not _visible(space, ray_origin, body.global_position, body, data):
			continue
		body.apply_impulse(impulse)
	exploded.emit(hit.position, data)
	return true


func _visible(space: PhysicsDirectSpaceState3D, origin: Vector3, point: Vector3, target: Object, data: ExplosionData) -> bool:
	if not data.occlusion or origin.is_equal_approx(point):
		return true
	_visibility.from = origin
	_visibility.to = point
	var result: Dictionary = space.intersect_ray(_visibility)
	if result.is_empty() or result["collider"] == target:
		return true
	var zone := result["collider"] as TargetHitZone
	return zone != null and zone.dummy == target
