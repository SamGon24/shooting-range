extends GutTest

const RANGE: PackedScene = preload("res://range/range.tscn")
const RIFLE: WeaponData = preload("res://weapons/data/halberd_rifle.tres")
const SMG: WeaponData = preload("res://weapons/data/rill_smg.tres")
const PISTOL: WeaponData = preload("res://weapons/data/wayline_pistol.tres")
const ROCKET: WeaponData = preload("res://weapons/data/cairn_launcher.tres")
const KNIFE: WeaponData = preload("res://weapons/data/latch_knife.tres")
const SHIELD: WeaponData = preload("res://weapons/data/palisade_shield.tres")
var _scene: Node3D
var _weapons: WeaponController
var _player: PlayerController
var _system: ProjectileSystem
var _hud: Hud
var _view: WeaponView


func before_each() -> void:
	_scene = RANGE.instantiate() as Node3D
	add_child_autofree(_scene)
	_player = _scene.get_node("Player") as PlayerController
	_weapons = _player.get_node("Weapons") as WeaponController
	_system = _scene.get_node("Projectiles") as ProjectileSystem
	_hud = _scene.get_node("Hud") as Hud
	_view = _player.get_node("Head/CameraFeel/Camera/WeaponView") as WeaponView
	await wait_physics_frames(5)


func after_each() -> void:
	for action: StringName in [&"secondary_next", &"shield_test_fire", &"fire", &"aim", &"reload"]:
		Input.action_release(action)


func _select(data: WeaponData) -> void:
	assert_true(_weapons.request_secondary(data))
	await wait_physics_frames(90)
	assert_eq(_weapons.get_current_data().definition(), data)
	assert_eq(_weapons.get_current_logic().state, WeaponLogic.State.READY)


func test_physical_o_cycles_all_four_secondaries_and_retains_strict_slots() -> void:
	for expected: WeaponData in [ROCKET, KNIFE, SHIELD, PISTOL]:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_O
		event.pressed = true
		Input.parse_input_event(event)
		await wait_physics_frames(1)
		event = InputEventKey.new()
		event.physical_keycode = KEY_O
		Input.parse_input_event(event)
		await wait_physics_frames(90)
		assert_eq(_weapons.get_current_data().definition(), expected)
		assert_eq(_weapons.loadout.size(), 2)
		assert_eq(_weapons.get_logic(0).data.definition(), RIFLE)
		assert_eq(_weapons.get_logic(1).data.role, WeaponTypes.Role.SECONDARY)
		assert_eq(_hud.get_weapon_name_text(), expected.display_name)
	assert_eq(_player.weapon_speed_scale, 1.0)


func test_pistol_ammo_and_mounted_attachments_survive_secondary_exchange() -> void:
	await _select(PISTOL)
	var optic := load("res://weapons/attachments/data/red_dot.tres") as AttachmentData
	var magazine := load("res://weapons/attachments/data/quick_mag.tres") as AttachmentData
	_weapons.request_attachment(WeaponTypes.Slot.OPTIC, optic)
	_weapons.request_attachment(WeaponTypes.Slot.MAGAZINE, magazine)
	await wait_physics_frames(3)
	Input.action_press("fire")
	await wait_physics_frames(1)
	Input.action_release("fire")
	await _select(KNIFE)
	await _select(PISTOL)
	assert_eq(_weapons.get_current_logic().ammo, 11)
	assert_eq(_hud.get_ammo_text(), "11 / 12")
	assert_eq(_weapons.get_build(1).get_attachment(WeaponTypes.Slot.OPTIC), optic)
	assert_eq(_weapons.get_build(1).get_attachment(WeaponTypes.Slot.MAGAZINE), magazine)
	assert_not_null(_view.get_current_model().get_node_or_null("Mounts/Optic/red_dot"))


