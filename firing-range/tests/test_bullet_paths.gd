extends GutTest
## The bullet-path debug view records what the ProjectileSystem simulated,
## and nothing while it is off.

const TICK: float = 1.0 / 60.0
const EYE: Vector3 = Vector3(0.0, 1.5, 0.0)

var _system: ProjectileSystem
var _paths: BulletPaths
var _spec: ProjectileSpec


func before_each() -> void:
	_spec = ProjectileSpec.new()
	_spec.muzzle_velocity = 850.0
	_spec.drag_coefficient = 0.3
	_spec.mass_grams = 4.0
	_spec.diameter_mm = 5.7
	_system = ProjectileSystem.new()
	add_child_autofree(_system)
	_system.set_physics_process(false)
	_paths = BulletPaths.new()
	add_child_autofree(_paths)
	_paths.set_physics_process(false)
	_paths.attach(_system)

	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20.0, 20.0, 1.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	body.position = Vector3(0.0, 0.0, -100.5)
	add_child_autofree(body)
	await wait_physics_frames(2)


func _step(ticks: int) -> void:
	for _tick: int in ticks:
		_system.advance(TICK)
		_paths.sample()


func test_records_each_tick_and_ends_at_the_impact() -> void:
	_paths.enabled = true
	_system.fire(EYE, Vector3.FORWARD, _spec)
	_step(3)
	assert_eq(_paths.get_live_count(), 1)
	_step(10)
	assert_eq(_paths.get_live_count(), 0)
	assert_eq(_paths.get_path_count(), 1)
	var points: PackedVector3Array = _paths.get_path_points(0)
	# Muzzle, 7 ticks in flight (under 100 m), then the impact point.
	assert_eq(points.size(), 9)
	assert_eq(points[0], EYE)
	assert_almost_eq(points[points.size() - 1].z, -100.0, 0.001, "ends on the wall face")
	var speeds: PackedFloat32Array = _paths.get_path_speeds(0)
	assert_eq(speeds[0], 1.0)
	assert_lt(speeds[speeds.size() - 1], 0.92, "drag slowed it by about 11% over 100 m")
	for i: int in speeds.size() - 1:
		assert_true(speeds[i + 1] < speeds[i], "speed only falls")
	_paths._rebuild()
	assert_eq(_paths.get_drawn_vertex_count(), 8 * 2 + 6, "eight segments and the impact cross")


func test_records_nothing_while_off() -> void:
	_system.fire(EYE, Vector3.FORWARD, _spec)
	_step(13)
	assert_eq(_paths.get_path_count(), 0)
	assert_eq(_paths.get_live_count(), 0)


func test_keeps_only_the_newest_paths() -> void:
	_paths.max_paths = 3
	_paths.enabled = true
	for _shot: int in 5:
		_system.fire(EYE, Vector3.FORWARD, _spec)
		_step(10)
	assert_eq(_paths.get_path_count(), 3)


func test_expired_bullets_finish_their_path() -> void:
	_paths.enabled = true
	_spec.max_lifetime = 0.05
	_system.fire(EYE, Vector3.UP, _spec)
	_step(5)
	assert_eq(_paths.get_path_count(), 1)
	assert_eq(_paths.get_live_count(), 0)


func test_drawing_does_not_change_hits() -> void:
	var hits: Array[Vector3] = []
	_system.projectile_hit.connect(func(hit: ProjectileHit) -> void: hits.append(hit.position))
	_system.fire(EYE, Vector3.FORWARD, _spec)
	_step(10)
	_paths.enabled = true
	_system.fire(EYE, Vector3.FORWARD, _spec)
	_step(10)
	_paths._rebuild()
	assert_eq(hits.size(), 2)
	if hits.size() == 2:
		assert_eq(hits[1], hits[0])
