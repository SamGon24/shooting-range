extends GutTest

const RIFLE: WeaponData = preload("res://weapons/data/halberd_rifle.tres")
const SNIPER: WeaponData = preload("res://weapons/data/longwatch_sniper.tres")


func _check_snapshot(resource: Resource, expected: Dictionary) -> void:
	for key: String in expected:
		var value: Variant = resource.get(key)
		if expected[key] is Dictionary:
			_check_snapshot(value, expected[key])
		elif value is PackedScene:
			assert_eq(value.resource_path, expected[key], key)
		else:
			assert_eq(var_to_str(value), expected[key], key)


func test_zero_attachments_match_every_frozen_milestone_6_stat() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/milestone_6_weapon_stats.json"))
	for name: String in expected:
		var base := load("res://weapons/data/%s.tres" % name) as WeaponData
		var build := WeaponBuild.new(base)
		_check_snapshot(build.get_stats(), expected[name])
		assert_ne(build.get_stats(), base)
		assert_ne(build.get_stats().projectile, base.projectile)


func _attachment(slot: WeaponTypes.Slot, stat: StringName, operation: StatModifier.Operation, value: float) -> AttachmentData:
	var attachment := AttachmentData.new()
	attachment.slot = slot
	attachment.compatible_classes = PackedInt32Array([WeaponTypes.Class.RIFLE])
	var modifier := StatModifier.new()
	modifier.stat = stat
	modifier.operation = operation
	modifier.value = value
	attachment.modifiers = [modifier]
	return attachment


func test_additions_precede_multipliers_independent_of_install_order() -> void:
	var a: AttachmentData = _attachment(WeaponTypes.Slot.MUZZLE, &"projectile.muzzle_velocity", StatModifier.Operation.MULTIPLY, 1.1)
	var b: AttachmentData = _attachment(WeaponTypes.Slot.BARREL, &"projectile.muzzle_velocity", StatModifier.Operation.ADD, 50.0)
	for reverse: bool in [false, true]:
		var build := WeaponBuild.new(RIFLE)
		build.set_attachment(b.slot, b) if reverse else build.set_attachment(a.slot, a)
		build.set_attachment(a.slot, a) if reverse else build.set_attachment(b.slot, b)
		assert_almost_eq(build.get_stats().projectile.muzzle_velocity, 990.0, 0.00001)
	assert_eq(RIFLE.projectile.muzzle_velocity, 850.0)


func test_clamps_once_and_rounds_integer_stats_once() -> void:
	var build := WeaponBuild.new(RIFLE)
	build.set_attachment(WeaponTypes.Slot.MUZZLE, _attachment(WeaponTypes.Slot.MUZZLE, &"magazine_size", StatModifier.Operation.ADD, 0.4))
	build.set_attachment(WeaponTypes.Slot.BARREL, _attachment(WeaponTypes.Slot.BARREL, &"magazine_size", StatModifier.Operation.MULTIPLY, 1.5))
	assert_eq(build.get_stats().magazine_size, 46)
	build.set_attachment(WeaponTypes.Slot.MUZZLE, _attachment(WeaponTypes.Slot.MUZZLE, &"ads_time", StatModifier.Operation.ADD, -100.0))
	assert_almost_eq(build.get_stats().ads_time, 0.05, 0.000001)
	build.set_attachment(WeaponTypes.Slot.BARREL, _attachment(WeaponTypes.Slot.BARREL, &"projectile.muzzle_velocity", StatModifier.Operation.MULTIPLY, 100.0))
	assert_eq(build.get_stats().projectile.muzzle_velocity, 1500.0)


func test_compatibility_invalid_modifiers_and_cache_boundaries() -> void:
	var build := WeaponBuild.new(SNIPER)
	var cached: WeaponData = build.get_stats()
	var attachment: AttachmentData = _attachment(WeaponTypes.Slot.STOCK, &"ads_time", StatModifier.Operation.ADD, 0.1)
	assert_false(build.set_attachment(attachment.slot, attachment))
	assert_eq(build.get_stats(), cached)
	assert_eq(build.computation_count, 1)
	attachment.compatible_classes = PackedInt32Array([WeaponTypes.Class.SNIPER])
	assert_true(build.set_attachment(attachment.slot, attachment))
	assert_ne(build.get_stats(), cached)
	for frame: int in 60:
		build.get_stats()
	assert_eq(build.computation_count, 2)
	assert_true(build.set_attachment(attachment.slot, attachment))
	build.get_stats()
	assert_eq(build.computation_count, 2)
	attachment = _attachment(WeaponTypes.Slot.MUZZLE, &"unknown", StatModifier.Operation.ADD, 1.0)
	assert_false(build.set_attachment(attachment.slot, attachment))
	for weapon_class: WeaponTypes.Class in [WeaponTypes.Class.ROCKET, WeaponTypes.Class.KNIFE, WeaponTypes.Class.SHIELD]:
		assert_false(WeaponTypes.allows_slot(weapon_class, WeaponTypes.Slot.MUZZLE))
	assert_false(WeaponTypes.allows_slot(WeaponTypes.Class.PISTOL, WeaponTypes.Slot.STOCK))
	assert_true(WeaponTypes.allows_slot(WeaponTypes.Class.PISTOL, WeaponTypes.Slot.OPTIC))


func test_loadout_comparison_mode_is_an_explicit_exception() -> void:
	var loadout := WeaponLoadout.new()
	loadout.primary = RIFLE
	loadout.secondary = SNIPER
	assert_false(loadout.is_valid())
	loadout.comparison_mode = true
	assert_true(loadout.is_valid())
	loadout.comparison_mode = false
	loadout.secondary = SNIPER.duplicate() as WeaponData
	loadout.secondary.role = WeaponTypes.Role.SECONDARY
	loadout.secondary.weapon_class = WeaponTypes.Class.PISTOL
	assert_true(loadout.is_valid())
