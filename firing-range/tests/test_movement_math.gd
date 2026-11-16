extends GutTest
## Unit tests for the pure movement math: acceleration, friction, air control,
## slide decay and jump velocity. No nodes or physics involved.

const TICK: float = 1.0 / 60.0
const FORWARD: Vector3 = Vector3(0.0, 0.0, -1.0)
const RIGHT: Vector3 = Vector3(1.0, 0.0, 0.0)

var _settings: MovementSettings


func before_all() -> void:
	_settings = load("res://player/data/movement_default.tres") as MovementSettings


## Runs `ground_move` for `seconds` at the given tick length.
func _run_ground(start: Vector3, wish_dir: Vector3, wish_speed: float, seconds: float, tick: float = TICK) -> Vector3:
	var velocity: Vector3 = start
	var steps: int = roundi(seconds / tick)
	for _step: int in steps:
		velocity = MovementMath.ground_move(
			velocity,
			wish_dir,
			wish_speed,
			_settings.ground_accel,
			_settings.ground_friction,
			_settings.stop_speed,
			tick
		)
	return velocity


# --- Settings sanity ---


func test_default_settings_load() -> void:
	assert_not_null(_settings, "movement_default.tres loads as MovementSettings")


func test_default_settings_are_consistent() -> void:
	assert_gt(_settings.sprint_speed, _settings.walk_speed, "sprint is faster than walk")
	assert_gt(_settings.walk_speed, _settings.crouch_speed, "walk is faster than crouch")
	assert_gt(_settings.ground_accel, _settings.ground_friction, "accel must beat friction to reach target speed")
	assert_gt(_settings.slide_min_entry_speed, _settings.walk_speed, "walking speed alone cannot start a slide")
	assert_lte(_settings.slide_min_entry_speed, _settings.sprint_speed, "sprinting can start a slide")
	assert_gt(_settings.slide_min_entry_speed, _settings.slide_end_speed, "a slide does not end the moment it starts")
	assert_gt(_settings.stand_height, _settings.crouch_height, "crouching is lower than standing")
	assert_gte(_settings.crouch_height, _settings.capsule_radius * 2.0, "capsule height is at least its diameter")


func test_target_speed_by_state() -> void:
	assert_eq(_settings.target_speed(false, false), _settings.walk_speed)
	assert_eq(_settings.target_speed(false, true), _settings.sprint_speed)
	assert_eq(_settings.target_speed(true, false), _settings.crouch_speed)
	assert_eq(_settings.target_speed(true, true), _settings.crouch_speed, "crouch wins over sprint")


# --- Acceleration ---


func test_accelerate_from_rest_gains_accel_times_wish_speed_per_tick() -> void:
	var velocity: Vector3 = MovementMath.accelerate(Vector3.ZERO, FORWARD, 4.5, 9.0, TICK)
	assert_almost_eq(velocity.z, -9.0 * 4.5 * TICK, 0.00001)
	assert_almost_eq(velocity.x, 0.0, 0.00001)


func test_accelerate_does_not_snap_to_target_speed() -> void:
	var velocity: Vector3 = MovementMath.accelerate(Vector3.ZERO, FORWARD, 4.5, 9.0, TICK)
	assert_lt(MovementMath.horizontal_speed(velocity), 4.5 * 0.25, "one tick is nowhere near full speed")


func test_accelerate_never_exceeds_wish_speed() -> void:
	var velocity := Vector3.ZERO
	for _step: int in 600:
		velocity = MovementMath.accelerate(velocity, FORWARD, 4.5, 9.0, TICK)
		assert_lte(MovementMath.horizontal_speed(velocity), 4.5 + 0.00001)
	assert_almost_eq(MovementMath.horizontal_speed(velocity), 4.5, 0.00001, "and it gets there exactly")


func test_accelerate_ignores_zero_wish() -> void:
	var start := Vector3(1.0, 2.0, 3.0)
	assert_eq(MovementMath.accelerate(start, Vector3.ZERO, 4.5, 9.0, TICK), start)
	assert_eq(MovementMath.accelerate(start, FORWARD, 0.0, 9.0, TICK), start)


