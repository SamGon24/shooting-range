extends GutTest

var _world: Node3D
var _system: ProjectileSystem
var _explosions: ExplosionSystem
var _feedback: RangeFeedback
var _dummy: TargetDummy
var _spec: ProjectileSpec
var _blasts: Array[Vector3] = []
var _zones: Array[TargetSettings.Zone] = []
var _sources: Array[DamageSource.Kind] = []


func before_each() -> void:
	_blasts.clear()
	_zones.clear()
	_sources.clear()
	_world = Node3D.new()
	add_child_autofree(_world)
	_system = ProjectileSystem.new()
	_world.add_child(_system)
	_system.set_physics_process(false)
	_explosions = ExplosionSystem.new()
	_world.add_child(_explosions)
	_explosions.exploded.connect(func(point: Vector3, _data: ExplosionData) -> void: _blasts.append(point))
	_world.add_child(TargetHits.new())
	_feedback = RangeFeedback.new()
	_world.add_child(_feedback)
	_dummy = _add_dummy(Vector3(0.6, 0, -19.8))
	_dummy.damaged.connect(func(hit: ProjectileHit, zone: TargetSettings.Zone, _amount: float) -> void:
		_zones.append(zone)
		_sources.append(hit.source))
	_spec = ProjectileSpec.new()
	_spec.muzzle_velocity = 120.0
	_spec.gravity_scale = 0.0
	_spec.damage = 0.0
	_spec.explosion = ExplosionData.new()
	_spec.explosion.damage = 50.0
	await wait_physics_frames(2)


func _add_dummy(point: Vector3) -> TargetDummy:
	var dummy := TargetDummy.new()
	dummy.armor_plates = 1
	dummy.position = point
	_world.add_child(dummy)
	return dummy


func _wall(distance: float) -> void:
	var wall := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20, 10, 0.1)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector3(0, 1.18, -distance - 0.05)
	_world.add_child(wall)


func _fire() -> void:
	_system.fire(Vector3(0, 1.18, 0), Vector3.FORWARD, _spec)
	_system.advance(0.25)


func test_radial_falloff_and_arming_boundary() -> void:
	var data := ExplosionData.new()
	assert_false(data.is_armed(9.999))
	assert_true(data.is_armed(10.0))
	assert_eq(data.damage_at_distance(0), 180.0)
	assert_eq(data.damage_at_distance(1), 180.0)
	assert_eq(data.damage_at_distance(3.5), 90.0)
	assert_eq(data.damage_at_distance(6), 0.0)
	assert_eq(data.damage_at_distance(20), 0.0)
	assert_eq(data.impulse_at(Vector3.RIGHT), Vector3.RIGHT * 45.0)
	assert_eq(data.impulse_at(Vector3.LEFT * 3.5), Vector3.LEFT * 22.5)


func test_contact_before_ten_metres_is_a_dud_without_target_damage() -> void:
	_wall(8)
	_dummy.position.z = -7.8
	await wait_physics_frames(2)
	_fire()
	assert_eq(_blasts.size(), 0)
	assert_eq(_dummy.state.armor, 50.0)
	assert_eq(_zones.size(), 0)
	assert_eq(_feedback.stats.shots, 1)
	assert_eq(_feedback.stats.hits, 0)


func test_exact_ten_metre_contact_arms_and_breaks_last_plate_exactly() -> void:
	_wall(10)
	_dummy.position.z = -9.8
	await wait_physics_frames(2)
	_fire()
	assert_eq(_blasts.size(), 1)
	assert_eq(_dummy.state.armor, 0.0)
	assert_eq(_dummy.state.health, 100.0)
	assert_eq(_sources, [DamageSource.Kind.SPLASH] as Array[DamageSource.Kind])
	assert_eq(_zones, [TargetSettings.Zone.TORSO] as Array[TargetSettings.Zone])


