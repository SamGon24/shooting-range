extends GutTest

const RIFLE: WeaponData = preload("res://weapons/data/halberd_rifle.tres")
const PISTOL: WeaponData = preload("res://weapons/data/wayline_pistol.tres")
const SHOTGUN: WeaponData = preload("res://weapons/data/breakwater_shotgun.tres")
const SCOPE: AttachmentData = preload("res://weapons/attachments/data/scope_4x.tres")
const MAG: AttachmentData = preload("res://weapons/attachments/data/quick_mag.tres")
const BARREL: AttachmentData = preload("res://weapons/attachments/data/long_barrel.tres")
const PATH: String = "/tmp/gut_m11_armory.cfg"


func after_each() -> void:
	DirAccess.remove_absolute(PATH)


func _armory() -> Armory:
	var screen := Armory.new()
	screen.config = LoadoutConfig.new()
	screen.save_path = PATH
	add_child_autoqfree(screen)
	return screen


func _row(rows: Array[Dictionary], label: String) -> Dictionary:
	for row: Dictionary in rows:
		if row.label == label:
			return row
	fail_test("Missing comparison row: " + label)
	return {}


func test_comparison_uses_real_build_values_units_and_fixed_zoom_reference() -> void:
	var build := WeaponBuild.new(RIFLE)
	build.set_attachment(WeaponTypes.Slot.BARREL, BARREL)
	build.set_attachment(WeaponTypes.Slot.MAGAZINE, MAG)
	build.set_attachment(WeaponTypes.Slot.OPTIC, SCOPE)
	var rows: Array[Dictionary] = StatComparison.rows(RIFLE, build.get_stats())
	var velocity: Dictionary = _row(rows, "Velocity")
	assert_eq(velocity.base, 850.0)
	assert_almost_eq(float(velocity.fitted), 935.0, 0.0001)
	assert_almost_eq(float(velocity.delta), 85.0, 0.0001)
	var reload: Dictionary = _row(rows, "Tactical reload")
	assert_almost_eq(float(reload.fitted), RIFLE.reload_tactical_time * 0.85, 0.0001)
	assert_true(reload.lower_better)
	var zoom: Dictionary = _row(rows, "Optic zoom")
	assert_almost_eq(float(zoom.fitted), 4.0, 0.001)
	assert_eq(StatComparison.format_value(0.25, "s"), "0.25 s")
	assert_eq(StatComparison.format_value(68.0, "m/s", true), "+68 m/s")
	var shotgun: Dictionary = _row(StatComparison.rows(SHOTGUN, SHOTGUN), "Full empty reload")
	assert_almost_eq(float(shotgun.base), 4.0, 0.0001)


func test_all_weapons_show_valid_delivery_specific_comparisons_without_recomputing() -> void:
	var config := LoadoutConfig.new()
	for role: WeaponTypes.Role in [WeaponTypes.Role.PRIMARY, WeaponTypes.Role.SECONDARY]:
		for definition: WeaponData in config.choices(role):
			var build: WeaponBuild = config.get_build(definition)
			for slot: int in WeaponTypes.SLOT_NAMES.size():
				var attachments: Array[AttachmentData] = config.attachment_catalog().for_slot(slot as WeaponTypes.Slot, definition.weapon_class)
				if not attachments.is_empty():
					build.set_attachment(slot as WeaponTypes.Slot, attachments.back())
			var stats: WeaponData = build.get_stats()
			var count: int = build.computation_count
			for row: Dictionary in StatComparison.rows(definition, stats):
				assert_true(is_finite(float(row.base)) and is_finite(float(row.fitted)))
				assert_almost_eq(float(row.delta), float(row.fitted) - float(row.base), 0.00001)
			assert_eq(build.computation_count, count)
			assert_same(build.get_stats(), stats)


