extends GutTest
## RecoilLogic: pattern indexing, random deviation, reset and recovery, and
## the split of mouse movement against a recoil offset.

const TICK: float = 1.0 / 60.0

var _data: WeaponData
var _rng: RandomNumberGenerator


func before_each() -> void:
	_data = WeaponData.new()
	_data.recoil_pattern = PackedVector2Array([
		Vector2(0.0, 1.0), Vector2(0.1, 2.0), Vector2(0.2, 3.0), Vector2(-0.3, 4.0), Vector2(0.4, 5.0),
	])
	_data.recoil_loop_length = 2
	_data.recoil_random_degrees = Vector2.ZERO
	_data.aimed_recoil_scale = 0.5
	_data.recoil_recovery_delay = 0.1
	_data.recoil_recovery_rate = 6.0
	_data.recoil_reset_time = 0.3
	_rng = RandomNumberGenerator.new()
	_rng.seed = 42


func _ticks(recoil: RecoilLogic, count: int) -> void:
	for _tick: int in count:
		recoil.tick(TICK)


func test_shots_walk_through_the_pattern_in_order() -> void:
	var recoil := RecoilLogic.new(_data, _rng)
	for i: int in 5:
		assert_eq(recoil.shot_index, i)
		assert_eq(recoil.on_shot(0.0), _data.recoil_pattern[i], "shot %d" % (i + 1))
		_ticks(recoil, 5)


func test_past_the_end_the_last_entries_loop() -> void:
	var recoil := RecoilLogic.new(_data, _rng)
	# Loop length 2 over entries 3 and 4: 3, 4, 3, 4, ...
	assert_eq(recoil.pattern_kick(5), _data.recoil_pattern[3])
	assert_eq(recoil.pattern_kick(6), _data.recoil_pattern[4])
	assert_eq(recoil.pattern_kick(7), _data.recoil_pattern[3])
	assert_eq(recoil.pattern_kick(100), _data.recoil_pattern[4])


func test_loop_length_is_clamped_to_the_pattern() -> void:
	_data.recoil_loop_length = 50
	var recoil := RecoilLogic.new(_data, _rng)
	assert_eq(recoil.pattern_kick(5), _data.recoil_pattern[0], "loops the whole pattern")
	_data.recoil_pattern = PackedVector2Array()
	assert_eq(recoil.pattern_kick(0), Vector2.ZERO, "an empty pattern kicks nothing")


func test_pattern_restarts_after_the_reset_time_only() -> void:
	var recoil := RecoilLogic.new(_data, _rng)
	recoil.on_shot(0.0)
	recoil.on_shot(0.0)
	_ticks(recoil, 17)  # 0.283 s, just short of 0.3 s.
	assert_eq(recoil.shot_index, 2, "a pause shorter than the reset time keeps the place")
	_ticks(recoil, 1)
	assert_eq(recoil.shot_index, 0, "back to shot 1 at 0.3 s")


func test_aiming_scales_the_kick() -> void:
	var recoil := RecoilLogic.new(_data, _rng)
	assert_eq(recoil.on_shot(1.0), Vector2(0.0, 0.5), "half the kick fully aimed")
	assert_eq(recoil.on_shot(0.5), Vector2(0.075, 1.5), "three quarters halfway in")


func test_random_deviation_stays_in_bounds_and_varies() -> void:
	_data.recoil_random_degrees = Vector2(0.2, 0.1)
	_data.recoil_pattern = PackedVector2Array([Vector2(0.0, 1.0)])
	var recoil := RecoilLogic.new(_data, _rng)
	var kicks: Array[Vector2] = []
	for _shot: int in 200:
		var kick: Vector2 = recoil.on_shot(0.0)
		assert_between(kick.x, -0.2, 0.2)
		assert_between(kick.y, 0.9, 1.1)
		kicks.append(kick)
	assert_ne(kicks[0], kicks[1], "random part changes per shot")


func test_same_seed_gives_the_same_kicks() -> void:
	_data.recoil_random_degrees = Vector2(0.2, 0.1)
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 7
	b.seed = 7
	var first := RecoilLogic.new(_data, a)
	var second := RecoilLogic.new(_data, b)
	for _shot: int in 10:
		assert_eq(first.on_shot(0.0), second.on_shot(0.0))


func test_recovery_waits_for_the_delay_then_runs_at_the_rate() -> void:
	var recoil := RecoilLogic.new(_data, _rng)
	assert_almost_eq(recoil.recovery_allowance(TICK), 0.1, 0.00001, "a settled weapon recovers at 6 °/s")
	recoil.on_shot(0.0)
	assert_eq(recoil.recovery_allowance(TICK), 0.0, "not on the tick of a shot")
	_ticks(recoil, 5)  # 0.083 s
	assert_eq(recoil.recovery_allowance(TICK), 0.0, "not before 0.1 s")
	_ticks(recoil, 1)
	assert_almost_eq(recoil.recovery_allowance(TICK), 0.1, 0.00001)


func test_absorb_cancels_recoil_before_moving_the_base_angle() -> void:
	assert_eq(RecoilLogic.absorb(3.0, -1.0), Vector2(2.0, 0.0), "pulling down eats into the kick")
	assert_eq(RecoilLogic.absorb(3.0, -5.0), Vector2(0.0, -2.0), "the rest moves the base angle")
	assert_eq(RecoilLogic.absorb(3.0, 1.0), Vector2(3.0, 1.0), "moving with the kick leaves it alone")
	assert_eq(RecoilLogic.absorb(-2.0, 0.5), Vector2(-1.5, 0.0), "works for either sign")
	assert_eq(RecoilLogic.absorb(0.0, -1.0), Vector2(0.0, -1.0))
