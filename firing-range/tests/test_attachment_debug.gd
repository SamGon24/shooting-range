extends GutTest

const RANGE: PackedScene = preload("res://range/range.tscn")


func after_each() -> void:
	for action: String in AttachmentDebug.ACTIONS:
		Input.action_release(action)
	Input.action_release("attachment_clear")


func _tap(action: String) -> void:
	Input.action_press(action)
	await wait_physics_frames(1)
	Input.action_release(action)
	await wait_physics_frames(3)


func test_debug_actions_fit_cycle_and_clear_without_rebuilding_idle_stats() -> void:
	var scene: Node = RANGE.instantiate()
	add_child_autofree(scene)
	await wait_physics_frames(5)
	var controller := get_tree().get_first_node_in_group(WeaponController.GROUP) as WeaponController
	var build: WeaponBuild = controller.get_build(0)
	var native: WeaponData = build.get_stats()
	for action: String in AttachmentDebug.ACTIONS:
		await _tap(action)
	assert_eq(build.get_attachments().size(), 5)
	assert_eq(build.computation_count, 6, "one computation for each actual change")
	var view := scene.get_node("Player/Head/CameraFeel/Camera/WeaponView") as WeaponView
	var model: Node3D = view.get_current_model()
	for slot: String in WeaponTypes.SLOT_NAMES:
		assert_eq(model.get_node("Mounts/" + slot).get_child_count(), 1)
	for index: int in 3:
		await _tap("attachment_muzzle")
	assert_null(build.get_attachment(WeaponTypes.Slot.MUZZLE), "cycle includes native")
	await _tap("attachment_muzzle")
	assert_not_null(model.get_node_or_null("Mounts/Muzzle/baffle/Exit/MuzzleFlash"), "flash survives freeing and replacing muzzle parts")
	var computations: int = build.computation_count
	await wait_physics_frames(12)
	assert_eq(build.computation_count, computations, "no per-tick recomputation")
	assert_eq(controller.get_current_logic().ammo, native.magazine_size, "fitting a bigger magazine gives no free rounds")
	await _tap("attachment_clear")
	assert_eq(build.get_attachments().size(), 0)
	assert_eq(build.computation_count, computations + 1, "clear batches five slots into one computation")
	assert_eq(build.get_stats().magazine_size, native.magazine_size)
	assert_eq(build.get_stats().ads_position, native.ads_position)
	assert_not_null(model.get_node_or_null("FrontSightPost"))
	assert_not_null(model.get_node_or_null("Muzzle/MuzzleFlash"))
	for slot: String in WeaponTypes.SLOT_NAMES:
		assert_eq(model.get_node("Mounts/" + slot).get_child_count(), 0)
	await _tap("attachment_clear")
	assert_eq(build.computation_count, computations + 1, "clearing an empty build is a no-op")
