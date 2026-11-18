extends GutTest

const CATALOG: AttachmentCatalog = preload("res://weapons/attachments/data/catalog.tres")
const RIFLE: WeaponData = preload("res://weapons/data/halberd_rifle.tres")
const SNIPER: WeaponData = preload("res://weapons/data/longwatch_sniper.tres")


func test_catalog_has_unique_compatible_mounted_tradeoffs_in_every_slot() -> void:
	var ids: Dictionary[StringName, bool] = {}
	for attachment: AttachmentData in CATALOG.choices:
		assert_false(ids.has(attachment.id))
		ids[attachment.id] = true
		assert_true(attachment.accepts(RIFLE.weapon_class))
		assert_eq(attachment.accepts(SNIPER.weapon_class), attachment.id != &"hybrid_35x")
		var part := attachment.part_scene.instantiate() as Node3D
		assert_not_null(part.get_node_or_null(attachment.part_mount))
		part.free()
		var benefit: bool = attachment.optic_kind >= 2
		var cost: bool = false
		for modifier: StatModifier in attachment.modifiers:
			var delta: float = modifier.value if modifier.operation == StatModifier.Operation.ADD else modifier.value - 1.0
			var lower_is_better: bool = modifier.stat in [&"ads_time", &"recoil_scale", &"hip_spread_degrees", &"aimed_spread_degrees", &"reload_tactical_time", &"reload_empty_time", &"raise_time"]
			benefit = benefit or (delta < 0.0 if lower_is_better else delta > 0.0)
			cost = cost or (delta > 0.0 if lower_is_better else delta < 0.0)
		assert_true(benefit and cost, attachment.display_name + " is a trade-off")
	for slot: int in WeaponTypes.SLOT_NAMES.size():
		var count: int = CATALOG.for_slot(slot as WeaponTypes.Slot, RIFLE.weapon_class).size()
		assert_eq(count, 6 if slot == WeaponTypes.Slot.OPTIC else 3)


func test_optics_set_zoom_reticle_sight_height_and_restore_native_stats() -> void:
	for base: WeaponData in [RIFLE, SNIPER]:
		var build := WeaponBuild.new(base)
		for optic: AttachmentData in CATALOG.for_slot(WeaponTypes.Slot.OPTIC, base.weapon_class):
			assert_true(build.set_attachment(WeaponTypes.Slot.OPTIC, optic))
			var computed: WeaponData = build.get_stats()
			assert_almost_eq(computed.ads_fov_degrees, optic.optic_fov_degrees, 0.000001)
			assert_eq(computed.optic_kind, optic.optic_kind)
			assert_almost_eq(computed.sight_height_m, optic.optic_sight_height_m, 0.000001)
			assert_eq(computed.scoped, optic.optic_kind >= 2 and optic.optic_kind <= 4)
			assert_almost_eq(computed.ads_position.y + base.bore_height_m + computed.sight_height_m, 0.0, 0.000001)
		build.set_attachment(WeaponTypes.Slot.OPTIC, null)
		assert_eq(build.get_stats().ads_fov_degrees, base.ads_fov_degrees)
		assert_eq(build.get_stats().scoped, base.scoped)
		assert_eq(build.get_stats().ads_position, base.ads_position)


func test_cycle_includes_none_and_skips_incompatible_slots() -> void:
	var current: AttachmentData
	for index: int in 3:
		current = CATALOG.next_attachment(current, WeaponTypes.Slot.MUZZLE, WeaponTypes.Class.RIFLE)
		assert_not_null(current)
	current = CATALOG.next_attachment(current, WeaponTypes.Slot.MUZZLE, WeaponTypes.Class.RIFLE)
	assert_null(current)
	assert_null(CATALOG.next_attachment(null, WeaponTypes.Slot.STOCK, WeaponTypes.Class.PISTOL))
	assert_null(CATALOG.next_attachment(null, WeaponTypes.Slot.MUZZLE, WeaponTypes.Class.ROCKET))
