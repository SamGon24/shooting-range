extends GutTest
## Pure projectile integration: the exact gravity-only step, and the RK4
## drag step checked against the flat-fire analytic solution.

const TICK: float = 1.0 / 60.0
const GRAVITY: Vector3 = Vector3(0.0, -9.81, 0.0)


func _simulate(position: Vector3, velocity: Vector3, seconds: float, tick: float) -> Array[Vector3]:
	var steps: int = roundi(seconds / tick)
	for _step: int in steps:
		position = ProjectileMath.step_position(position, velocity, GRAVITY, tick)
		velocity = ProjectileMath.step_velocity(velocity, GRAVITY, tick)
	return [position, velocity]


func test_position_matches_the_analytic_parabola() -> void:
	var start := Vector3(0.0, 1.5, 0.0)
	var velocity := Vector3(0.0, 20.0, -850.0)
	var state: Array[Vector3] = _simulate(start, velocity, 0.5, TICK)
	var expected: Vector3 = start + velocity * 0.5 + GRAVITY * (0.5 * 0.5 * 0.5)
	assert_almost_eq(state[0], expected, Vector3.ONE * 0.0001)
	assert_almost_eq(state[1], velocity + GRAVITY * 0.5, Vector3.ONE * 0.0001)


func test_result_does_not_depend_on_tick_rate() -> void:
	var start := Vector3(0.0, 1.5, 0.0)
	var velocity := Vector3(0.0, 0.0, -900.0)
	var at_60: Array[Vector3] = _simulate(start, velocity, 0.3, 1.0 / 60.0)
	var at_240: Array[Vector3] = _simulate(start, velocity, 0.3, 1.0 / 240.0)
	assert_almost_eq(at_60[0], at_240[0], Vector3.ONE * 0.0001)


func test_no_acceleration_is_a_straight_line() -> void:
	var position: Vector3 = ProjectileMath.step_position(Vector3.ZERO, Vector3(0.0, 0.0, -900.0), Vector3.ZERO, TICK)
	assert_almost_eq(position, Vector3(0.0, 0.0, -15.0), Vector3.ONE * 0.00001)


func test_drop_at_distance() -> void:
	# 850 m/s: 100 m takes 0.1176 s and falls 6.8 cm; 300 m falls 61 cm.
	assert_almost_eq(ProjectileMath.drop_at_distance(100.0, 850.0, 9.81), 0.0679, 0.0001)
	assert_almost_eq(ProjectileMath.drop_at_distance(300.0, 850.0, 9.81), 0.6110, 0.0001)
	assert_almost_eq(ProjectileMath.time_to_distance(300.0, 900.0), 1.0 / 3.0, 0.00001)


func test_simulated_drop_matches_drop_at_distance() -> void:
	# A level shot stepped for 6 ticks (0.1 s) covers exactly 85 m at 850 m/s.
	var state: Array[Vector3] = _simulate(Vector3.ZERO, Vector3(0.0, 0.0, -850.0), 0.1, TICK)
	assert_almost_eq(-state[0].z, 85.0, 0.0001)
	assert_almost_eq(-state[0].y, ProjectileMath.drop_at_distance(85.0, 850.0, 9.81), 0.0001)


# --- Drag ---


## Drag factors of the two weapons' bullets (see weapons/data/*.tres).
const RIFLE_DRAG: float = 0.0011722
const SNIPER_DRAG: float = 0.0007287


## Fires level along -Z from the origin, steps with drag and returns
## [drop, time, speed] where the path crosses `distance` metres downrange,
## interpolated between the two ticks either side.
func _drag_shot(speed: float, drag: float, distance: float, tick: float) -> PackedFloat64Array:
	var position := Vector3.ZERO
	var velocity := Vector3(0.0, 0.0, -speed)
	var time: float = 0.0
	while true:
		var step: PackedVector3Array = ProjectileMath.step_drag(position, velocity, GRAVITY, drag, tick)
		if -step[0].z >= distance:
			var t: float = (distance + position.z) / (position.z - step[0].z)
			return PackedFloat64Array([
				-lerpf(position.y, step[0].y, t),
				time + tick * t,
				velocity.lerp(step[1], t).length(),
			])
		position = step[0]
		velocity = step[1]
		time += tick
	return PackedFloat64Array()


func test_drag_factor_from_bullet_size_and_mass() -> void:
	var spec := ProjectileSpec.new()
	spec.drag_coefficient = 0.30
	spec.mass_grams = 4.0
	spec.diameter_mm = 5.7
	assert_almost_eq(spec.drag_factor(ProjectileMath.SEA_LEVEL_AIR_DENSITY), RIFLE_DRAG, 0.0000001)
	spec.drag_coefficient = 0.0
	assert_eq(spec.drag_factor(ProjectileMath.SEA_LEVEL_AIR_DENSITY), 0.0, "Cd 0 turns drag off")


