class_name ProjectileSystem
extends Node3D
## Simulates every projectile in the world from one node.
##
## Projectiles are rows in packed arrays, not nodes: firing takes a free slot
## and never allocates a projectile node. Each physics tick, every live projectile is integrated
## under gravity and air drag, and a ray is cast from its previous position to
## its new one, so a fast bullet cannot skip through a thin object between
## ticks.
##
## Weapons call `fire`. Effects, targets and debug tools listen to the signals.

signal projectile_fired(slot: int, origin: Vector3, velocity: Vector3, spec: ProjectileSpec)
signal projectile_hit(hit: ProjectileHit)
signal projectile_expired(slot: int)
signal shot_started(shot_id: int)
signal shot_finished(shot_id: int)

const GROUP: StringName = &"projectile_system"

## Maximum projectiles alive at once. A shot fired when every slot is in use
## is dropped and counted in `get_dropped_count`.
@export_range(8, 1024) var capacity: int = 128
## Physics layers a projectile can hit.
@export_flags_3d_physics var collision_mask: int = 1 | 8
@export var collide_with_areas: bool = false
## Air density for drag, kg/m³. Sea level at 15 °C by default.
@export_range(0.0, 2.0, 0.001, "suffix:kg/m³") var air_density: float = ProjectileMath.SEA_LEVEL_AIR_DENSITY

var _gravity: float = 9.81
var _active: PackedByteArray = PackedByteArray()
var _positions: PackedVector3Array = PackedVector3Array()
var _velocities: PackedVector3Array = PackedVector3Array()
var _ages: PackedFloat32Array = PackedFloat32Array()
var _distances: PackedFloat32Array = PackedFloat32Array()
## Drag factor k (1/m) per slot, worked out once at launch.
var _drags: PackedFloat32Array = PackedFloat32Array()
var _specs: Array[ProjectileSpec] = []
var _shot_ids: PackedInt64Array = PackedInt64Array()
var _remaining: Dictionary[int, int] = {}
var _unscored: Dictionary[int, bool] = {}
var _next_shot_id: int = 0
var _free_slots: PackedInt32Array = PackedInt32Array()
var _active_count: int = 0
var _dropped_count: int = 0
var _query: PhysicsRayQueryParameters3D


func _ready() -> void:
	add_to_group(GROUP)
	# Run after weapons, so a shot fired this tick also moves this tick.
	process_physics_priority = 100
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))

	_active.resize(capacity)
	_positions.resize(capacity)
	_velocities.resize(capacity)
	_ages.resize(capacity)
	_distances.resize(capacity)
	_drags.resize(capacity)
	_specs.resize(capacity)
	_shot_ids.resize(capacity)
	_free_slots.resize(capacity)
	for slot: int in capacity:
		# Popped from the back, so slot 0 is handed out first.
		_free_slots[slot] = capacity - 1 - slot

	_query = PhysicsRayQueryParameters3D.new()
	_query.collision_mask = collision_mask
	_query.collide_with_areas = collide_with_areas


func _physics_process(delta: float) -> void:
	advance(delta)


## Launches a projectile from `origin` along `direction`. Returns its slot,
## or -1 if the pool is full.
func fire(origin: Vector3, direction: Vector3, spec: ProjectileSpec) -> int:
	if spec == null or direction.is_zero_approx():
		return -1
	if _free_slots.is_empty():
		_dropped_count += 1
		return -1
	return _launch(origin, direction, spec, _begin_shot(1, spec.stats_eligible))


## Atomic volley: either every pellet launches, or none does. Uses exactly
## the same pool, integration and collision sweep as a single projectile.
func fire_volley(origin: Vector3, directions: PackedVector3Array, spec: ProjectileSpec) -> int:
	if spec == null or directions.is_empty():
		return -1
	for direction: Vector3 in directions:
		if direction.is_zero_approx():
			return -1
	if _free_slots.size() < directions.size():
		_dropped_count += directions.size()
		return -1
	var shot_id: int = _begin_shot(directions.size(), spec.stats_eligible)
	var first_slot: int = -1
	for direction: Vector3 in directions:
		var slot: int = _launch(origin, direction, spec, shot_id)
		if first_slot < 0:
			first_slot = slot
	return first_slot


