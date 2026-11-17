extends GutTest


func test_trigger_policy_is_independent_of_delivery_and_reload() -> void:
	var mode := FireModeData.new()
	for kind: FireModeData.Kind in [FireModeData.Kind.FULL_AUTO, FireModeData.Kind.SEMI_AUTO, FireModeData.Kind.BOLT_ACTION, FireModeData.Kind.PUMP_ACTION]:
		mode.kind = kind
		assert_true(mode.wants_shot(true, true))
		assert_eq(mode.wants_shot(true, false), kind == FireModeData.Kind.FULL_AUTO)
		assert_eq(mode.interval(600.0, 0.8), 0.8)
	var reload := ReloadData.new()
	assert_eq(reload.refill(2, 5), 5)
	reload.kind = ReloadData.Kind.SINGLE_ROUND
	assert_eq(reload.refill(2, 5), 3)
	reload.kind = ReloadData.Kind.NONE
	assert_false(reload.can_reload(0, 5))
	reload.kind = ReloadData.Kind.SHELL
	assert_true(reload.is_supported())
	assert_eq(reload.refill(2, 5), 3)
	var delivery := DeliveryData.new()
	delivery.kind = DeliveryData.Kind.PELLET
	assert_true(delivery.is_supported())
	delivery.kind = DeliveryData.Kind.EXPLOSIVE
	assert_true(delivery.is_supported())
	delivery.kind = DeliveryData.Kind.MELEE
	assert_true(delivery.is_supported())


func test_damage_source_survives_the_existing_ballistic_and_target_path() -> void:
	var system := ProjectileSystem.new()
	add_child_autofree(system)
	system.set_physics_process(false)
	add_child_autofree(TargetHits.new())
	var dummy := TargetDummy.new()
	dummy.position.z = -10.0
	add_child_autofree(dummy)
	var sources: Array[DamageSource.Kind] = []
	dummy.damaged.connect(func(hit: ProjectileHit, _zone: TargetSettings.Zone, _amount: float) -> void: sources.append(hit.source))
	await wait_physics_frames(2)
	var spec := ProjectileSpec.new()
	spec.source = DamageSource.Kind.PELLET
	spec.gravity_scale = 0.0
	system.fire(Vector3(0, 1.2, 0), Vector3.FORWARD, spec)
	system.advance(1.0 / 60.0)
	assert_eq(sources, [DamageSource.Kind.PELLET] as Array[DamageSource.Kind])
	assert_eq(dummy.state.health, 70.0)