func test_accelerate_leaves_vertical_velocity_alone() -> void:
	var velocity: Vector3 = MovementMath.accelerate(Vector3(0.0, -3.0, 0.0), FORWARD, 4.5, 9.0, TICK)
	assert_eq(velocity.y, -3.0)


func test_accelerate_ignores_vertical_part_of_wish_direction() -> void:
	var tilted := Vector3(0.0, 5.0, -1.0)
	var velocity: Vector3 = MovementMath.accelerate(Vector3.ZERO, tilted, 4.5, 9.0, TICK)
	assert_eq(velocity.y, 0.0, "looking up never adds vertical speed")
	assert_almost_eq(velocity.z, -9.0 * 4.5 * TICK, 0.00001)


func test_accelerate_does_nothing_when_already_at_wish_speed_in_that_direction() -> void:
	var start: Vector3 = FORWARD * 6.0
	assert_eq(MovementMath.accelerate(start, FORWARD, 4.5, 9.0, TICK), start, "it never brakes; friction does that")


# --- Friction ---


func test_friction_reduces_speed_and_keeps_direction() -> void:
	var start := Vector3(3.0, 0.0, -4.0)
	var velocity: Vector3 = MovementMath.apply_friction(start, 6.0, 2.5, TICK)
	assert_lt(MovementMath.horizontal_speed(velocity), 5.0)
	assert_almost_eq(velocity.normalized().dot(start.normalized()), 1.0, 0.00001)


func test_friction_is_exponential_above_stop_speed() -> void:
	var velocity := Vector3(0.0, 0.0, -7.0)
	# 0.1 s from 7 m/s stays above the 2.5 m/s stop speed, so pure exp decay.
	for _step: int in 6:
		velocity = MovementMath.apply_friction(velocity, 6.0, 2.5, TICK)
	assert_almost_eq(MovementMath.horizontal_speed(velocity), 7.0 * exp(-6.0 * 0.1), 0.0001)


func test_friction_is_linear_below_stop_speed() -> void:
	var velocity: Vector3 = MovementMath.apply_friction(Vector3(2.0, 0.0, 0.0), 6.0, 2.5, TICK)
	assert_almost_eq(velocity.x, 2.0 - 2.5 * 6.0 * TICK, 0.00001)


func test_friction_stops_exactly_and_never_reverses() -> void:
	var velocity := Vector3(0.0, 0.0, -4.5)
	for _step: int in 120:
		velocity = MovementMath.apply_friction(velocity, 6.0, 2.5, TICK)
		assert_lte(velocity.z, 0.0, "never flips direction")
	assert_eq(MovementMath.horizontal_speed(velocity), 0.0)


func test_friction_stop_time_matches_analytic() -> void:
	# From v0 > stop_speed: exponential down to stop_speed, then linear to 0.
	var v0: float = 4.5
	var expected: float = log(v0 / 2.5) / 6.0 + 1.0 / 6.0
	var velocity := Vector3(v0, 0.0, 0.0)
	var elapsed: float = 0.0
	while MovementMath.horizontal_speed(velocity) > 0.0 and elapsed < 5.0:
		velocity = MovementMath.apply_friction(velocity, 6.0, 2.5, TICK)
		elapsed += TICK
	assert_almost_eq(elapsed, expected, TICK, "stops within one tick of the analytic time")


func test_friction_is_tick_rate_independent() -> void:
	var at_60 := Vector3(0.0, 0.0, -7.0)
	var at_240 := Vector3(0.0, 0.0, -7.0)
	for _step: int in 12:
		at_60 = MovementMath.apply_friction(at_60, 6.0, 2.5, 1.0 / 60.0)
	for _step: int in 48:
		at_240 = MovementMath.apply_friction(at_240, 6.0, 2.5, 1.0 / 240.0)
	assert_almost_eq(at_60.z, at_240.z, 0.0001, "0.2 s of friction gives the same speed at 60 and 240 Hz")


func test_friction_leaves_vertical_velocity_alone() -> void:
	var velocity: Vector3 = MovementMath.apply_friction(Vector3(3.0, -9.0, 0.0), 6.0, 2.5, TICK)
	assert_eq(velocity.y, -9.0)


func test_friction_with_zero_friction_is_a_no_op() -> void:
	var start := Vector3(3.0, 0.0, 1.0)
	assert_eq(MovementMath.apply_friction(start, 0.0, 2.5, TICK), start)