func test_splash_applies_armor_first_with_carryover_and_one_report_per_dummy() -> void:
	_wall(20)
	_spec.explosion.damage = 75.0
	await wait_physics_frames(2)
	_fire()
	assert_eq(_dummy.state.armor, 0.0)
	assert_eq(_dummy.state.health, 75.0)
	assert_eq(_zones.size(), 1, "overlapping head, torso and limbs do not multiply splash")
	assert_eq(_feedback.stats.shots, 1)
	assert_eq(_feedback.stats.hits, 1)
	assert_eq(_feedback.stats.headshots, 0)


func test_wall_occlusion_blocks_splash_to_a_dummy_behind_the_impact() -> void:
	_wall(20)
	_dummy.position.z = -21.0
	await wait_physics_frames(2)
	_fire()
	assert_eq(_blasts.size(), 1)
	assert_eq(_dummy.state.armor, 50.0)
	assert_eq(_feedback.stats.hits, 0)


func test_multiple_damaged_targets_count_as_one_rocket_hit_and_reset_excludes_old_rocket() -> void:
	_wall(20)
	var other: TargetDummy = _add_dummy(Vector3(-0.6, 0, -19.8))
	await wait_physics_frames(2)
	_fire()
	assert_eq(other.state.armor, 0.0)
	assert_eq(_dummy.state.armor, 0.0)
	assert_eq(_feedback.stats.shots, 1)
	assert_eq(_feedback.stats.hits, 1)
	assert_eq(_feedback.stats.accuracy_percent(), 100.0)
	_system.fire(Vector3(0, 1.18, 0), Vector3.FORWARD, _spec)
	_feedback.reset_stats()
	_system.advance(0.25)
	assert_eq(_feedback.stats.shots, 0)
	assert_eq(_feedback.stats.hits, 0)
	assert_eq(_dummy.state.health, 50.0, "real old-rocket damage still applies")


func test_blast_impulse_direction_and_magnitude_on_a_prop_and_steel() -> void:
	_wall(20)
	var prop := PhysicsProp.new()
	prop.gravity_scale = 0.0
	prop.position = Vector3(-2, 1.18, -19.8)
	_world.add_child(prop)
	prop.linear_damp = 0.0
	prop.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	var steel := SteelPlate.new()
	steel.gravity_scale = 0.0
	steel.position = Vector3(-3, 1.18, -18.5)
	_world.add_child(steel)
	await wait_physics_frames(2)
	_fire()
	var expected: Vector3 = _spec.explosion.impulse_at(prop.global_position - _blasts[0])
	await wait_physics_frames(2)
	assert_almost_eq(prop.linear_velocity * prop.mass, expected, Vector3.ONE * 0.001)
	assert_lt(steel.angular_velocity.x, 0.0, "blast drives the constrained plate away from impact")


func test_a_killing_blast_pushes_new_ragdoll_parts_once() -> void:
	_wall(20)
	_spec.explosion.damage = 400.0
	for part: RigidBody3D in _dummy.ragdoll.parts:
		part.gravity_scale = 0.0
		part.linear_damp = 0.0
		part.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	await wait_physics_frames(2)
	_fire()
	assert_true(_dummy.state.dead)
	assert_true(_dummy.ragdoll.active)
	var expected: Vector3 = Vector3.ZERO
	for part: RigidBody3D in _dummy.ragdoll.parts:
		expected += _spec.explosion.impulse_at(part.global_position - _blasts[0])
	await wait_physics_frames(2)
	var momentum: Vector3 = Vector3.ZERO
	for part: RigidBody3D in _dummy.ragdoll.parts:
		assert_gt(part.linear_velocity.length(), 0.0)
		momentum += part.linear_velocity * part.mass
	assert_almost_eq(momentum, expected, Vector3.ONE * 0.05, "internal joints conserve the six applied impulses")
	assert_eq(_feedback.stats.last_time_to_kill, 0.0)


func test_expiring_rocket_without_contact_does_not_explode() -> void:
	_spec.max_lifetime = 0.1
	_system.fire(Vector3(100, 20, 0), Vector3.FORWARD, _spec)
	_system.advance(0.2)
	assert_eq(_blasts.size(), 0)
	assert_eq(_system.get_active_shot_count(), 0)
	assert_eq(_feedback.stats.hits, 0)
