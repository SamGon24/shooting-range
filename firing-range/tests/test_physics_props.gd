extends GutTest


func test_bullet_impulse_is_mass_times_velocity_for_both_props() -> void:
	for kind: PhysicsProp.Kind in [PhysicsProp.Kind.CRATE, PhysicsProp.Kind.BARREL]:
		var prop := PhysicsProp.new()
		prop.kind = kind
		prop.gravity_scale = 0.0
		add_child_autofree(prop)
		prop.linear_damp = 0.0
		prop.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		await wait_physics_frames(2)
		var hit := ProjectileHit.new()
		hit.spec = ProjectileSpec.new()
		hit.spec.mass_grams = 4.0
		hit.velocity = Vector3(0, 0, -850)
		hit.position = prop.global_position
		prop.receive_hit(hit)
		await wait_physics_frames(2)
		assert_almost_eq(prop.linear_velocity, Vector3(0, 0, -3.4 / prop.mass), Vector3.ONE * 0.001)
		prop.free()


func test_player_push_is_horizontal_and_force_limited() -> void:
	var prop := PhysicsProp.new()
	prop.gravity_scale = 0.0
	add_child_autofree(prop)
	prop.linear_damp = 0.0
	prop.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	await wait_physics_frames(2)
	prop.push(Vector3(1, 1, 0), Vector3(4.5, 0, 0), prop.global_position, 1.0 / 60.0)
	await wait_physics_frames(2)
	assert_almost_eq(prop.linear_velocity, Vector3(0.125, 0, 0), Vector3.ONE * 0.001)


func test_existing_projectile_report_moves_a_prop() -> void:
	var system := ProjectileSystem.new()
	add_child_autofree(system)
	system.set_physics_process(false)
	add_child_autofree(TargetHits.new())
	var prop := PhysicsProp.new()
	prop.position = Vector3(0, 0, -10)
	prop.gravity_scale = 0.0
	add_child_autofree(prop)
	prop.linear_damp = 0.0
	prop.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	await wait_physics_frames(2)
	var spec := ProjectileSpec.new()
	spec.gravity_scale = 0.0
	system.fire(Vector3.ZERO, Vector3.FORWARD, spec)
	system.advance(1.0 / 60.0)
	await wait_physics_frames(2)
	assert_almost_eq(prop.linear_velocity.z, -3.4 / 8.0, 0.001)