func test_cancelled_and_cross_slot_requests_obey_the_last_selection_and_roles() -> void:
	_weapons.request_secondary(ROCKET)
	await wait_physics_frames(5)
	_weapons.request_secondary(PISTOL)
	await wait_physics_frames(60)
	assert_eq(_weapons.get_current_data().definition(), PISTOL)
	_weapons.request_primary(SMG)
	await wait_physics_frames(5)
	_weapons.request_secondary(SHIELD)
	await wait_physics_frames(90)
	assert_eq(_weapons.get_current_data().definition(), SHIELD)
	assert_eq(_weapons.get_logic(0).data.definition(), RIFLE)
	assert_false(_weapons.request_primary(PISTOL))
	assert_false(_weapons.request_secondary(RIFLE))


func test_shield_blocks_training_round_without_stats_then_bashes_without_a_bullet_or_flash() -> void:
	await _select(SHIELD)
	var hits: Array[ProjectileHit] = []
	_system.projectile_hit.connect(func(hit: ProjectileHit) -> void: hits.append(hit))
	assert_eq(_player.weapon_speed_scale, 0.8)
	assert_eq(_weapons._guard.collision_layer, 8)
	Input.action_press("shield_test_fire")
	await wait_physics_frames(1)
	Input.action_release("shield_test_fire")
	await wait_physics_frames(15)
	assert_eq(hits.size(), 1)
	assert_eq(hits[0].collider, _weapons._guard)
	assert_eq(_hud.feedback.stats.shots, 0)
	assert_eq(_hud.feedback.stats.hits, 0)
	watch_signals(_view)
	Input.action_press("fire")
	await wait_physics_frames(1)
	Input.action_release("fire")
	assert_eq(_hud.feedback.stats.shots, 1)
	assert_eq(_system.get_active_count(), 0)
	assert_eq(_hud.get_ammo_text(), "MELEE")
	assert_signal_not_emitted(_view, "muzzle_flashed")
	_weapons.request_switch(0)
	await wait_physics_frames(60)
	assert_eq(_weapons._guard.collision_layer, 0)
	assert_eq(_player.weapon_speed_scale, 1.0)


func test_knife_controller_hits_a_real_dummy_through_the_shared_damage_pipeline() -> void:
	await _select(KNIFE)
	var dummy := _scene.get_node("Targets/Dummy25m") as TargetDummy
	_player.teleport(dummy.global_position + Vector3(0, 0, 1.2))
	await wait_physics_frames(3)
	Input.action_press("fire")
	await wait_physics_frames(1)
	Input.action_release("fire")
	assert_true(dummy.state.dead)
	assert_eq(_hud.feedback.stats.shots, 1)
	assert_eq(_hud.feedback.stats.hits, 1)
	assert_eq(_hud.feedback.stats.headshots, 1)
	assert_eq(_hud.feedback.stats.last_time_to_kill, 0.0)
	assert_eq(_hud.get_ammo_text(), "MELEE")
	assert_eq(_system.get_active_count(), 0)


func test_rocket_controller_uses_one_round_and_scores_one_torso_splash_hit() -> void:
	await _select(ROCKET)
	var dummy := _scene.get_node("Targets/Dummy25m") as TargetDummy
	var sources: Array[DamageSource.Kind] = []
	dummy.damaged.connect(func(hit: ProjectileHit, _zone: TargetSettings.Zone, _amount: float) -> void: sources.append(hit.source))
	_player.teleport(Vector3(dummy.global_position.x, 0, 0))
	_player.pitch = -atan(0.35 / 25.0)
	Input.action_press("aim")
	await wait_physics_frames(30)
	Input.action_press("fire")
	await wait_physics_frames(1)
	Input.action_release("fire")
	await wait_physics_frames(20)
	assert_eq(_weapons.get_current_logic().ammo, 0)
	assert_true(dummy.state.dead)
	assert_eq(sources, [DamageSource.Kind.SPLASH] as Array[DamageSource.Kind])
	assert_eq(_hud.feedback.stats.shots, 1)
	assert_eq(_hud.feedback.stats.hits, 1)
	assert_eq(_hud.feedback.stats.headshots, 0)