# --- Ground move (friction + acceleration together) ---


func test_ground_move_settles_at_exactly_wish_speed() -> void:
	var velocity: Vector3 = _run_ground(Vector3.ZERO, FORWARD, _settings.walk_speed, 2.0)
	assert_almost_eq(MovementMath.horizontal_speed(velocity), _settings.walk_speed, 0.0001)
	assert_almost_eq(velocity.x, 0.0, 0.0001)


func test_ground_move_takes_time_to_reach_walk_speed() -> void:
	var early: Vector3 = _run_ground(Vector3.ZERO, FORWARD, _settings.walk_speed, 0.05)
	assert_lt(MovementMath.horizontal_speed(early), _settings.walk_speed * 0.6, "still accelerating after 50 ms")
	var later: Vector3 = _run_ground(Vector3.ZERO, FORWARD, _settings.walk_speed, 0.5)
	assert_almost_eq(MovementMath.horizontal_speed(later), _settings.walk_speed, 0.0001, "at speed within 0.5 s")


func test_ground_move_never_overshoots_wish_speed_from_rest() -> void:
	var velocity := Vector3.ZERO
	for _step: int in 180:
		velocity = _run_ground(velocity, FORWARD, _settings.sprint_speed, TICK)
		assert_lte(MovementMath.horizontal_speed(velocity), _settings.sprint_speed + 0.0001)


func test_ground_move_reversing_direction_carries_momentum() -> void:
	var velocity: Vector3 = FORWARD * _settings.walk_speed
	velocity = _run_ground(velocity, -FORWARD, _settings.walk_speed, TICK)
	assert_lt(velocity.z, 0.0, "still moving forward one tick after reversing input")
	velocity = _run_ground(velocity, -FORWARD, _settings.walk_speed, 1.0)
	assert_almost_eq(velocity.z, _settings.walk_speed, 0.0001, "and fully reversed a second later")


func test_ground_move_coasts_to_a_stop_without_input() -> void:
	var velocity: Vector3 = FORWARD * _settings.sprint_speed
	velocity = _run_ground(velocity, Vector3.ZERO, 0.0, 3.0 * TICK)
	assert_gt(MovementMath.horizontal_speed(velocity), 0.0, "does not stop dead")
	velocity = _run_ground(velocity, Vector3.ZERO, 0.0, 1.0)
	assert_eq(MovementMath.horizontal_speed(velocity), 0.0)


func test_ground_move_sheds_sideways_momentum_when_turning() -> void:
	var velocity: Vector3 = RIGHT * _settings.walk_speed
	velocity = _run_ground(velocity, FORWARD, _settings.walk_speed, 0.1)
	assert_gt(velocity.x, 1.0, "sideways momentum is still there after 0.1 s")
	velocity = _run_ground(velocity, FORWARD, _settings.walk_speed, 0.9)
	# Sideways speed decays as exp(-friction * t): about 1 cm/s left after 1 s.
	assert_almost_eq(velocity.x, 0.0, 0.02)
	assert_almost_eq(MovementMath.horizontal_speed(velocity), _settings.walk_speed, 0.001)


func test_ground_move_never_exceeds_wish_speed_while_turning() -> void:
	# Start at full sprint, then swing the wish direction around hard.
	var velocity: Vector3 = FORWARD * _settings.sprint_speed
	for step: int in 240:
		var wish: Vector3 = FORWARD.rotated(Vector3.UP, deg_to_rad(float(step) * 7.0))
		velocity = MovementMath.ground_move(
			velocity,
			wish,
			_settings.sprint_speed,
			_settings.ground_accel,
			_settings.ground_friction,
			_settings.stop_speed,
			TICK
		)
		assert_lte(MovementMath.horizontal_speed(velocity), _settings.sprint_speed + 0.0001)


func test_ground_move_is_close_at_60_and_120_hz() -> void:
	# Friction is exact, but the acceleration step is not, so allow a little.
	var at_60: Vector3 = _run_ground(Vector3.ZERO, FORWARD, _settings.sprint_speed, 0.1, 1.0 / 60.0)
	var at_120: Vector3 = _run_ground(Vector3.ZERO, FORWARD, _settings.sprint_speed, 0.1, 1.0 / 120.0)
	assert_almost_eq(at_60.z, at_120.z, _settings.sprint_speed * 0.05)


