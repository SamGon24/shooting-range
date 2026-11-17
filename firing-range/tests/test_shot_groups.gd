extends GutTest

var _system: ProjectileSystem
var _feedback: RangeFeedback
var _view: FeedbackView
var _dummy: TargetDummy
var _hits: Array[ProjectileHit] = []


func before_each() -> void:
	_hits.clear()
	_system = ProjectileSystem.new()
	_system.capacity = 8
	add_child_autofree(_system)
	_system.set_physics_process(false)
	add_child_autofree(TargetHits.new())
	_feedback = RangeFeedback.new()
	add_child_autofree(_feedback)
	_feedback.set_physics_process(false)
	_view = FeedbackView.new()
	add_child_autofree(_view)
	_view.set_process(false)
	_feedback.feedback.connect(_view.show_feedback)
	_feedback.damage_total.connect(_view.show_damage_total)
	_system.projectile_hit.connect(func(hit: ProjectileHit) -> void: _hits.append(hit))
	_dummy = TargetDummy.new()
	_dummy.armor_plates = 3
	_dummy.position.z = -8.0
	add_child_autofree(_dummy)
	await wait_physics_frames(2)


func _spec() -> ProjectileSpec:
	var spec := ProjectileSpec.new()
	spec.source = DamageSource.Kind.PELLET
	spec.gravity_scale = 0.0
	spec.muzzle_velocity = 100.0
	spec.damage = 5.0
	return spec


func _directions(count: int) -> PackedVector3Array:
	var directions := PackedVector3Array()
	directions.resize(count)
	directions.fill(Vector3.FORWARD)
	return directions


func test_eight_real_sweeps_score_one_shot_hit_and_damage_number() -> void:
	var nodes: int = get_tree().get_node_count()
	_system.fire_volley(Vector3(0, 1.18, 0), _directions(8), _spec())
	assert_eq(_system.get_active_count(), 8)
	var shot_id: int = _system.get_slot_shot_id(0)
	_system.advance(0.1)
	assert_eq(_hits.size(), 8)
	for hit: ProjectileHit in _hits:
		assert_eq(hit.shot_id, shot_id)
		assert_eq(hit.source, DamageSource.Kind.PELLET)
	assert_eq(_feedback.stats.shots, 1)
	assert_eq(_feedback.stats.hits, 1)
	assert_eq(_feedback.stats.accuracy_percent(), 100.0)
	assert_eq((_view.get_child(0) as Label).text, "40")
	assert_eq((_view.get_child(1) as Label).text, "")
	assert_eq(get_tree().get_node_count(), nodes)
	assert_eq(_system.get_active_shot_count(), 0)
	assert_eq(_feedback._pellet_totals.size(), 0, "finished shots release aggregation state")


func test_cross_tick_pellets_update_one_label_and_promote_headshot_once() -> void:
	var directions: PackedVector3Array = _directions(2)
	directions[1] = Vector3(0, 0.47, -8).normalized()
	_system.fire_volley(Vector3(0, 1.18, 0), directions, _spec())
	_system.advance(0.07865)
	assert_eq(_hits.size(), 1)
	assert_eq((_view.get_child(0) as Label).text, "5")
	_system.advance(0.01)
	assert_eq(_hits.size(), 2)
	assert_eq(_feedback.stats.shots, 1)
	assert_eq(_feedback.stats.hits, 1)
	assert_eq(_feedback.stats.headshots, 1)
	assert_eq(_feedback.stats.headshot_percent(), 100.0)
	assert_eq((_view.get_child(0) as Label).text, "13", "5 body plus 7.5 head, rounded once")
	assert_eq((_view.get_child(1) as Label).text, "")
	assert_eq((_view.get_child(0) as Label).get_theme_color("font_color"), _view.headshot_color)


func test_multi_target_volley_keeps_target_timers_but_counts_one_hit() -> void:
	var far := TargetDummy.new()
	far.armor_plates = 0
	far.position = Vector3(2, 0, -20)
	add_child_autofree(far)
	await wait_physics_frames(2)
	var spec: ProjectileSpec = _spec()
	spec.damage = 100.0
	_system.fire_volley(Vector3(0, 1.18, 0), PackedVector3Array([Vector3.FORWARD, Vector3(2, 0.47, -20).normalized()]), spec)
	_system.advance(0.1)
	assert_eq(_feedback.stats.hits, 1)
	_feedback._physics_process(0.1)
	_system.advance(0.11)
	assert_true(far.state.dead)
	assert_eq(_feedback.stats.hits, 1)
	assert_eq(_feedback.stats.headshots, 1)
	assert_eq(_feedback.stats.last_time_to_kill, 0.0)
	assert_eq((_view.get_child(0) as Label).text, "100")
	assert_eq((_view.get_child(1) as Label).text, "150")


func test_reset_excludes_in_flight_group_after_pool_slots_are_reused() -> void:
	_system.fire_volley(Vector3(0, 1.18, 0), _directions(8), _spec())
	_feedback.reset_stats()
	_system.advance(0.1)
	assert_eq(_feedback.stats.hits, 0)
	assert_eq(_feedback.stats.shots, 0)
	_system.fire_volley(Vector3(0, 1.18, 0), _directions(8), _spec())
	_system.advance(0.1)
	assert_eq(_feedback.stats.shots, 1)
	assert_eq(_feedback.stats.hits, 1)
	assert_ne(_hits[0].shot_id, _hits[8].shot_id)


func test_full_pool_rejects_entire_volley_and_expiry_releases_groups() -> void:
	for index: int in 7:
		_system.fire(Vector3(50, 5, 0), Vector3.FORWARD, _spec())
	assert_eq(_system.fire_volley(Vector3.ZERO, _directions(8), _spec()), -1)
	assert_eq(_system.get_active_count(), 7)
	assert_eq(_feedback.stats.shots, 7)
	assert_eq(_system.get_dropped_count(), 8)
	_system.advance(4.0)
	assert_eq(_system.get_active_shot_count(), 0)
	assert_eq(_feedback._eligible_shots.size(), 0)


func test_keyed_number_pool_evicts_old_keys_and_clears_without_allocating() -> void:
	var nodes: int = get_tree().get_node_count()
	for id: int in 100:
		_view.show_damage_total(id, 9, Vector3.ZERO, 20, false)
	assert_eq(_view._number_keys.size(), _view.number_capacity)
	_view.show_damage_total(99, 9, Vector3.ZERO, 40, true)
	assert_eq((_view.get_child(3) as Label).text, "40")
	_view.clear_feedback()
	assert_eq(_view._number_keys.size(), 0)
	assert_eq(get_tree().get_node_count(), nodes)