func _begin_shot(count: int, scoring: bool = true) -> int:
	_next_shot_id += 1
	_remaining[_next_shot_id] = count
	if not scoring:
		_unscored[_next_shot_id] = true
	shot_started.emit(_next_shot_id)
	return _next_shot_id


## Non-projectile deliveries share the same stats lifecycle and hit signal.
func begin_damage_event(scoring: bool = true) -> int:
	return _begin_shot(1, scoring)


func report_contact(hit: ProjectileHit) -> void:
	projectile_hit.emit(hit)


func end_damage_event(shot_id: int) -> void:
	_finish_projectile(shot_id)


func is_scoring_shot(shot_id: int) -> bool:
	return _remaining.has(shot_id) and not _unscored.has(shot_id)


func _launch(origin: Vector3, direction: Vector3, spec: ProjectileSpec, shot_id: int) -> int:

	var slot: int = _free_slots[_free_slots.size() - 1]
	_free_slots.remove_at(_free_slots.size() - 1)
	var velocity: Vector3 = direction.normalized() * spec.muzzle_velocity
	_active[slot] = 1
	_positions[slot] = origin
	_velocities[slot] = velocity
	_ages[slot] = 0.0
	_distances[slot] = 0.0
	_drags[slot] = spec.drag_factor(air_density)
	_specs[slot] = spec
	_shot_ids[slot] = shot_id
	_active_count += 1
	projectile_fired.emit(slot, origin, velocity, spec)
	return slot


## Moves every live projectile forward by `delta` seconds. Called once per
## physics tick; tests call it directly to step time by hand.
func advance(delta: float) -> void:
	if _active_count == 0:
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state

	for slot: int in capacity:
		if _active[slot] == 0:
			continue
		var spec: ProjectileSpec = _specs[slot]
		var shot_id: int = _shot_ids[slot]
		var gravity: Vector3 = Vector3.DOWN * (_gravity * spec.gravity_scale)
		var from: Vector3 = _positions[slot]
		var step: PackedVector3Array = ProjectileMath.step_drag(from, _velocities[slot], gravity, _drags[slot], delta)
		var to: Vector3 = step[0]
		var new_velocity: Vector3 = step[1]

		_query.from = from
		_query.to = to
		var result: Dictionary = space.intersect_ray(_query)
		if not result.is_empty():
			var point: Vector3 = result["position"]
			var hit := ProjectileHit.new()
			hit.position = point
			hit.normal = result["normal"]
			hit.collider = result["collider"]
			hit.velocity = new_velocity
			hit.travel_time = _ages[slot] + delta
			hit.travel_distance = _distances[slot] + from.distance_to(point)
			hit.spec = spec
			hit.source = spec.source
			hit.shot_id = shot_id
			hit.damage = spec.damage_at_distance(hit.travel_distance)
			hit.slot = slot
			_release(slot)
			projectile_hit.emit(hit)
			_finish_projectile(shot_id)
			continue

		_positions[slot] = to
		_velocities[slot] = new_velocity
		_ages[slot] += delta
		_distances[slot] += from.distance_to(to)
		if _ages[slot] >= spec.max_lifetime:
			_release(slot)
			projectile_expired.emit(slot)
			_finish_projectile(shot_id)


func get_active_count() -> int:
	return _active_count


## Shots that could not be fired because every slot was in use.
func get_dropped_count() -> int:
	return _dropped_count


func get_slot_shot_id(slot: int) -> int:
	return _shot_ids[slot] if is_slot_active(slot) else -1


func get_active_shot_count() -> int:
	return _remaining.size()


func _finish_projectile(shot_id: int) -> void:
	_remaining[shot_id] -= 1
	if _remaining[shot_id] == 0:
		_remaining.erase(shot_id)
		_unscored.erase(shot_id)
		shot_finished.emit(shot_id)


func is_slot_active(slot: int) -> bool:
	return slot >= 0 and slot < capacity and _active[slot] == 1


## Current position of a live projectile. Meaningless for a free slot.
func get_slot_position(slot: int) -> Vector3:
	return _positions[slot]


## Current velocity of a live projectile. Meaningless for a free slot.
func get_slot_velocity(slot: int) -> Vector3:
	return _velocities[slot]


func _release(slot: int) -> void:
	_active[slot] = 0
	_specs[slot] = null
	_free_slots.append(slot)
	_active_count -= 1
