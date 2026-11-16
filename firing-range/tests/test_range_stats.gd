extends GutTest


func test_empty_percentages_and_no_kill() -> void:
	var stats := RangeStats.new()
	assert_eq(stats.accuracy_percent(), 0.0)
	assert_eq(stats.headshot_percent(), 0.0)
	assert_eq(stats.last_time_to_kill, -1.0)


func test_accuracy_and_headshot_percent_have_different_denominators() -> void:
	var stats := RangeStats.new()
	for shot: int in 5:
		stats.record_shot()
	stats.record_hit(1, true, false, 1.0)
	stats.record_hit(1, false, false, 2.0)
	stats.record_hit(2, false, false, 2.5, false)
	assert_almost_eq(stats.accuracy_percent(), 60.0, 0.0001)
	assert_almost_eq(stats.headshot_percent(), 100.0 / 3.0, 0.0001)


func test_ttk_is_per_target_first_damage_to_kill_and_one_shot_is_zero() -> void:
	var stats := RangeStats.new()
	stats.record_hit(1, false, false, 1.0)
	stats.record_hit(2, false, false, 1.5)
	stats.record_hit(1, false, true, 3.0)
	assert_eq(stats.last_time_to_kill, 2.0)
	stats.record_hit(2, true, true, 4.0)
	assert_eq(stats.last_time_to_kill, 2.5)
	stats.record_hit(3, true, true, 9.0)
	assert_eq(stats.last_time_to_kill, 0.0)
	stats.record_hit(1, false, false, 10.0)
	stats.record_hit(1, false, true, 10.5)
	assert_eq(stats.last_time_to_kill, 0.5, "new life does not reuse the earlier start")


func test_reset_clears_counts_ttk_and_open_target_lives() -> void:
	var stats := RangeStats.new()
	stats.record_shot()
	stats.record_hit(1, true, false, 1.0)
	stats.record_hit(2, false, true, 2.0)
	stats.reset()
	assert_eq(stats.shots, 0)
	assert_eq(stats.hits, 0)
	assert_eq(stats.headshots, 0)
	assert_eq(stats.accuracy_percent(), 0.0)
	assert_eq(stats.headshot_percent(), 0.0)
	assert_eq(stats.last_time_to_kill, -1.0)
	stats.record_hit(1, false, true, 8.0)
	assert_eq(stats.last_time_to_kill, 0.0)


func test_restoring_a_target_discards_its_open_timer() -> void:
	var stats := RangeStats.new()
	stats.record_hit(1, false, false, 1.0)
	stats.end_life(1)
	stats.record_hit(1, false, true, 5.0)
	assert_eq(stats.last_time_to_kill, 0.0)