func test_zero_drag_step_is_the_exact_parabola() -> void:
	var step: PackedVector3Array = ProjectileMath.step_drag(Vector3.ZERO, Vector3(0.0, 0.0, -850.0), GRAVITY, 0.0, 0.5)
	assert_almost_eq(step[0], Vector3(0.0, -9.81 * 0.125, -425.0), Vector3.ONE * 0.00001)
	assert_almost_eq(step[1], Vector3(0.0, -4.905, -850.0), Vector3.ONE * 0.00001)


func test_drag_with_no_gravity_matches_exponential_speed_decay() -> void:
	# Without gravity the shot is one-dimensional and v(x) = v0 * e^(-k x)
	# is exact, so this checks RK4 alone.
	var position := Vector3.ZERO
	var velocity := Vector3(0.0, 0.0, -850.0)
	for _step: int in 30:
		var step: PackedVector3Array = ProjectileMath.step_drag(position, velocity, Vector3.ZERO, RIFLE_DRAG, TICK)
		position = step[0]
		velocity = step[1]
	var expected: float = ProjectileMath.speed_at_distance(-position.z, 850.0, RIFLE_DRAG)
	assert_almost_eq(velocity.length(), expected, 0.001)
	assert_almost_eq(ProjectileMath.time_to_distance(-position.z, 850.0, RIFLE_DRAG), 0.5, 0.00001)


func test_rifle_drop_with_drag_matches_the_analytic_values() -> void:
	# 850 m/s, 4 g, 5.7 mm, Cd 0.30: 7.3 cm at 100 m, 32 cm at 200 m and
	# 78 cm at 300 m, against 6.8 / 27 / 61 cm in a vacuum.
	for distance: float in [100.0, 200.0, 300.0]:
		var shot: PackedFloat64Array = _drag_shot(850.0, RIFLE_DRAG, distance, TICK)
		var drop: float = ProjectileMath.drop_at_distance(distance, 850.0, 9.81, RIFLE_DRAG)
		assert_almost_eq(shot[0], drop, 0.002, "drop at %d m" % distance)
		assert_almost_eq(shot[1], ProjectileMath.time_to_distance(distance, 850.0, RIFLE_DRAG), 0.0001, "time at %d m" % distance)
		assert_almost_eq(shot[2], ProjectileMath.speed_at_distance(distance, 850.0, RIFLE_DRAG), 0.1, "speed at %d m" % distance)
	assert_almost_eq(ProjectileMath.drop_at_distance(300.0, 850.0, 9.81, RIFLE_DRAG), 0.7834, 0.0001)
	assert_almost_eq(ProjectileMath.speed_at_distance(300.0, 850.0, RIFLE_DRAG), 598.0, 0.1)


func test_sniper_drop_with_drag_matches_the_analytic_values() -> void:
	# 900 m/s, 10.9 g, 7.82 mm, Cd 0.27: 6.4 / 27 / 63 cm at 100 / 200 / 300 m.
	for distance: float in [100.0, 200.0, 300.0]:
		var shot: PackedFloat64Array = _drag_shot(900.0, SNIPER_DRAG, distance, TICK)
		var drop: float = ProjectileMath.drop_at_distance(distance, 900.0, 9.81, SNIPER_DRAG)
		assert_almost_eq(shot[0], drop, 0.002, "drop at %d m" % distance)
		assert_almost_eq(shot[1], ProjectileMath.time_to_distance(distance, 900.0, SNIPER_DRAG), 0.0001, "time at %d m" % distance)
	assert_almost_eq(ProjectileMath.drop_at_distance(300.0, 900.0, 9.81, SNIPER_DRAG), 0.6339, 0.0001)


func test_drag_result_barely_depends_on_tick_rate() -> void:
	var at_60: PackedFloat64Array = _drag_shot(850.0, RIFLE_DRAG, 300.0, 1.0 / 60.0)
	var at_240: PackedFloat64Array = _drag_shot(850.0, RIFLE_DRAG, 300.0, 1.0 / 240.0)
	assert_almost_eq(at_60[0], at_240[0], 0.001, "drop within a millimetre")
	assert_almost_eq(at_60[2], at_240[2], 0.01, "speed within 1 cm/s")


func test_zero_drag_analytic_functions_match_the_vacuum_ones() -> void:
	assert_eq(ProjectileMath.time_to_distance(300.0, 900.0, 0.0), 300.0 / 900.0)
	assert_eq(ProjectileMath.speed_at_distance(300.0, 900.0, 0.0), 900.0)
	assert_almost_eq(ProjectileMath.drop_at_distance(300.0, 850.0, 9.81, 0.0), 0.6110, 0.0001)
