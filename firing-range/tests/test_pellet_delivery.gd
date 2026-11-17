extends GutTest


func test_eight_seeded_pellets_use_real_pool_shared_id_and_bounded_cone() -> void:
	var system := ProjectileSystem.new()
	add_child_autofree(system)
	system.set_physics_process(false)
	var delivery := DeliveryData.new()
	delivery.kind = DeliveryData.Kind.PELLET
	var spec := ProjectileSpec.new()
	spec.source = DamageSource.Kind.PELLET
	spec.muzzle_velocity = 400.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var nodes: int = get_tree().get_node_count()
	assert_eq(delivery.launch(system, Vector3.ZERO, Vector3.FORWARD, spec, rng), 0)
	assert_eq(system.get_active_count(), 8)
	var velocities := PackedVector3Array()
	var shot_id: int = system.get_slot_shot_id(0)
	var varied: bool = false
	for slot: int in 8:
		var velocity: Vector3 = system.get_slot_velocity(slot)
		velocities.append(velocity)
		assert_almost_eq(velocity.length(), 400.0, 0.001)
		assert_lte(rad_to_deg(Vector3.FORWARD.angle_to(velocity)), delivery.pellet_spread_degrees + 0.001)
		assert_eq(system.get_slot_shot_id(slot), shot_id)
		varied = varied or slot > 0 and velocity != velocities[0]
	assert_true(varied)
	assert_eq(get_tree().get_node_count(), nodes)
	rng.seed = 91
	delivery.launch(system, Vector3.ZERO, Vector3.FORWARD, spec, rng)
	for slot: int in 8:
		assert_eq(system.get_slot_velocity(slot + 8), velocities[slot])
	assert_ne(system.get_slot_shot_id(8), shot_id)


func test_zero_cone_and_vertical_aim_are_finite() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_eq(ConeSpread.sample(Vector3.FORWARD, 0.0, rng), Vector3.FORWARD)
	for index: int in 64:
		var direction: Vector3 = ConeSpread.sample(Vector3.UP, 3.0, rng)
		assert_true(direction.is_finite())
		assert_lte(rad_to_deg(Vector3.UP.angle_to(direction)), 3.001)
