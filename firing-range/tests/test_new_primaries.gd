extends GutTest

const SMG: WeaponData = preload("res://weapons/data/rill_smg.tres")
const LMG: WeaponData = preload("res://weapons/data/foundry_lmg.tres")
const SHOTGUN: WeaponData = preload("res://weapons/data/breakwater_shotgun.tres")
const GUNS: Array[WeaponData] = [SMG, LMG, SHOTGUN]
const DT: float = 1.0 / 60.0


func test_new_weapon_definitions_match_the_phase_two_brief() -> void:
	assert_eq(SMG.magazine_size, 32)
	assert_eq(SMG.projectile.muzzle_velocity, 400.0)
	assert_eq(SMG.rounds_per_minute, 900.0)
	assert_eq(SMG.projectile.falloff_start_distance, 25.0)
	assert_eq(LMG.magazine_size, 100)
	assert_eq(LMG.projectile.muzzle_velocity, 850.0)
	assert_eq(LMG.rounds_per_minute, 700.0)
	assert_gt(LMG.ads_time, SMG.ads_time)
	assert_gt(LMG.sprint_to_fire_time, SMG.sprint_to_fire_time)
	assert_lt(LMG.aimed_recoil_scale, SMG.aimed_recoil_scale)
	assert_eq(SHOTGUN.magazine_size, 6)
	assert_eq(SHOTGUN.bolt_cycle_time, 0.8)
	assert_eq(SHOTGUN.delivery.pellet_count, 8)
	assert_eq(SHOTGUN.projectile.muzzle_velocity, 400.0)
	assert_eq(SHOTGUN.projectile.falloff_start_distance, 15.0)
	assert_eq(SHOTGUN.fire_mode.kind, FireModeData.Kind.PUMP_ACTION)
	assert_eq(SHOTGUN.reload_policy.kind, ReloadData.Kind.SHELL)
	for data: WeaponData in GUNS:
		assert_eq(data.role, WeaponTypes.Role.PRIMARY)
		assert_not_null(data.viewmodel_scene)


func test_fire_timing_for_every_new_primary_and_no_held_pump_repeat() -> void:
	for data: WeaponData in GUNS:
		var logic := WeaponLogic.new(data)
		logic.equip_instantly()
		var input := WeaponInput.new()
		input.trigger_held = true
		var times: Array[int] = []
		for tick: int in 181:
			input.trigger_pressed = data.fire_mode.kind == FireModeData.Kind.PUMP_ACTION or tick == 0
			if logic.tick(DT, input) > 0:
				times.append(tick)
			if times.size() == 5:
				break
		assert_gte(times.size(), 4, data.display_name)
		for index: int in range(1, times.size()):
			var ticks: int = times[index] - times[index - 1]
			if data == SMG:
				assert_eq(ticks, 4)
			elif data == LMG:
				assert_true(ticks == 5 or ticks == 6)
			else:
				assert_eq(ticks, 48)
		var elapsed: float = float(times[-1] - times[0]) * DT
		assert_almost_eq(elapsed, float(times.size() - 1) * data.shot_interval(), DT)
	var pump := WeaponLogic.new(SHOTGUN)
	pump.equip_instantly()
	var held := WeaponInput.new()
	held.trigger_held = true
	held.trigger_pressed = true
	assert_eq(pump.tick(DT, held), 1)
	held.trigger_pressed = false
	for tick: int in 180:
		assert_eq(pump.tick(DT, held), 0)
	assert_eq(pump.ammo, 5)


func test_smg_and_lmg_magazines_and_both_reload_durations() -> void:
	for data: WeaponData in [SMG, LMG]:
		for starting_ammo: int in [0, 1]:
			var logic := WeaponLogic.new(data)
			logic.equip_instantly()
			logic.ammo = starting_ammo
			var input := WeaponInput.new()
			input.reload_pressed = true
			logic.tick(DT, input)
			input.reload_pressed = false
			var frames: int = roundi(data.reload_time(starting_ammo) / DT)
			for tick: int in frames - 1:
				logic.tick(DT, input)
			assert_eq(logic.ammo, starting_ammo)
			logic.tick(DT, input)
			assert_eq(logic.ammo, data.magazine_size)
			assert_false(logic.is_reloading())


