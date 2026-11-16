extends GutTest


func test_hitmarker_priority_for_damage_outcomes() -> void:
	assert_eq(HitFeedback.pick(0, false), HitFeedback.Kind.HIT)
	assert_eq(HitFeedback.pick(1, false), HitFeedback.Kind.ARMOR_BREAK)
	assert_eq(HitFeedback.pick(3, false), HitFeedback.Kind.ARMOR_BREAK)
	assert_eq(HitFeedback.pick(0, true), HitFeedback.Kind.KILL)
	assert_eq(HitFeedback.pick(3, true), HitFeedback.Kind.KILL)


func test_existing_damage_signal_exposes_plate_breaks_and_kill_state() -> void:
	var dummy := TargetDummy.new()
	dummy.armor_plates = 3
	add_child_autofree(dummy)
	var kinds: Array[HitFeedback.Kind] = []
	dummy.damaged.connect(func(_hit: ProjectileHit, _zone: TargetSettings.Zone, _amount: float) -> void:
		kinds.append(HitFeedback.pick(dummy.last_plate_breaks, dummy.state.dead)))
	var hit := ProjectileHit.new()
	hit.spec = ProjectileSpec.new()
	hit.damage = 30.0
	dummy.receive_hit(hit, TargetSettings.Zone.TORSO)
	hit.damage = 20.0
	dummy.receive_hit(hit, TargetSettings.Zone.TORSO)
	hit.damage = 200.0
	dummy.receive_hit(hit, TargetSettings.Zone.TORSO)
	assert_eq(kinds, [HitFeedback.Kind.HIT, HitFeedback.Kind.ARMOR_BREAK, HitFeedback.Kind.KILL] as Array[HitFeedback.Kind])
	assert_eq(dummy.last_plate_breaks, 2)
	dummy.receive_hit(hit, TargetSettings.Zone.HEAD)
	assert_eq(kinds.size(), 3, "a down target emits no new feedback")
