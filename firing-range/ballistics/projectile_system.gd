class_name ProjectileSystem
extends Node3D
## Simulates every projectile in the world from one node.
##
## Projectiles are rows in packed arrays, not nodes: firing takes a free slot
## and never allocates. Each physics tick, every live projectile is integrated
## under gravity and air drag, and a ray is cast from its previous position to
## its new one, so a fast bullet cannot skip through a thin object between
## ticks.
##
## Weapons call `fire`. Effects, targets and debug tools listen to the signals.

signal projectile_fired(slot: int, origin: Vector3, velocity: Vector3, spec: ProjectileSpec)
signal projectile_hit(hit: ProjectileHit)
signal projectile_expired(slot: int)

const GROUP: StringName = &"projectile_system"

## Maximum projectiles alive at once. A shot fired when every slot is in use
## is dropped and counted in `get_dropped_count`.
@export_range(8, 1024) var capacity: int = 128
## Physics layers a projectile can hit.
@export_flags_3d_physics var collision_mask: int = 1
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
			hit.damage = spec.damage_at_distance(hit.travel_distance)
			hit.slot = slot
			_release(slot)
			projectile_hit.emit(hit)
			continue

		_positions[slot] = to
		_velocities[slot] = new_velocity
		_ages[slot] += delta
		_distances[slot] += from.distance_to(to)
		if _ages[slot] >= spec.max_lifetime:
			_release(slot)
			projectile_expired.emit(slot)


func get_active_count() -> int:
	return _active_count


## Shots that could not be fired because every slot was in use.
func get_dropped_count() -> int:
	return _dropped_count


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
