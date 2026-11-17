extends GutTest

const RANGE: PackedScene = preload("res://range/range.tscn")
const RIFLE: WeaponData = preload("res://weapons/data/halberd_rifle.tres")
const SMG: WeaponData = preload("res://weapons/data/rill_smg.tres")
const LMG: WeaponData = preload("res://weapons/data/foundry_lmg.tres")
const SHOTGUN: WeaponData = preload("res://weapons/data/breakwater_shotgun.tres")
var _weapons: WeaponController
var _hud: Hud
var _view: WeaponView
var _scene: Node


func before_each() -> void:
	_scene = RANGE.instantiate()
	add_child_autofree(_scene)
	_weapons = _scene.get_node("Player/Weapons") as WeaponController
	_hud = _scene.get_node("Hud") as Hud
	_view = _scene.get_node("Player/Head/CameraFeel/Camera/WeaponView") as WeaponView
	await wait_physics_frames(5)


func after_each() -> void:
	for action: StringName in [&"primary_next", &"fire", &"reload", &"aim"]:
		Input.action_release(action)


func _select(data: WeaponData) -> void:
	assert_true(_weapons.request_primary(data))
	await wait_physics_frames(90)
	assert_eq(_weapons.get_current_data().definition(), data)
	assert_eq(_weapons.get_current_logic().state, WeaponLogic.State.READY)


func test_f11_cycles_new_primaries_in_stable_order_with_only_two_carried_slots() -> void:
	for expected: WeaponData in [SMG, LMG, SHOTGUN, RIFLE]:
		Input.action_press("primary_next")
		await wait_physics_frames(1)
		Input.action_release("primary_next")
		await wait_physics_frames(90)
		assert_eq(_weapons.get_current_data().definition(), expected)
		assert_eq(_weapons.loadout.size(), 2)
		assert_eq(_weapons.get_logic(1).data.weapon_class, WeaponTypes.Class.SNIPER)
		assert_eq(_hud.get_weapon_name_text(), expected.display_name)
		assert_true(_view.is_model_shown())
		assert_eq(_view.get_current_model(), _view._models[expected])


func test_primary_exchange_keeps_ammo_attachments_and_weapon_keyed_pending_changes() -> void:
	await _select(SMG)
	var brake := load("res://weapons/attachments/data/baffle.tres") as AttachmentData
	_weapons.request_attachment(WeaponTypes.Slot.MUZZLE, brake)
	await wait_physics_frames(3)
	Input.action_press("fire")
	await wait_physics_frames(1)
	Input.action_release("fire")
	var quick := load("res://weapons/attachments/data/quick_mag.tres") as AttachmentData
	_weapons.request_attachment(WeaponTypes.Slot.MAGAZINE, quick)
	await _select(LMG)
	assert_null(_weapons.get_build(0).get_attachment(WeaponTypes.Slot.MAGAZINE))
	assert_eq(_weapons.get_current_logic().ammo, 100)
	await _select(SMG)
	assert_eq(_weapons.get_build(0).get_attachment(WeaponTypes.Slot.MUZZLE), brake)
	assert_eq(_weapons.get_build(0).get_attachment(WeaponTypes.Slot.MAGAZINE), quick)
	assert_eq(_weapons.get_current_logic().ammo, 26, "stored 31 rounds clamp to the new capacity, without refilling")
	assert_not_null(_view.get_current_model().get_node_or_null("Mounts/Muzzle/baffle/Exit/MuzzleFlash"))


func test_cancelling_primary_exchange_restores_ready_weapon_and_slot_switching() -> void:
	_weapons.request_primary(SMG)
	await wait_physics_frames(5)
	_weapons.request_primary(RIFLE)
	await wait_physics_frames(40)
	assert_eq(_weapons.get_current_data().definition(), RIFLE)
	assert_eq(_weapons.get_current_logic().state, WeaponLogic.State.READY)
	_weapons.request_primary(LMG)
	await wait_physics_frames(5)
	_weapons.request_switch(1)
	await wait_physics_frames(90)
	assert_eq(_weapons.get_current_slot(), 1)
	assert_eq(_weapons.get_current_logic().state, WeaponLogic.State.READY)


func test_shotgun_controller_launches_eight_pellets_per_shell_and_shows_reload_count() -> void:
	await _select(SHOTGUN)
	var system := get_tree().get_first_node_in_group(ProjectileSystem.GROUP) as ProjectileSystem
	var launched: Array[int] = []
	system.projectile_fired.connect(func(slot: int, _origin: Vector3, _velocity: Vector3, _spec: ProjectileSpec) -> void: launched.append(slot))
	_weapons.get_current_logic().ammo = 1
	Input.action_press("reload")
	await wait_physics_frames(3)
	Input.action_release("reload")
	assert_true(_hud.get_ammo_text().begins_with("LOADING 1 / 6"))
	Input.action_press("fire")
	await wait_physics_frames(1)
	Input.action_release("fire")
	await wait_physics_frames(15)
	assert_eq(launched.size(), 8)
	assert_eq(_weapons.get_current_logic().ammo, 0)
	assert_eq(_hud.get_ammo_text(), "0 / 6")
	assert_eq(_hud.feedback.stats.shots, 1)


func test_repeated_primary_selection_reuses_models_sounds_and_computed_builds() -> void:
	var initial_nodes: int = get_tree().get_node_count()
	for data: WeaponData in [SMG, LMG, SHOTGUN, RIFLE, SMG]:
		await _select(data)
		assert_eq(_weapons.get_build(0).computation_count, 1)
	assert_eq(get_tree().get_node_count(), initial_nodes)