func test_armory_edits_an_isolated_draft_rejects_invalid_parts_and_preserves_each_gun() -> void:
	var screen: Armory = _armory()
	assert_true(screen.set_attachment(WeaponTypes.Slot.BARREL, BARREL))
	assert_null(screen.config.get_build(RIFLE).get_attachment(WeaponTypes.Slot.BARREL))
	screen.select_role(WeaponTypes.Role.SECONDARY)
	assert_same(screen.draft.selection(screen.role), PISTOL)
	assert_true(screen.attachment_pickers[WeaponTypes.Slot.BARREL].disabled)
	assert_true(screen.attachment_pickers[WeaponTypes.Slot.STOCK].disabled)
	assert_false(screen.set_attachment(WeaponTypes.Slot.BARREL, BARREL))
	assert_false(screen.select_weapon(RIFLE))
	for definition: WeaponData in screen.draft.choices(WeaponTypes.Role.SECONDARY):
		assert_true(screen.select_weapon(definition))
		if definition.weapon_class != WeaponTypes.Class.PISTOL:
			for picker: OptionButton in screen.attachment_pickers:
				assert_true(picker.disabled)
	screen.select_role(WeaponTypes.Role.PRIMARY)
	assert_same(screen.draft.get_build(RIFLE).get_attachment(WeaponTypes.Slot.BARREL), BARREL)
	var build: WeaponBuild = screen.draft.get_build(RIFLE)
	var count: int = build.computation_count
	screen.refresh()
	assert_eq(build.computation_count, count)
	watch_signals(screen)
	screen.save()
	assert_signal_emit_count(screen, "saved", 1)
	var restored := LoadoutConfig.new()
	assert_eq(restored.load_from_disk(PATH), OK)
	assert_same(restored.secondary, screen.draft.secondary)
	assert_same(restored.get_build(RIFLE).get_attachment(WeaponTypes.Slot.BARREL), BARREL)


func test_failed_save_keeps_draft_open_and_cancel_emits_without_writing() -> void:
	var screen: Armory = _armory()
	watch_signals(screen)
	screen.save_path = "/tmp/m11-missing-directory/loadout.cfg"
	screen.save()
	assert_signal_not_emitted(screen, "saved")
	assert_true(screen.is_inside_tree())
	screen.cancel_button.pressed.emit()
	assert_signal_emit_count(screen, "cancelled", 1)
	assert_false(FileAccess.file_exists(PATH))


func test_preview_poses_all_models_and_attachments_without_gameplay_or_accumulation() -> void:
	var preview := WeaponPreview.new()
	add_child_autoqfree(preview)
	var config := LoadoutConfig.new()
	for role: WeaponTypes.Role in [WeaponTypes.Role.PRIMARY, WeaponTypes.Role.SECONDARY]:
		for definition: WeaponData in config.choices(role):
			var build: WeaponBuild = config.get_build(definition)
			for slot: int in WeaponTypes.SLOT_NAMES.size():
				var attachments: Array[AttachmentData] = config.attachment_catalog().for_slot(slot as WeaponTypes.Slot, definition.weapon_class)
				if not attachments.is_empty():
					build.set_attachment(slot as WeaponTypes.Slot, attachments.back())
			preview.show_build(build)
			var model: Node3D = preview.get("_model")
			var rest: Transform3D = model.transform
			for frame: int in 3:
				preview.call("_process", 1.0 / 60.0)
			assert_eq(model.transform, rest)
			assert_true((preview.get("_viewport") as SubViewport).own_world_3d)
			assert_eq(preview.get_child_count(), 1)
			preview.demonstrate()
			preview.call("_physics_process", 1.0 / 60.0)
			assert_true(preview.logic.is_reloading() if definition.uses_ammo else preview.logic.get_time_to_next_shot() > 0.0)
			assert_same(build.get_stats(), preview.logic.data)
			assert_eq(definition.projectile.damage, build.base.projectile.damage)


func test_controls_fit_the_720p_viewport_and_preview_renders_at_its_actual_size() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child_autoqfree(viewport)
	var screen := Armory.new()
	screen.config = LoadoutConfig.new()
	viewport.add_child(screen)
	await wait_process_frames(3)
	assert_lte(screen.save_button.get_global_rect().end.y, screen.get_viewport_rect().end.y)
	assert_lte(screen.attachment_pickers.back().get_global_rect().end.y, screen.save_button.get_global_rect().position.y)
	assert_eq(screen.preview.stretch_shrink, 1)
