extends GutTest

var _system: ProjectileSystem
var _feedback: RangeFeedback
var _dummy: TargetDummy
var _events: Array[HitFeedback.Kind] = []


func before_each() -> void:
	_events.clear()
	_system = ProjectileSystem.new()
	add_child_autofree(_system)
	_system.set_physics_process(false)
	add_child_autofree(TargetHits.new())
	_feedback = RangeFeedback.new()
	add_child_autofree(_feedback)
	_feedback.feedback.connect(func(kind: HitFeedback.Kind, _point: Vector3, _amount: float, _head: bool) -> void: _events.append(kind))
	_dummy = TargetDummy.new()
	_dummy.armor_plates = 1
	_dummy.position.z = -25.0
	add_child_autofree(_dummy)
	await wait_physics_frames(2)


func _shot(damage: float) -> int:
	var spec := ProjectileSpec.new()
	spec.gravity_scale = 0.0
	spec.damage = damage
	return _system.fire(Vector3(0, 1.2, 0), Vector3.FORWARD, spec)


func test_damage_signals_feed_stats_and_marker_without_duplicate_hits() -> void:
	_shot(50.0)
	_system.advance(0.05)
	assert_eq(_feedback.stats.shots, 1)
	assert_eq(_feedback.stats.hits, 1)
	assert_eq(_events[0], HitFeedback.Kind.ARMOR_BREAK)
	_shot(100.0)
	_system.advance(0.05)
	assert_eq(_feedback.stats.shots, 2)
	assert_eq(_feedback.stats.hits, 2)
	assert_eq(_events[1], HitFeedback.Kind.KILL)
	assert_eq(_feedback.stats.accuracy_percent(), 100.0)
	assert_eq(_feedback.stats.last_time_to_kill, 0.0)


func test_reset_does_not_count_a_projectile_already_in_flight() -> void:
	_shot(20.0)
	_feedback.reset_stats()
	_system.advance(0.05)
	assert_eq(_feedback.stats.shots, 0)
	assert_eq(_feedback.stats.hits, 0)
	assert_eq(_events.size(), 1, "the real damage can still be shown")
	_shot(20.0)
	_system.advance(0.05)
	assert_eq(_feedback.stats.shots, 1)
	assert_eq(_feedback.stats.hits, 1)


func _fire_and_land(damage: float, launch_clock: float, hit_clock: float) -> void:
	_feedback._clock = launch_clock
	_shot(damage)
	_feedback._clock = hit_clock
	_system.advance(0.05)


func test_ttk_defaults_to_the_first_damaging_hit() -> void:
	assert_false(ViewSettings.ttk_from_first_shot)
	_fire_and_land(50.0, 10.0, 10.4)
	_fire_and_land(100.0, 11.0, 11.5)
	assert_almost_eq(_feedback.stats.last_time_to_kill, 1.1, 0.0001, "first hit at 10.4 to the kill at 11.5")


func test_ttk_can_start_when_the_first_damaging_shot_was_fired() -> void:
	ViewSettings.ttk_from_first_shot = true
	_fire_and_land(50.0, 10.0, 10.4)
	_fire_and_land(100.0, 11.0, 11.5)
	ViewSettings.ttk_from_first_shot = false
	assert_almost_eq(_feedback.stats.last_time_to_kill, 1.5, 0.0001, "first shot fired at 10.0 to the kill at 11.5")


func test_a_one_shot_kill_reads_its_flight_time_with_the_option_on() -> void:
	_dummy.armor_plates = 0
	ViewSettings.ttk_from_first_shot = true
	_fire_and_land(400.0, 20.0, 20.6)
	ViewSettings.ttk_from_first_shot = false
	assert_almost_eq(_feedback.stats.last_time_to_kill, 0.6, 0.0001)
	assert_eq(_feedback.stats.shots, 1)
	assert_eq(_feedback.stats.hits, 1)


func test_each_target_keeps_its_own_first_shot_time() -> void:
	ViewSettings.ttk_from_first_shot = true
	var other := TargetDummy.new()
	other.armor_plates = 0
	other.position = Vector3(3.0, 0.0, -25.0)
	add_child_autofree(other)
	await wait_physics_frames(2)
	_fire_and_land(50.0, 30.0, 30.2)
	_feedback._clock = 31.0
	var spec := ProjectileSpec.new()
	spec.gravity_scale = 0.0
	spec.damage = 400.0
	_system.fire(Vector3(3.0, 1.2, 0.0), Vector3.FORWARD, spec)
	_feedback._clock = 31.3
	_system.advance(0.05)
	assert_almost_eq(_feedback.stats.last_time_to_kill, 0.3, 0.0001, "the second dummy's own first shot")
	_fire_and_land(100.0, 32.0, 32.1)
	ViewSettings.ttk_from_first_shot = false
	assert_almost_eq(_feedback.stats.last_time_to_kill, 2.1, 0.0001, "the first dummy's clock began at 30.0")
