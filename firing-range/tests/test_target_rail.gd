extends GutTest


func _rail(speed: float) -> TargetRail:
	var rail := TargetRail.new()
	rail.position = Vector3(5.0, 0.0, -50.0)
	rail.speed = speed
	add_child_autofree(rail)
	rail.set_physics_process(false)
	return rail


func test_walk_and_sprint_speed_in_metres_per_second() -> void:
	for speed: float in [1.5, 6.0]:
		var rail: TargetRail = _rail(speed)
		for tick: int in 30:
			rail.advance(1.0 / 60.0)
		assert_almost_eq(rail.position.x - 5.0, speed * 0.5, 0.0001)
		assert_eq(rail.position.z, -50.0)


func test_end_reversal_preserves_overshoot() -> void:
	var rail: TargetRail = _rail(6.0)
	rail.advance(0.75)
	assert_almost_eq(rail.distance, 3.5, 0.00001)
	assert_eq(rail.direction, -1.0)
	rail.advance(0.6)
	assert_almost_eq(rail.distance, 0.1, 0.00001)
	assert_eq(rail.direction, 1.0)


func test_exact_endpoints_reverse_and_large_steps_match_small_steps() -> void:
	var rail: TargetRail = _rail(1.5)
	rail.advance(4.0 / 1.5)
	assert_eq(rail.distance, 4.0)
	assert_eq(rail.direction, -1.0)
	rail.advance(4.0 / 1.5)
	assert_eq(rail.distance, 0.0)
	assert_eq(rail.direction, 1.0)
	var other: TargetRail = _rail(1.5)
	rail.advance(17.0)
	for tick: int in 1020:
		other.advance(1.0 / 60.0)
	assert_almost_eq(rail.distance, other.distance, 0.0001)
	assert_eq(rail.direction, other.direction)
