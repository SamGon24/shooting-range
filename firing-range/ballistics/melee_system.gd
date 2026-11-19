class_name MeleeSystem
extends Node3D
## One reusable shape cast reports contact through the existing hit signal.
var _cast: ShapeCast3D
var _sphere: SphereShape3D


func _ready() -> void:
	_sphere = SphereShape3D.new()
	_cast = ShapeCast3D.new()
	_cast.shape = _sphere
	_cast.enabled = false
	_cast.collision_mask = 1 | 8
	_cast.margin = 0.0
	add_child(_cast)


func swing(system: ProjectileSystem, origin: Vector3, direction: Vector3, data: ContactData, spec: ProjectileSpec, exclude: Array[RID] = []) -> int:
	if data == null or spec == null or direction.is_zero_approx():
		return -1
	var shot_id: int = system.begin_damage_event(spec.stats_eligible)
	var forward: Vector3 = direction.normalized()
	var radius: float = minf(data.radius_m, data.reach_m * 0.5)
	_sphere.radius = radius
	_cast.global_transform = Transform3D(Basis.IDENTITY, origin + forward * radius)
	_cast.target_position = forward * maxf(data.reach_m - 2.0 * radius, 0.0)
	_cast.max_results = data.max_results
	_cast.clear_exceptions()
	for rid: RID in exclude:
		_cast.add_exception_rid(rid)
	_cast.force_shapecast_update()
	var nearest: int = -1
	var distance: float = INF
	for index: int in _cast.get_collision_count():
		var candidate: float = origin.distance_to(_cast.get_collision_point(index))
		if candidate < distance:
			distance = candidate
			nearest = index
	if nearest >= 0:
		var hit := ProjectileHit.new()
		hit.shot_id = shot_id
		hit.source = DamageSource.Kind.MELEE
		hit.source_position = origin
		hit.position = _cast.get_collision_point(nearest)
		hit.normal = _cast.get_collision_normal(nearest)
		hit.collider = _cast.get_collider(nearest)
		hit.travel_distance = distance
		hit.spec = spec
		hit.damage = spec.damage
		hit.impulse_override = forward * data.impulse_n_s
		system.report_contact(hit)
	system.end_damage_event(shot_id)
	return shot_id
