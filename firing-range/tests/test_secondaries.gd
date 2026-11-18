extends GutTest

const PISTOL: WeaponData = preload("res://weapons/data/wayline_pistol.tres")
const ROCKET: WeaponData = preload("res://weapons/data/cairn_launcher.tres")
const KNIFE: WeaponData = preload("res://weapons/data/latch_knife.tres")
const SHIELD: WeaponData = preload("res://weapons/data/palisade_shield.tres")
const SECONDARIES: Array[WeaponData] = [PISTOL, ROCKET, KNIFE, SHIELD]
const DT: float = 1.0 / 60.0


func test_real_default_loadout_is_strict_primary_secondary() -> void:
	var loadout := load("res://weapons/data/range_loadout.tres") as WeaponLoadout
	assert_false(loadout.comparison_mode)
	assert_true(loadout.is_valid())
	assert_eq(loadout.secondary, PISTOL)
	for data: WeaponData in SECONDARIES:
		assert_eq(data.role, WeaponTypes.Role.SECONDARY)
		assert_eq(data.fire_mode.kind, FireModeData.Kind.SEMI_AUTO)
		assert_not_null(data.viewmodel_scene)
	assert_eq(PISTOL.projectile.muzzle_velocity, 360.0)
	assert_eq(PISTOL.magazine_size, 15)
	assert_eq(PISTOL.rounds_per_minute, 400.0)
	assert_eq(ROCKET.projectile.muzzle_velocity, 120.0)
	assert_eq(ROCKET.projectile.gravity_scale, 0.15)
	assert_eq(ROCKET.projectile.explosion.arming_distance_m, 10.0)
	assert_eq(ROCKET.projectile.explosion.radius_m, 6.0)
	assert_eq(ROCKET.magazine_size, 1)
	assert_eq(KNIFE.delivery.contact.reach_m, 1.8)
	assert_eq(SHIELD.delivery.contact.reach_m, 1.5)
	assert_eq(SHIELD.movement_speed_scale, 0.8)


func test_pistol_press_timing_is_limited_to_four_hundred_rpm() -> void:
	var logic := WeaponLogic.new(PISTOL)
	logic.equip_instantly()
	var input := WeaponInput.new()
	input.trigger_pressed = true
	input.trigger_held = true
	var times: Array[int] = []
	for tick: int in 40:
		if logic.tick(DT, input) > 0:
			times.append(tick)
	assert_eq(times, [0, 9, 18, 27, 36] as Array[int])
	assert_eq(logic.ammo, 10)
	input.trigger_pressed = false
	for tick: int in 60:
		assert_eq(logic.tick(DT, input), 0, "holding a pistol trigger never repeats")
	assert_eq(logic.ammo, 10)


func test_pistol_reload_and_rocket_single_round_refill_use_resource_times() -> void:
	for data: WeaponData in [PISTOL, ROCKET]:
		for starting: int in ([0, 1] if data == PISTOL else [0]):
			var logic := WeaponLogic.new(data)
			logic.equip_instantly()
			logic.ammo = starting
			var input := WeaponInput.new()
			input.reload_pressed = true
			logic.tick(DT, input)
			input.reload_pressed = false
			for tick: int in roundi(data.reload_time(starting) / DT) - 1:
				logic.tick(DT, input)
			assert_eq(logic.ammo, starting)
			logic.tick(DT, input)
			assert_eq(logic.ammo, data.magazine_size)
	assert_eq(ROCKET.reload_policy.kind, ReloadData.Kind.SINGLE_ROUND)


func test_pistol_has_the_fastest_equip_and_holster_in_the_arsenal() -> void:
	var primaries := load("res://weapons/data/primary_catalog.tres") as WeaponCatalog
	for data: WeaponData in primaries.primaries + [ROCKET, KNIFE, SHIELD]:
		assert_lt(PISTOL.raise_time, data.raise_time)
		assert_lt(PISTOL.lower_time, data.lower_time)


func test_pistol_accepts_only_three_slots_and_other_secondaries_accept_none() -> void:
	var catalog := load("res://weapons/attachments/data/catalog.tres") as AttachmentCatalog
	var pistol := WeaponBuild.new(PISTOL)
	for attachment: AttachmentData in catalog.choices:
		var accepts: bool = attachment.slot in [WeaponTypes.Slot.MUZZLE, WeaponTypes.Slot.OPTIC, WeaponTypes.Slot.MAGAZINE]
		assert_eq(pistol.set_attachment(attachment.slot, attachment), accepts)
		if accepts:
			var computed: WeaponData = pistol.get_stats()
			if attachment.slot == WeaponTypes.Slot.OPTIC:
				assert_almost_eq(computed.ads_position.y, -computed.sight_height_m - PISTOL.bore_height_m, 0.000001)
			pistol.set_attachment(attachment.slot, null)
	for data: WeaponData in [ROCKET, KNIFE, SHIELD]:
		var build := WeaponBuild.new(data)
		for attachment: AttachmentData in catalog.choices:
			assert_false(build.set_attachment(attachment.slot, attachment))


func test_authored_contact_weapons_have_unlimited_ammo_free_attacks_and_no_ads() -> void:
	for data: WeaponData in [KNIFE, SHIELD]:
		assert_false(data.uses_ammo)
		assert_false(data.can_aim)
		assert_eq(data.delivery.kind, DeliveryData.Kind.MELEE)
		assert_eq(data.reload_policy.kind, ReloadData.Kind.NONE)
		assert_almost_eq(data.shot_interval(), 0.5 if data == KNIFE else 0.9, 0.000001)
		var logic := WeaponLogic.new(data)
		logic.equip_instantly()
		var input := WeaponInput.new()
		input.trigger_pressed = true
		input.trigger_held = true
		input.aim_held = true
		assert_eq(logic.tick(DT, input), 1)
		assert_eq(logic.ammo, 0)
		assert_false(logic.can_reload())
		input.trigger_pressed = false
		for tick: int in 90:
			assert_eq(logic.tick(DT, input), 0)
		assert_eq(logic.aim_progress, 0.0)


func test_new_models_have_muzzle_markers_and_correct_firearm_sight_geometry() -> void:
	for data: WeaponData in SECONDARIES:
		var model := data.viewmodel_scene.instantiate() as Node3D
		var muzzle := model.get_node_or_null("Muzzle") as Marker3D
		assert_not_null(muzzle)
		if data.uses_ammo:
			var post := model.get_node("FrontSightPost") as MeshInstance3D
			var tip: float = post.position.y + (post.mesh as BoxMesh).size.y * 0.5
			assert_almost_eq(tip - muzzle.position.y, data.sight_height_m, 0.000001)
			assert_almost_eq(muzzle.position.y, data.bore_height_m, 0.000001)
		if data == PISTOL:
			for slot: String in ["Muzzle", "Optic", "Magazine"]:
				assert_not_null(model.get_node_or_null("Mounts/" + slot))
		model.free()


func test_melee_swishes_are_cached_non_silent_and_distinct_from_gunshots() -> void:
	var sound: AudioStreamWAV = SfxFactory.swish(240.0, 0.2)
	assert_same(sound, SfxFactory.swish(240.0, 0.2))
	assert_eq(sound.data.size(), 8820)
	assert_ne(sound.data, SfxFactory.gunshot(240.0, 0.2).data)
	var nonzero: bool = false
	for index: int in range(0, sound.data.size(), 2):
		nonzero = nonzero or sound.data.decode_s16(index) != 0
	assert_true(nonzero)
