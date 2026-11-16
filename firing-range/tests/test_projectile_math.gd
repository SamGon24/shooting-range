extends GutTest
## Pure projectile integration, gravity only.

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
