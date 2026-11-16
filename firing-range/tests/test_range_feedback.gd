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
