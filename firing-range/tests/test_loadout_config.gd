extends GutTest

const PATH: String = "/tmp/gut_m11_loadout.cfg"
const RIFLE: WeaponData = preload("res://weapons/data/halberd_rifle.tres")
const PISTOL: WeaponData = preload("res://weapons/data/wayline_pistol.tres")
const MAG: AttachmentData = preload("res://weapons/attachments/data/extended_mag.tres")
const BARREL: AttachmentData = preload("res://weapons/attachments/data/long_barrel.tres")


func after_each() -> void:
	DirAccess.remove_absolute(PATH)


func test_all_weapons_and_attachments_survive_round_trip_without_loading_paths() -> void:
	var source := LoadoutConfig.new()
	for role: WeaponTypes.Role in [WeaponTypes.Role.PRIMARY, WeaponTypes.Role.SECONDARY]:
		for definition: WeaponData in source.choices(role):
			assert_true(source.select(role, definition))
			for slot: int in WeaponTypes.SLOT_NAMES.size():
				var choices: Array[AttachmentData] = LoadoutConfig.ATTACHMENTS.for_slot(slot as WeaponTypes.Slot, definition.weapon_class)
				if not choices.is_empty():
					assert_true(source.set_attachment(definition, slot as WeaponTypes.Slot, choices.back()))
	assert_eq(source.save_to_disk(PATH), OK)
	var restored := LoadoutConfig.new()
	assert_eq(restored.load_from_disk(PATH), OK)
	assert_same(restored.primary, source.primary)
	assert_same(restored.secondary, source.secondary)
	for role: WeaponTypes.Role in [WeaponTypes.Role.PRIMARY, WeaponTypes.Role.SECONDARY]:
		for definition: WeaponData in source.choices(role):
			assert_eq(restored.get_build(definition).get_attachments(), source.get_build(definition).get_attachments())
			assert_eq(restored.get_build(definition).get_stats().magazine_size, source.get_build(definition).get_stats().magazine_size)


func test_invalid_roles_unknown_resources_and_incompatible_attachments_are_rejected() -> void:
	var config := LoadoutConfig.new()
	assert_false(config.select(WeaponTypes.Role.PRIMARY, PISTOL))
	assert_false(config.select(WeaponTypes.Role.SECONDARY, RIFLE))
	assert_false(config.select(WeaponTypes.Role.PRIMARY, RIFLE.duplicate() as WeaponData))
	assert_false(config.set_attachment(PISTOL, WeaponTypes.Slot.BARREL, BARREL))
	assert_false(config.set_attachment(RIFLE, WeaponTypes.Slot.MUZZLE, MAG))
	assert_false(config.set_attachment(RIFLE, WeaponTypes.Slot.MAGAZINE, MAG.duplicate() as AttachmentData))
	assert_true(config.set_attachment(RIFLE, WeaponTypes.Slot.MAGAZINE, MAG))
	assert_true(config.set_attachment(RIFLE, WeaponTypes.Slot.MAGAZINE, null))
	assert_null(config.get_build(RIFLE).get_attachment(WeaponTypes.Slot.MAGAZINE))


func test_invalid_file_entries_fall_back_independently_and_drafts_are_isolated() -> void:
	var file := ConfigFile.new()
	file.set_value("loadout", "version", 1)
	file.set_value("loadout", "primary", "res://not_a_weapon.gd")
	file.set_value("loadout", "secondary", RIFLE.resource_path)
	file.set_value(PISTOL.resource_path, "Barrel", String(BARREL.id))
	file.set_value(RIFLE.resource_path, "Magazine", String(MAG.id))
	file.set_value(RIFLE.resource_path, "Optic", 42)
	file.set_value(RIFLE.resource_path, "Muzzle", "unknown")
	assert_eq(file.save(PATH), OK)
	var config := LoadoutConfig.new()
	assert_eq(config.load_from_disk(PATH), OK)
	assert_same(config.primary, RIFLE)
	assert_same(config.secondary, PISTOL)
	assert_null(config.get_build(PISTOL).get_attachment(WeaponTypes.Slot.BARREL))
	assert_same(config.get_build(RIFLE).get_attachment(WeaponTypes.Slot.MAGAZINE), MAG)
	var draft: LoadoutConfig = config.copy()
	assert_true(draft.set_attachment(RIFLE, WeaponTypes.Slot.MAGAZINE, null))
	assert_same(config.get_build(RIFLE).get_attachment(WeaponTypes.Slot.MAGAZINE), MAG)
	assert_eq(config.load_from_disk(PATH + ".missing"), ERR_FILE_NOT_FOUND)
	assert_true(config.get_build(RIFLE).get_attachments().is_empty())
	file.set_value("loadout", "version", 99)
	assert_eq(file.save(PATH), OK)
	assert_eq(config.load_from_disk(PATH), ERR_INVALID_DATA)


func test_controller_starts_with_saved_build_and_full_capacity_without_mutating_config() -> void:
	var config := LoadoutConfig.new()
	config.set_attachment(RIFLE, WeaponTypes.Slot.MAGAZINE, MAG)
	var player := preload("res://player/player.tscn").instantiate() as PlayerController
	var controller := player.get_node("Weapons") as WeaponController
	controller.initial_builds = [config.get_build(config.primary), config.get_build(config.secondary)]
	var world := Node3D.new()
	add_child_autofree(world)
	world.add_child(ProjectileSystem.new())
	world.add_child(player)
	await get_tree().process_frame
	assert_same(controller.get_current_data().definition(), RIFLE)
	assert_eq(controller.get_current_logic().ammo, config.get_build(RIFLE).get_stats().magazine_size)
	assert_same(controller.get_build(0).get_attachment(WeaponTypes.Slot.MAGAZINE), MAG)
	controller.get_build(0).set_attachment(WeaponTypes.Slot.MAGAZINE, null)
	assert_same(config.get_build(RIFLE).get_attachment(WeaponTypes.Slot.MAGAZINE), MAG)
