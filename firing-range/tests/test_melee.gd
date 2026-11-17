extends GutTest

var _world: Node3D
var _system: ProjectileSystem
var _melee: MeleeSystem
var _feedback: RangeFeedback
var _dummy: TargetDummy
var _data: ContactData
var _spec: ProjectileSpec
var _hits: Array[ProjectileHit] = []


func before_each() -> void:
	_hits.clear()
	_world = Node3D.new()
	add_child_autofree(_world)
	_system = ProjectileSystem.new()
	_world.add_child(_system)
	_system.set_physics_process(false)
	_melee = MeleeSystem.new()
	_world.add_child(_melee)
	_world.add_child(TargetHits.new())
	_feedback = RangeFeedback.new()
	_world.add_child(_feedback)
	_dummy = _add_dummy(1.79)
	_data = ContactData.new()
	_spec = ProjectileSpec.new()
	_spec.source = DamageSource.Kind.MELEE
	_spec.damage = 25.0
	_system.projectile_hit.connect(func(hit: ProjectileHit) -> void: _hits.append(hit))
	await wait_physics_frames(2)


func _add_dummy(front_distance: float) -> TargetDummy:
	var dummy := TargetDummy.new()
	dummy.armor_plates = 0
	dummy.position.z = -front_distance - 0.14
	_world.add_child(dummy)
	return dummy


func _swing(exclude: Array[RID] = []) -> int:
	return _melee.swing(_system, Vector3(0, 1.18, 0), Vector3.FORWARD, _data, _spec, exclude)


func test_knife_reach_includes_radius_and_reports_real_melee_damage() -> void:
	var nodes: int = get_tree().get_node_count()
	assert_gt(_swing(), 0)
	assert_eq(_dummy.state.health, 75.0)
	assert_eq(_feedback.stats.shots, 1)
	assert_eq(_feedback.stats.hits, 1)
	assert_eq(_hits.size(), 1)
	assert_eq(_hits[0].source, DamageSource.Kind.MELEE)
	assert_eq(_hits[0].velocity, Vector3.ZERO)
	assert_eq(_hits[0].momentum(), Vector3.FORWARD * 6.0)
	assert_lte(_hits[0].travel_distance, 1.8)
	assert_eq(_system.get_active_count(), 0)
	assert_eq(_system.get_active_shot_count(), 0)
	assert_eq(get_tree().get_node_count(), nodes)


func test_knife_does_not_reach_beyond_the_authored_distance() -> void:
	_dummy.position.z = -1.81 - 0.14
	await wait_physics_frames(2)
	_swing()
	assert_eq(_dummy.state.health, 100.0)
	assert_eq(_hits.size(), 0)
	assert_eq(_feedback.stats.shots, 1)
	assert_eq(_feedback.stats.hits, 0)


func test_bash_reach_is_one_point_five_metres_and_drops_stale_hits() -> void:
	_data.reach_m = 1.5
	_data.radius_m = 0.18
	_dummy.position.z = -1.49 - 0.14
	await wait_physics_frames(2)
	_swing()
	assert_eq(_dummy.state.health, 75.0)
	_dummy.position.z = -1.51 - 0.14
	await wait_physics_frames(2)
	_swing()
	assert_eq(_dummy.state.health, 75.0)
	assert_eq(_feedback.stats.shots, 2)
	assert_eq(_feedback.stats.hits, 1)


func test_wall_blocks_a_swing_before_it_reaches_a_dummy() -> void:
	var wall := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2, 3, 0.1)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector3(0, 1.18, -0.75)
	_world.add_child(wall)
	await wait_physics_frames(2)
	_swing()
	assert_eq(_dummy.state.health, 100.0)
	assert_eq(_hits[0].collider, wall)
	assert_eq(_feedback.stats.hits, 0)


func test_initial_overlap_and_multiple_targets_still_apply_one_contact() -> void:
	_dummy.position.z = -0.24
	var other: TargetDummy = _add_dummy(0.1)
	await wait_physics_frames(2)
	_swing()
	assert_eq(_dummy.state.health + other.state.health, 175.0)
	assert_eq(_hits.size(), 1)
	assert_eq(_feedback.stats.hits, 1)


func test_own_guard_can_be_excluded_without_leaking_exclusions_to_next_swing() -> void:
	_dummy.position.z = -1.2 - 0.14
	var guard := WeaponGuard.new()
	_world.add_child(guard)
	guard.configure(GuardData.new())
	guard.update_pose(Vector3(0, 1.18, 0), Basis.IDENTITY, true)
	await wait_physics_frames(2)
	_swing()
	assert_eq(_hits[0].collider, guard)
	assert_eq(_dummy.state.health, 100.0)
	_swing([guard.get_rid()])
	assert_eq(_dummy.state.health, 75.0)
	_swing()
	assert_eq(_dummy.state.health, 75.0)
	assert_eq(_feedback.stats.shots, 3)
	assert_eq(_feedback.stats.hits, 1)


func test_contact_impulse_pushes_a_prop_without_fabricating_projectile_velocity() -> void:
	var prop := PhysicsProp.new()
	prop.position = Vector3(0, 1.18, -1.0)
	prop.gravity_scale = 0.0
	_world.add_child(prop)
	prop.linear_damp = 0.0
	prop.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	await wait_physics_frames(2)
	_swing()
	await wait_physics_frames(2)
	assert_almost_eq(prop.linear_velocity * prop.mass, Vector3.FORWARD * 6.0, Vector3.ONE * 0.001)
	assert_eq(_hits[0].velocity, Vector3.ZERO)


func test_ammo_free_swing_and_bash_timing_and_disabled_aim() -> void:
	for interval: float in [0.5, 0.9]:
		var data := WeaponData.new()
		data.uses_ammo = false
		data.can_aim = false
		data.fire_mode = FireModeData.new()
		data.fire_mode.kind = FireModeData.Kind.SEMI_AUTO
		data.rounds_per_minute = 60.0 / interval
		data.bolt_cycle_time = interval
		data.reload_policy = ReloadData.new()
		data.reload_policy.kind = ReloadData.Kind.NONE
		var logic := WeaponLogic.new(data)
		logic.equip_instantly()
		var input := WeaponInput.new()
		input.trigger_pressed = true
		input.trigger_held = true
		input.aim_held = true
		assert_eq(logic.tick(1.0 / 60.0, input), 1)
		assert_eq(logic.ammo, 0)
		assert_false(logic.can_reload())
		for tick: int in roundi(interval * 60.0) - 1:
			assert_eq(logic.tick(1.0 / 60.0, input), 0)
		assert_eq(logic.tick(1.0 / 60.0, input), 1)
		assert_eq(logic.aim_progress, 0.0)
		input.trigger_pressed = false
		for tick: int in 90:
			assert_eq(logic.tick(1.0 / 60.0, input), 0, "holding does not repeat swings")