# --- Capped acceleration (air control and slide steering) ---


func test_raw_accelerate_overshoots_when_turning_but_capped_does_not() -> void:
	# Documents why gameplay uses the capped version.
	var start: Vector3 = FORWARD * 7.0
	var diagonal: Vector3 = (FORWARD + RIGHT).normalized()
	var raw: Vector3 = MovementMath.accelerate(start, diagonal, 7.0, 9.0, TICK)
	var capped: Vector3 = MovementMath.accelerate_capped(start, diagonal, 7.0, 9.0, TICK)
	assert_gt(MovementMath.horizontal_speed(raw), 7.0, "raw acceleration gains speed")
	assert_almost_eq(MovementMath.horizontal_speed(capped), 7.0, 0.0001, "capped does not")
	assert_gt(capped.x, 0.0, "but it still turns toward the wish direction")


func test_capped_accelerate_never_adds_speed_above_takeoff_speed() -> void:
	var velocity: Vector3 = FORWARD * 7.0
	for step: int in 240:
		# Wiggle the wish direction left and right like a strafe-jumper would.
		var angle: float = deg_to_rad(60.0) * (1.0 if step % 20 < 10 else -1.0)
		var wish: Vector3 = FORWARD.rotated(Vector3.UP, angle)
		velocity = MovementMath.accelerate_capped(velocity, wish, 7.0, 1.5, TICK)
		assert_lte(MovementMath.horizontal_speed(velocity), 7.0 + 0.0001)


func test_capped_accelerate_can_redirect_momentum() -> void:
	var velocity: Vector3 = FORWARD * 4.5
	for _step: int in 30:
		velocity = MovementMath.accelerate_capped(velocity, RIGHT, 4.5, 1.5, TICK)
	assert_gt(velocity.x, 0.5, "half a second of air strafe moves the velocity sideways")


func test_capped_accelerate_from_standing_jump_is_capped_at_wish_speed() -> void:
	var velocity := Vector3.ZERO
	for _step: int in 600:
		velocity = MovementMath.accelerate_capped(velocity, FORWARD, 4.5, 1.5, TICK)
	assert_almost_eq(MovementMath.horizontal_speed(velocity), 4.5, 0.0001)


func test_capped_accelerate_keeps_vertical_velocity() -> void:
	var velocity: Vector3 = MovementMath.accelerate_capped(Vector3(0.0, -4.0, -7.0), RIGHT, 7.0, 1.5, TICK)
	assert_eq(velocity.y, -4.0)


# --- Slide ---


func test_slide_decay_is_linear() -> void:
	var velocity: Vector3 = FORWARD * 8.5
	for _step: int in 30:
		velocity = MovementMath.slide_decay(velocity, 6.0, TICK)
	assert_almost_eq(MovementMath.horizontal_speed(velocity), 8.5 - 6.0 * 0.5, 0.0001)


func test_slide_decay_keeps_direction_and_vertical() -> void:
	var start := Vector3(3.0, -2.0, -4.0)
	var velocity: Vector3 = MovementMath.slide_decay(start, 6.0, TICK)
	assert_eq(velocity.y, -2.0)
	var flat_before: Vector3 = MovementMath.horizontal(start).normalized()
	var flat_after: Vector3 = MovementMath.horizontal(velocity).normalized()
	assert_almost_eq(flat_before.dot(flat_after), 1.0, 0.00001)


func test_slide_decay_stops_at_zero() -> void:
	var velocity: Vector3 = FORWARD * 1.0
	for _step: int in 60:
		velocity = MovementMath.slide_decay(velocity, 6.0, TICK)
	assert_eq(MovementMath.horizontal_speed(velocity), 0.0)


