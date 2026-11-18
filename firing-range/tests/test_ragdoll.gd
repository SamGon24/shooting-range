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


## Jolt enforces cone-twist limits softly and Godot exposes no stiffness for
## it, so hard hits overshoot a little. Measured worst case in this scenario:
## about 12 degrees of swing (neck) and 13 of twist (neck).
const SWING_OVERSHOOT_DEGREES: float = 22.0
const TWIST_OVERSHOOT_DEGREES: float = 22.0


func _add_floor() -> void:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(60.0, 1.0, 60.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	body.position = Vector3(0.0, -0.5, 0.0)
	add_child_autofree(body)


func _kill(dummy: TargetDummy) -> void:
	var hit := ProjectileHit.new()
	hit.spec = ProjectileSpec.new()
	hit.damage = 400.0
	hit.velocity = Vector3(0.0, 0.0, -900.0)
	hit.position = dummy.zones[1].global_position
	dummy.receive_hit(hit, TargetSettings.Zone.TORSO)


## Swing and twist of a limb relative to the torso about its joint's axis.
func _joint_angles(ragdoll: DummyRagdoll, joint: int) -> Vector2:
	var axis: Vector3 = DummyRagdoll.AXES[joint]
	var torso: Basis = ragdoll.parts[1].global_basis
	var part: Basis = ragdoll.parts[DummyRagdoll.ATTACHED_PARTS[joint]].global_basis
	var swing: float = rad_to_deg((torso * axis).angle_to(part * axis))
	var relative: Quaternion = (torso.inverse() * part).get_rotation_quaternion()
	var twist: float = rad_to_deg(2.0 * atan2(Vector3(relative.x, relative.y, relative.z).dot(axis), relative.w))
	return Vector2(swing, absf(wrapf(twist, -180.0, 180.0)))


## Kills a dummy and hits every part with the same seeded kicks every 25
## ticks. Returns the worst swing and twist seen per joint. `unlimited`
## opens every joint's cone fully, standing in for the old pin joints.
func _worst_angles(unlimited: bool) -> Dictionary:
	_add_floor()
	var dummy := TargetDummy.new()
	dummy.position = Vector3(0.0, 0.0, -5.0)
	add_child_autofree(dummy)
	dummy.set_physics_process(false)
	_kill(dummy)
	var ragdoll: DummyRagdoll = dummy.ragdoll
	if unlimited:
		for joint: ConeTwistJoint3D in ragdoll._joints:
			joint.swing_span = PI
			joint.twist_span = PI
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var swing: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	var twist: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
	for tick: int in 150:
		if tick % 25 == 0 and tick < 100:
			for part: RigidBody3D in ragdoll.parts:
				var kick := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.2, 1.0), rng.randf_range(-1.0, 1.0))
				part.apply_impulse(kick.normalized() * part.mass * 3.0, Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.3, 0.3), 0.0))
		await wait_physics_frames(1)
		for joint: int in 5:
			var angles: Vector2 = _joint_angles(ragdoll, joint)
			swing[joint] = maxf(swing[joint], angles.x)
			twist[joint] = maxf(twist[joint], angles.y)
	return {"swing": swing, "twist": twist, "limits_swing": ragdoll.swing_limit_degrees, "limits_twist": ragdoll.twist_limit_degrees}


func test_limbs_stay_near_their_swing_and_twist_limits_under_hard_hits() -> void:
	var worst: Dictionary = await _worst_angles(false)
	for joint: int in 5:
		assert_lte(worst.swing[joint], worst.limits_swing[joint] + SWING_OVERSHOOT_DEGREES, "swing of joint %d" % joint)
		assert_lte(worst.twist[joint], worst.limits_twist[joint] + TWIST_OVERSHOOT_DEGREES, "twist of joint %d" % joint)
	assert_gt(worst.swing.max(), 30.0, "the hits really flexed the joints")


func test_the_same_hits_fold_limbs_much_further_without_limits() -> void:
	var limited: Dictionary = await _worst_angles(false)
	var free: Dictionary = await _worst_angles(true)
	gut.p("limited swing %s twist %s" % [limited.swing, limited.twist])
	gut.p("free swing %s twist %s" % [free.swing, free.twist])
	var folded: int = 0
	for joint: int in 5:
		if free.swing[joint] > limited.swing[joint] + 20.0 or free.twist[joint] > limited.twist[joint] + 20.0:
			folded += 1
	assert_gte(folded, 3, "most joints would have gone well past their limits")
	for joint: int in [1, 2, 3, 4]:
		assert_lt(limited.swing[joint], 120.0, "no limb folds up past the torso")


func test_every_joint_is_a_cone_twist_with_its_limits_and_axis() -> void:
	var dummy := TargetDummy.new()
	add_child_autofree(dummy)
	dummy.set_physics_process(false)
	var ragdoll: DummyRagdoll = dummy.ragdoll
	assert_eq(ragdoll._joints.size(), 5)
	for index: int in 5:
		var joint: ConeTwistJoint3D = ragdoll._joints[index]
		assert_almost_eq(joint.swing_span, deg_to_rad(ragdoll.swing_limit_degrees[index]), 0.0001)
		assert_almost_eq(joint.twist_span, deg_to_rad(ragdoll.twist_limit_degrees[index]), 0.0001)
		assert_almost_eq((joint.global_basis * Vector3.RIGHT).distance_to(DummyRagdoll.AXES[index]), 0.0, 0.0001, "twist axis along the limb")
		assert_almost_eq(joint.global_basis.determinant(), 1.0, 0.0001)