func test_native_shotgun_empty_reload_takes_four_seconds_and_loads_six() -> void:
	var logic := WeaponLogic.new(SHOTGUN)
	logic.equip_instantly()
	logic.ammo = 0
	var input := WeaponInput.new()
	input.reload_pressed = true
	logic.tick(DT, input)
	input.reload_pressed = false
	for tick: int in 239:
		logic.tick(DT, input)
	assert_true(logic.is_reloading())
	assert_eq(logic.ammo, 6)
	logic.tick(DT, input)
	assert_false(logic.is_reloading())


func test_all_catalog_attachments_fit_each_new_primary_without_mutating_base() -> void:
	var catalog := load("res://weapons/attachments/data/catalog.tres") as AttachmentCatalog
	for data: WeaponData in GUNS:
		var build := WeaponBuild.new(data)
		for attachment: AttachmentData in catalog.choices:
			if attachment.id == &"hybrid_35x" and data.weapon_class == WeaponTypes.Class.SHOTGUN:
				assert_false(build.set_attachment(attachment.slot, attachment))
				continue
			assert_true(build.set_attachment(attachment.slot, attachment))
			assert_not_null(build.get_stats())
			build.set_attachment(attachment.slot, null)
		assert_eq(build.get_stats().magazine_size, data.magazine_size)
		assert_eq(build.get_stats().projectile.muzzle_velocity, data.projectile.muzzle_velocity)
		assert_eq(build.get_stats().ads_position, data.ads_position)


func test_new_models_have_all_mounts_and_authored_native_sight_height() -> void:
	for data: WeaponData in GUNS:
		var model := data.viewmodel_scene.instantiate() as Node3D
		var post := model.get_node("FrontSightPost") as MeshInstance3D
		var muzzle := model.get_node("Muzzle") as Marker3D
		var tip: float = post.position.y + (post.mesh as BoxMesh).size.y * 0.5
		assert_almost_eq(tip - muzzle.position.y, data.sight_height_m, 0.000001)
		assert_almost_eq(muzzle.position.y, data.bore_height_m, 0.000001)
		for slot: String in WeaponTypes.SLOT_NAMES:
			assert_not_null(model.get_node_or_null("Mounts/" + slot))
		model.free()


func test_real_new_weapon_delivery_damage_and_stats_use_existing_target_path() -> void:
	var system := ProjectileSystem.new()
	add_child_autofree(system)
	system.set_physics_process(false)
	add_child_autofree(TargetHits.new())
	var dummy := TargetDummy.new()
	dummy.armor_plates = 3
	dummy.position.z = -2.0
	add_child_autofree(dummy)
	var feedback := RangeFeedback.new()
	add_child_autofree(feedback)
	var view := FeedbackView.new()
	add_child_autofree(view)
	feedback.feedback.connect(view.show_feedback)
	feedback.damage_total.connect(view.show_damage_total)
	await wait_physics_frames(2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	for data: WeaponData in GUNS:
		dummy.state.reset()
		var before: float = dummy.state.armor
		data.delivery.launch(system, Vector3(0, 1.18, 0), Vector3.FORWARD, data.projectile, rng)
		system.advance(DT)
		var count: int = 8 if data == SHOTGUN else 1
		assert_almost_eq(dummy.state.armor, before - data.projectile.damage * count, 0.001)
	assert_eq(feedback.stats.shots, 3)
	assert_eq(feedback.stats.hits, 3)
	assert_eq(feedback.stats.accuracy_percent(), 100.0)
	assert_eq((view.get_child(2) as Label).text, "144")
