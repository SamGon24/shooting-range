extends GutTest


func test_kill_reuses_six_parts_and_reset_restores_every_zone_exactly() -> void:
	var dummy := TargetDummy.new()
	dummy.position = Vector3(3, 0, -25)
	add_child_autofree(dummy)
	dummy.set_physics_process(false)
	var original: Array[Transform3D] = []
	for zone: TargetHitZone in dummy.zones:
		original.append(zone.transform)
	var count: int = get_tree().get_node_count()
	var hit := ProjectileHit.new()
	hit.spec = ProjectileSpec.new()
	hit.spec.mass_grams = 10.9
	hit.damage = 400.0
	hit.velocity = Vector3(0, 0, -900)
	hit.collider = dummy.zones[1]
	hit.position = dummy.zones[1].global_position
	dummy.receive_hit(hit, TargetSettings.Zone.TORSO)
	assert_true(dummy.ragdoll.active)
	assert_eq(dummy.ragdoll.parts.size(), 6)
	assert_eq(get_tree().get_node_count(), count, "kill allocates no nodes")
	for index: int in dummy.zones.size():
		assert_eq(dummy.zones[index].collision_layer, 0)
		assert_eq(dummy.ragdoll.parts[index].global_transform, dummy.zones[index].global_transform)
	await wait_physics_frames(8)
	assert_lt(dummy.ragdoll.parts[1].global_position.z, hit.position.z, "killing momentum carries the body downrange")
	dummy.advance(2.99)
	assert_true(dummy.state.dead)
	dummy.advance(0.01)
	assert_false(dummy.ragdoll.active)
	assert_false(dummy.state.dead)
	for index: int in dummy.zones.size():
		assert_eq(dummy.zones[index].transform, original[index])
		assert_eq(dummy.zones[index].collision_layer, 1)
		assert_true(dummy.ragdoll.parts[index].freeze)
		assert_eq(dummy.ragdoll.parts[index].collision_layer, 0)
	assert_eq(get_tree().get_node_count(), count)


func test_a_moving_rail_does_not_drag_the_active_corpse() -> void:
	var rail := TargetRail.new()
	add_child_autofree(rail)
	rail.set_physics_process(false)
	var dummy := TargetDummy.new()
	rail.add_child(dummy)
	dummy.set_physics_process(false)
	var hit := ProjectileHit.new()
	hit.spec = ProjectileSpec.new()
	hit.damage = 400.0
	hit.position = dummy.zones[1].global_position
	dummy.receive_hit(hit, TargetSettings.Zone.TORSO)
	var position: Vector3 = dummy.ragdoll.parts[1].global_position
	rail.advance(0.5)
	assert_eq(dummy.ragdoll.parts[1].global_position, position)
	dummy.advance(3.0)
	assert_almost_eq(dummy.zones[1].global_position.x, rail.global_position.x, 0.001)