func test_slide_duration_and_distance_match_simulation() -> void:
	var entry: float = 8.5
	var end: float = _settings.slide_end_speed
	var deceleration: float = _settings.slide_deceleration
	var velocity: Vector3 = FORWARD * entry
	var elapsed: float = 0.0
	var distance: float = 0.0
	while MovementMath.horizontal_speed(velocity) > end:
		var before: float = MovementMath.horizontal_speed(velocity)
		velocity = MovementMath.slide_decay(velocity, deceleration, TICK)
		# Trapezoid, which is exact for constant deceleration.
		distance += (before + MovementMath.horizontal_speed(velocity)) * 0.5 * TICK
		elapsed += TICK
	# 1.5 ticks: the loop can run one tick past the exact end speed.
	assert_almost_eq(elapsed, MovementMath.slide_duration(entry, end, deceleration), TICK * 1.5)
	assert_almost_eq(distance, MovementMath.slide_distance(entry, end, deceleration), entry * TICK)


func test_slide_analytic_helpers() -> void:
	assert_almost_eq(MovementMath.slide_duration(9.0, 3.0, 6.0), 1.0, 0.00001)
	assert_almost_eq(MovementMath.slide_distance(9.0, 3.0, 6.0), 6.0, 0.00001)
	assert_eq(MovementMath.slide_duration(2.0, 3.0, 6.0), 0.0, "already below the end speed")
	assert_eq(MovementMath.slide_distance(9.0, 3.0, 0.0), 0.0, "no deceleration is treated as no slide")


func test_slide_entry_adds_boost_along_current_direction() -> void:
	var start := Vector3(0.0, 0.0, -7.0)
	var velocity: Vector3 = MovementMath.slide_entry_velocity(start, 1.5, 9.0)
	assert_almost_eq(velocity.z, -8.5, 0.00001)
	assert_almost_eq(velocity.x, 0.0, 0.00001)


func test_slide_entry_boost_is_capped() -> void:
	var velocity: Vector3 = MovementMath.slide_entry_velocity(FORWARD * 8.5, 1.5, 9.0)
	assert_almost_eq(MovementMath.horizontal_speed(velocity), 9.0, 0.00001)


func test_slide_entry_never_slows_a_fast_player() -> void:
	var velocity: Vector3 = MovementMath.slide_entry_velocity(FORWARD * 12.0, 1.5, 9.0)
	assert_almost_eq(MovementMath.horizontal_speed(velocity), 12.0, 0.00001)


func test_slide_entry_without_boost_keeps_speed() -> void:
	var velocity: Vector3 = MovementMath.slide_entry_velocity(FORWARD * 7.0, 0.0, 9.0)
	assert_almost_eq(MovementMath.horizontal_speed(velocity), 7.0, 0.00001)


# --- Jump ---


func test_jump_velocity_formula() -> void:
	assert_almost_eq(MovementMath.jump_velocity(0.65, 9.81), sqrt(2.0 * 9.81 * 0.65), 0.00001)
	assert_eq(MovementMath.jump_velocity(0.0, 9.81), 0.0)


func test_jump_reaches_configured_height_with_half_step_gravity() -> void:
	# Same integration the controller uses: half gravity, move, half gravity.
	var gravity: float = 9.81
	var height: float = 0.0
	var apex: float = 0.0
	var vertical: float = MovementMath.jump_velocity(_settings.jump_height, gravity)
	for _step: int in 120:
		vertical -= gravity * TICK * 0.5
		height += vertical * TICK
		vertical -= gravity * TICK * 0.5
		apex = maxf(apex, height)
		if height <= 0.0:
			break
	assert_almost_eq(apex, _settings.jump_height, 0.002, "apex within 2 mm of the configured jump height")


# --- Helpers ---


func test_with_horizontal_speed_rescales_only_xz() -> void:
	var velocity: Vector3 = MovementMath.with_horizontal_speed(Vector3(3.0, 5.0, -4.0), 10.0)
	assert_almost_eq(velocity, Vector3(6.0, 5.0, -8.0), Vector3.ONE * 0.00001)


func test_with_horizontal_speed_handles_zero_velocity() -> void:
	assert_eq(MovementMath.with_horizontal_speed(Vector3(0.0, 2.0, 0.0), 5.0), Vector3(0.0, 2.0, 0.0))


func test_eye_height_tracks_collider_height() -> void:
	assert_almost_eq(
		_settings.eye_height_for(_settings.stand_height),
		_settings.stand_height - _settings.eye_offset_from_top,
		0.00001
	)
