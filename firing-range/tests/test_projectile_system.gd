extends GutTest
## ProjectileSystem against real Jolt colliders, stepped by hand so every
## test is deterministic to the tick.

const TICK: float = 1.0 / 60.0
const EYE: Vector3 = Vector3(0.0, 1.5, 0.0)
const DOWNRANGE: Vector3 = Vector3(0.0, 0.0, -1.0)

var _system: ProjectileSystem
var _spec: ProjectileSpec
var _hits: Array[ProjectileHit] = []
var _expired: Array[int] = []


func before_each() -> void:
	_hits.clear()
	_expired.clear()
	_spec = ProjectileSpec.new()
	_spec.muzzle_velocity = 900.0
	_system = ProjectileSystem.new()
	_system.capacity = 16
	add_child_autofree(_system)
	_system.set_physics_process(false)
	_system.projectile_hit.connect(func(hit: ProjectileHit) -> void: _hits.append(hit))
	_system.projectile_expired.connect(func(slot: int) -> void: _expired.append(slot))


## Adds a wall facing the shooter whose front face is `distance` metres away.
func _add_wall(distance: float, thickness: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20.0, 20.0, thickness)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	body.position = Vector3(0.0, 0.0, -distance - thickness * 0.5)
	add_child_autofree(body)
	return body


func _advance(ticks: int) -> void:
	for _tick: int in ticks:
		_system.advance(TICK)


# --- Swept raycast ---


func test_fast_bullet_hits_a_thin_wall_instead_of_passing_through() -> void:
	# 900 m/s covers 15 m per tick. The wall is 2 cm thick and sits in the
	# middle of the fourth step, so a point check at tick ends would miss it.
	var wall: StaticBody3D = _add_wall(52.0, 0.02)
	await wait_physics_frames(2)

	_system.fire(EYE, DOWNRANGE, _spec)
	_advance(3)
	assert_eq(_hits.size(), 0, "still short of the wall after 45 m")
	_advance(1)

	assert_eq(_hits.size(), 1, "hit on the tick that crosses the wall")
	if _hits.size() == 1:
		var hit: ProjectileHit = _hits[0]
		assert_almost_eq(hit.position.z, -52.0, 0.001, "impact is on the front face")
		assert_eq(hit.collider, wall)
		assert_almost_eq(hit.normal, Vector3(0.0, 0.0, 1.0), Vector3.ONE * 0.001, "normal faces the shooter")
		assert_almost_eq(hit.travel_distance, 52.0, 0.01)
		assert_almost_eq(hit.travel_time, 4.0 * TICK, 0.00001)
	assert_eq(_system.get_active_count(), 0, "the projectile is gone after the hit")

	_advance(10)
	assert_eq(_hits.size(), 1, "and never reports again")


func test_hits_a_wall_closer_than_one_tick_of_travel() -> void:
	_add_wall(3.0, 0.02)
	await wait_physics_frames(2)
	_system.fire(EYE, DOWNRANGE, _spec)
	_advance(1)
	assert_eq(_hits.size(), 1)
	if _hits.size() == 1:
		assert_almost_eq(_hits[0].position.z, -3.0, 0.001)


func test_gravity_drop_at_100_m_matches_the_analytic_value() -> void:
	_spec.muzzle_velocity = 850.0
	_add_wall(100.0, 1.0)
	await wait_physics_frames(2)
	_system.fire(EYE, DOWNRANGE, _spec)
	_advance(10)
	assert_eq(_hits.size(), 1)
	if _hits.size() == 1:
		var expected_drop: float = ProjectileMath.drop_at_distance(100.0, 850.0, 9.81)
		assert_almost_eq(EYE.y - _hits[0].position.y, expected_drop, 0.002, "6.8 cm of drop at 100 m")
		assert_lt(_hits[0].velocity.y, 0.0, "falling at impact")


func test_ignores_colliders_outside_the_collision_mask() -> void:
	var wall: StaticBody3D = _add_wall(20.0, 0.5)
	wall.collision_layer = 2
	await wait_physics_frames(2)
	_system.fire(EYE, DOWNRANGE, _spec)
	_advance(5)
	assert_eq(_hits.size(), 0, "layer 2 (the player's layer) is not hit")


# --- Pooling ---


func test_firing_does_not_create_nodes() -> void:
	var nodes_before: int = get_tree().get_node_count()
	var children_before: int = _system.get_child_count()
	for shot: int in 200:
		_system.fire(EYE, DOWNRANGE.rotated(Vector3.UP, float(shot) * 0.01), _spec)
		_system.advance(TICK)
	assert_eq(get_tree().get_node_count(), nodes_before, "no node per shot")
	assert_eq(_system.get_child_count(), children_before)


func test_slots_are_reused_after_projectiles_expire() -> void:
	_spec.max_lifetime = 0.05  # 3 ticks.
	var used: Dictionary[int, bool] = {}
	for _shot: int in 100:
		var slot: int = _system.fire(EYE, Vector3.UP, _spec)
		assert_ne(slot, -1, "a slot is always free because old shots expire")
		used[slot] = true
		_system.advance(TICK)
	assert_lte(used.size(), 4, "100 shots only ever needed a handful of slots")
	assert_eq(_system.get_dropped_count(), 0)


func test_a_full_pool_drops_the_shot_without_error() -> void:
	for _shot: int in _system.capacity:
		assert_ne(_system.fire(EYE, Vector3.UP, _spec), -1)
	assert_eq(_system.get_active_count(), _system.capacity)
	assert_eq(_system.fire(EYE, Vector3.UP, _spec), -1, "no free slot")
	assert_eq(_system.get_dropped_count(), 1)
	assert_eq(_system.get_active_count(), _system.capacity)


func test_projectile_expires_after_its_lifetime() -> void:
	_spec.max_lifetime = 0.5
	var slot: int = _system.fire(EYE, Vector3.UP, _spec)
	_advance(29)
	assert_true(_system.is_slot_active(slot), "alive just before 0.5 s")
	_advance(1)
	assert_false(_system.is_slot_active(slot), "gone at 0.5 s")
	assert_eq(_expired, [slot] as Array[int])
	assert_eq(_hits.size(), 0)


func test_fire_reports_the_muzzle_velocity() -> void:
	watch_signals(_system)
	var slot: int = _system.fire(EYE, Vector3(0.0, 0.0, -5.0), _spec)
	assert_signal_emitted(_system, "projectile_fired")
	assert_almost_eq(_system.get_slot_velocity(slot), Vector3(0.0, 0.0, -900.0), Vector3.ONE * 0.001, "direction is normalised")
	assert_eq(_system.get_slot_position(slot), EYE)


func test_rejects_a_missing_spec_or_zero_direction() -> void:
	assert_eq(_system.fire(EYE, DOWNRANGE, null), -1)
	assert_eq(_system.fire(EYE, Vector3.ZERO, _spec), -1)
	assert_eq(_system.get_active_count(), 0)
