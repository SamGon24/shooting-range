extends GutTest


func test_real_projectile_rings_and_swings_a_world_hinged_plate() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var system := ProjectileSystem.new()
	root.add_child(system)
	system.set_physics_process(false)
	root.add_child(TargetHits.new())
	var plate := SteelPlate.new()
	plate.position = Vector3(0.0, 1.5, -100.0)
	root.add_child(plate)
	watch_signals(plate)
	await wait_physics_frames(3)
	var start: Vector3 = plate.global_position
	var weapon := load("res://weapons/data/longwatch_sniper.tres") as WeaponData
	system.fire(Vector3(0, 1.5, 0), Vector3.FORWARD, weapon.projectile)
	for tick: int in 10:
		system.advance(1.0 / 60.0)
	assert_signal_emitted(plate, "rang")
	assert_true(plate.hinge.get_flag(HingeJoint3D.FLAG_USE_LIMIT))
	assert_eq(plate.hinge.node_b, NodePath())
	await wait_physics_frames(15)
	assert_gt(absf(plate.rotation.x), 0.01, "bullet momentum swings the plate")
	assert_lt(plate.global_position.distance_to(start), 0.7, "hinge retains the plate")
	# Let the placeholder playback finish before GUT tears down the scene.
	await wait_physics_frames(65)
