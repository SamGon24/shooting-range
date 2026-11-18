extends GutTest
## The player scene with its weapons, a ProjectileSystem and a Jolt floor,
## driven through the input map with real physics ticks.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ACTIONS: Array[StringName] = [
	&"move_forward", &"sprint", &"fire", &"aim", &"reload", &"weapon_1", &"weapon_2",
]

var _world: Node3D
var _player: PlayerController
var _weapons: WeaponController
var _projectiles: ProjectileSystem
var _hits: Array[ProjectileHit] = []
var _rifle: WeaponData
var _sniper: WeaponData


func before_each() -> void:
	_hits.clear()
	_world = Node3D.new()
	add_child_autofree(_world)
	_add_slab(Vector3(400.0, 1.0, 400.0), Vector3(0.0, -0.5, 0.0))

	_projectiles = ProjectileSystem.new()
	_world.add_child(_projectiles)
	_projectiles.projectile_hit.connect(func(hit: ProjectileHit) -> void: _hits.append(hit))

	_player = PLAYER_SCENE.instantiate() as PlayerController
	(_player.get_node("Weapons") as WeaponController).loadout_definition = preload("res://tests/fixtures/mvp_loadout.tres")
	_world.add_child(_player)
	_weapons = _player.get_node("Weapons") as WeaponController
	_rifle = _weapons.loadout[0]
	_sniper = _weapons.loadout[1]
	_weapons.reseed(99)
	await wait_physics_frames(5)


func after_each() -> void:
	for action: StringName in ACTIONS:
		Input.action_release(action)


func _add_slab(size: Vector3, centre: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	body.position = centre
	_world.add_child(body)
	return body


func _seconds(seconds: float) -> int:
	return roundi(seconds * float(Engine.physics_ticks_per_second))


## Taps an action for one physics tick.
func _tap(action: StringName) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)


# --- Setup ---


func test_starts_with_the_rifle_ready_and_the_sniper_holstered() -> void:
	assert_eq(_weapons.loadout.size(), 2)
	assert_eq(_weapons.get_current_data(), _rifle)
	assert_eq(_weapons.get_current_logic().state, WeaponLogic.State.READY)
	assert_eq(_weapons.get_logic(1).state, WeaponLogic.State.HOLSTERED)
	assert_eq(_weapons.get_current_logic().ammo, _rifle.magazine_size)


# --- Firing ---


## Holds aim until the current weapon is fully aimed.
func _aim_fully() -> void:
	Input.action_press("aim")
	await wait_physics_frames(_seconds(_weapons.get_current_data().ads_time) + 2)


func test_fire_launches_from_the_bore_with_the_equipped_zero() -> void:
	# Aimed and settled, so the first shot has no spread at all.
	_add_slab(Vector3(40.0, 40.0, 1.0), Vector3(0.0, 0.0, -30.5))
	await _aim_fully()
	watch_signals(_weapons)
	watch_signals(_projectiles)

	await _tap(&"fire")
	await wait_physics_frames(6)

	assert_signal_emitted(_weapons, "shot_fired")
	assert_signal_emitted(_projectiles, "projectile_fired")
	assert_gt(_hits.size(), 0, "the shot reached the wall 30 m away")
	if _hits.size() > 0:
		var hit: ProjectileHit = _hits[0]
		assert_almost_eq(hit.position.z, -30.0, 0.001)
		assert_almost_eq(hit.position.x, 0.0, 0.001, "straight down the aim line")
		var offset: float = SightZeroing.height_at_distance(_rifle.projectile, 30.0, _rifle.sight_height_m, _weapons.get_zero_angle(), 9.81, _projectiles.air_density, 1.0 / 60.0)
		assert_almost_eq(hit.position.y, _player.get_eye_position().y + offset, 0.003, "from bore height, with zero and gravity")
		assert_eq(hit.spec, _rifle.projectile)


func test_shots_follow_yaw_and_pitch() -> void:
	_player.yaw = deg_to_rad(90.0)  # Facing -X.
	_player.pitch = deg_to_rad(-45.0)
	await _aim_fully()
	var basis: Basis = _player.get_aim_basis()
	var origin: Vector3 = _player.get_eye_position() - basis.y * _rifle.sight_height_m
	var direction: Vector3 = (-basis.z).rotated(basis.x, _weapons.get_zero_angle())
	var expected_x: float = origin.x - origin.y / direction.y * direction.x
	await _tap(&"fire")
	await wait_physics_frames(4)
	assert_gt(_hits.size(), 0, "aimed down, so it hits the floor")
	if _hits.size() > 0:
		assert_almost_eq(_hits[0].position.y, 0.0, 0.001)
		assert_almost_eq(_hits[0].position.x, expected_x, 0.003, "bore offset and elevation rotate with gameplay aim")
		assert_almost_eq(_hits[0].position.z, 0.0, 0.01)


func test_holding_fire_empties_the_magazine_at_the_rifle_rate() -> void:
	watch_signals(_weapons)
	Input.action_press("fire")
	await wait_physics_frames(_seconds(1.0))
	Input.action_release("fire")
	var shots: int = get_signal_emit_count(_weapons, "shot_fired")
	# 700 rpm is 11.7 per second; allow a tick of slack either side.
	assert_between(shots, 11, 13)
	assert_eq(_weapons.get_current_logic().ammo, _rifle.magazine_size - shots)


func test_firing_does_not_create_nodes() -> void:
	await wait_physics_frames(2)
	var nodes_before: int = get_tree().get_node_count()
	Input.action_press("fire")
	await wait_physics_frames(_seconds(1.0))
	Input.action_release("fire")
	assert_eq(get_tree().get_node_count(), nodes_before, "30 rounds, no new nodes")


func test_ammo_changed_reports_each_shot() -> void:
	watch_signals(_weapons)
	await _tap(&"fire")
	await wait_physics_frames(2)
	assert_signal_emitted(_weapons, "ammo_changed")
	var parameters: Array = get_signal_parameters(_weapons, "ammo_changed")
	assert_eq(parameters[1], _rifle.magazine_size)
	assert_lt(int(parameters[0]), _rifle.magazine_size)


# --- Sprint ---


func test_sprinting_blocks_fire_and_aim() -> void:
	watch_signals(_weapons)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait_physics_frames(_seconds(0.5))
	assert_true(_player.is_sprinting)

	Input.action_press("fire")
	Input.action_press("aim")
	await wait_physics_frames(_seconds(0.5))
	assert_signal_not_emitted(_weapons, "shot_fired")
	assert_eq(_weapons.get_current_logic().aim_progress, 0.0)
	assert_eq(_player.look_sensitivity_scale, 1.0)

	Input.action_release("sprint")
	await wait_physics_frames(_seconds(0.5))
	assert_signal_emitted(_weapons, "shot_fired", "fires once the sprint ends")
	assert_eq(_weapons.get_current_logic().aim_progress, 1.0)


# --- Aim ---


func test_aiming_scales_look_sensitivity_by_the_weapon_value() -> void:
	Input.action_press("aim")
	await wait_physics_frames(_seconds(_rifle.ads_time) + 3)
	assert_eq(_weapons.get_current_logic().aim_progress, 1.0)
	assert_almost_eq(_player.look_sensitivity_scale, _rifle.ads_sensitivity_scale, 0.0001)

	Input.action_release("aim")
	await wait_physics_frames(_seconds(_rifle.ads_time) + 3)
	assert_almost_eq(_player.look_sensitivity_scale, 1.0, 0.0001)


func test_aim_blend_interpolates_between_ticks() -> void:
	Input.action_press("aim")
	await wait_physics_frames(4)
	var logic: WeaponLogic = _weapons.get_current_logic()
	assert_eq(_weapons.get_aim_blend(0.0), logic.previous_aim_progress)
	assert_eq(_weapons.get_aim_blend(1.0), logic.aim_progress)
	assert_between(_weapons.get_aim_blend(0.5), logic.previous_aim_progress, logic.aim_progress)


# --- Switching ---


func test_switch_lowers_the_rifle_then_raises_the_sniper() -> void:
	watch_signals(_weapons)
	await _tap(&"weapon_2")
	assert_eq(_weapons.get_current_data(), _rifle, "still the rifle while it lowers")
	assert_eq(_weapons.get_current_logic().state, WeaponLogic.State.LOWERING)

	await wait_physics_frames(_seconds(_rifle.lower_time) + 2)
	assert_eq(_weapons.get_current_data(), _sniper)
	assert_eq(_weapons.get_current_logic().state, WeaponLogic.State.RAISING)
	assert_signal_emitted_with_parameters(_weapons, "weapon_changed", [_sniper])

	await wait_physics_frames(_seconds(_sniper.raise_time) + 2)
	assert_eq(_weapons.get_current_logic().state, WeaponLogic.State.READY)
	assert_eq(_weapons.get_logic(0).state, WeaponLogic.State.HOLSTERED)


func test_cannot_fire_while_switching() -> void:
	watch_signals(_weapons)
	Input.action_press("weapon_2")
	await wait_physics_frames(2)
	Input.action_release("weapon_2")
	Input.action_press("fire")
	await wait_physics_frames(_seconds(_rifle.lower_time + _sniper.raise_time) - 4)
	assert_signal_not_emitted(_weapons, "shot_fired")


func test_each_weapon_keeps_its_own_ammo() -> void:
	Input.action_press("fire")
	await wait_physics_frames(_seconds(0.5))
	Input.action_release("fire")
	await wait_physics_frames(2)
	var rifle_ammo: int = _weapons.get_logic(0).ammo
	assert_lt(rifle_ammo, _rifle.magazine_size)

	await _tap(&"weapon_2")
	await wait_physics_frames(_seconds(_rifle.lower_time + _sniper.raise_time) + 4)
	assert_eq(_weapons.get_current_logic().ammo, _sniper.magazine_size, "sniper is full")
	assert_eq(_weapons.get_logic(0).ammo, rifle_ammo, "rifle kept its count")


func test_reload_cancelled_by_switching_keeps_ammo_consistent() -> void:
	watch_signals(_weapons)
	Input.action_press("fire")
	await wait_physics_frames(_seconds(0.5))
	Input.action_release("fire")
	await wait_physics_frames(8)
	var rifle_ammo: int = _weapons.get_logic(0).ammo

	await _tap(&"reload")
	await wait_physics_frames(_seconds(_rifle.reload_tactical_time * 0.5))
	assert_true(_weapons.get_current_logic().is_reloading(), "mid-reload")

	# Switch away halfway through the reload, then come back.
	await _tap(&"weapon_2")
	await wait_physics_frames(_seconds(_rifle.lower_time + _sniper.raise_time) + 4)
	assert_signal_emitted(_weapons, "reload_cancelled")
	assert_eq(_weapons.get_current_data(), _sniper)
	assert_eq(_weapons.get_logic(0).ammo, rifle_ammo, "the cancelled reload added nothing")

	await _tap(&"weapon_1")
	await wait_physics_frames(_seconds(_sniper.lower_time + _rifle.raise_time) + 4)
	assert_eq(_weapons.get_current_data(), _rifle)
	assert_eq(_weapons.get_current_logic().state, WeaponLogic.State.READY)
	assert_eq(_weapons.get_current_logic().ammo, rifle_ammo, "same count after switching back")
	assert_signal_not_emitted(_weapons, "reload_finished")

	# The rifle still fires and counts down from where it was.
	await _tap(&"fire")
	await wait_physics_frames(2)
	assert_lt(_weapons.get_current_logic().ammo, rifle_ammo)


func test_switching_back_mid_lower_keeps_the_same_weapon() -> void:
	_weapons.request_switch(1)
	await wait_physics_frames(_seconds(_rifle.lower_time * 0.5))
	_weapons.request_switch(0)
	await wait_physics_frames(_seconds(_rifle.raise_time) + 4)
	assert_eq(_weapons.get_current_data(), _rifle)
	assert_eq(_weapons.get_current_logic().state, WeaponLogic.State.READY)
	assert_eq(_weapons.get_logic(1).state, WeaponLogic.State.HOLSTERED)


func test_relative_switch_wraps_around() -> void:
	_weapons.request_switch_relative(1)
	await wait_physics_frames(_seconds(_rifle.lower_time + _sniper.raise_time) + 4)
	assert_eq(_weapons.get_current_slot(), 1)
	_weapons.request_switch_relative(1)
	await wait_physics_frames(_seconds(_sniper.lower_time + _rifle.raise_time) + 4)
	assert_eq(_weapons.get_current_slot(), 0, "next from the last slot wraps to the first")


func test_switching_to_the_current_weapon_does_nothing() -> void:
	await _tap(&"weapon_1")
	await wait_physics_frames(4)
	assert_eq(_weapons.get_current_logic().state, WeaponLogic.State.READY)


func test_a_click_shorter_than_one_tick_still_fires() -> void:
	# A real click arrives as input events. Press and release both land
	# before the next physics tick, so polling the action would see nothing.
	_weapons.request_switch(1)
	await wait_physics_frames(_seconds(_rifle.lower_time + _sniper.raise_time) + 4)
	watch_signals(_weapons)

	var press := InputEventAction.new()
	press.action = &"fire"
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = &"fire"
	release.pressed = false
	Input.parse_input_event(release)
	await wait_physics_frames(4)

	assert_signal_emit_count(_weapons, "shot_fired", 1)
	assert_eq(_weapons.get_current_logic().ammo, _sniper.magazine_size - 1)


func test_sniper_fires_one_round_per_pull_through_the_controller() -> void:
	_weapons.request_switch(1)
	await wait_physics_frames(_seconds(_rifle.lower_time + _sniper.raise_time) + 4)
	watch_signals(_weapons)
	Input.action_press("fire")
	await wait_physics_frames(_seconds(_sniper.bolt_cycle_time * 2.0))
	Input.action_release("fire")
	assert_signal_emit_count(_weapons, "shot_fired", 1, "holding the trigger fires once")


# --- Recoil ---


func test_a_burst_kicks_the_aim_up_and_it_recovers() -> void:
	var pitch_before: float = _player.pitch
	Input.action_press("fire")
	await wait_physics_frames(_seconds(0.5))
	Input.action_release("fire")
	await wait_physics_frames(1)
	var kicked: float = rad_to_deg(_player.recoil_pitch)
	# Six or seven shots of the pattern's 0.45-0.6 degrees, give or take.
	assert_between(kicked, 2.5, 4.5, "the view climbed")
	assert_eq(_player.pitch, pitch_before, "the base look angle is untouched")
	var aim: Vector3 = -_player.get_aim_basis().z
	assert_gt(aim.y, 0.0, "shots now leave above the original line")

	# 9 °/s after a 0.12 s delay: about 0.5 s for this kick.
	await wait_physics_frames(_seconds(_rifle.recoil_recovery_delay + kicked / _rifle.recoil_recovery_rate) + 3)
	assert_almost_eq(_player.recoil_pitch, 0.0, 0.0001, "fully recovered")
	assert_almost_eq(_player.recoil_yaw, 0.0, 0.0001)


func test_later_shots_in_a_burst_land_higher() -> void:
	_add_slab(Vector3(40.0, 40.0, 1.0), Vector3(0.0, 0.0, -30.5))
	await _aim_fully()
	Input.action_press("fire")
	await wait_physics_frames(_seconds(0.6))
	Input.action_release("fire")
	await wait_physics_frames(4)
	assert_gt(_hits.size(), 5)
	if _hits.size() > 5:
		# Aimed, five kicks climb about 2.2 degrees (1.15 m at 30 m); bloom
		# can move the sixth round by at most 0.75 degrees (0.39 m).
		assert_gt(_hits[5].position.y, _hits[0].position.y + 0.7, "the burst climbs")


func test_pulling_down_against_recoil_cancels_it() -> void:
	Input.action_press("fire")
	await wait_physics_frames(_seconds(0.3))
	Input.action_release("fire")
	await wait_physics_frames(1)
	var kicked: float = _player.recoil_pitch
	var view_before: float = _player.pitch + _player.recoil_pitch
	# Mouse down by half the kick: the view drops by that much, taken out of
	# the recoil offset rather than the base angle.
	var counts: float = kicked * 0.5 / (deg_to_rad(ViewSettings.mouse_sensitivity) * _player.look_sensitivity_scale)
	_player._apply_look(Vector2(0.0, counts))
	assert_almost_eq(_player.pitch + _player.recoil_pitch, view_before - kicked * 0.5, 0.00001)
	assert_almost_eq(_player.recoil_pitch, kicked * 0.5, 0.00001, "half the kick left to recover")



# --- Spread ---


func test_first_aimed_shot_is_exact_and_bloom_spreads_the_rest() -> void:
	_add_slab(Vector3(40.0, 40.0, 1.0), Vector3(0.0, 0.0, -30.5))
	await _aim_fully()
	var basis: Basis = _player.get_aim_basis()
	var aim_before: Vector3 = (-basis.z).rotated(basis.x, _weapons.get_zero_angle())
	var directions: Array[Vector3] = []
	_projectiles.projectile_fired.connect(
		func(_slot: int, _origin: Vector3, velocity: Vector3, _spec: ProjectileSpec) -> void:
			directions.append(velocity.normalized())
	)
	Input.action_press("fire")
	await wait_physics_frames(_seconds(0.5))
	Input.action_release("fire")
	assert_gt(directions.size(), 4)
	if directions.size() > 4:
		assert_almost_eq(directions[0].angle_to(aim_before), 0.0, 0.000001, "first shot has no spread around the calibrated bore")
		var recoil: RecoilLogic = _weapons.get_current_recoil()
		assert_almost_eq(recoil.bloom, _rifle.spread_per_shot_degrees * directions.size(), 0.0001, "bloom built up")


func test_hip_shots_land_inside_the_hip_cone() -> void:
	var recoil: RecoilLogic = _weapons.get_current_recoil()
	var aim: Vector3 = -_player.get_aim_basis().z
	var spread: float = recoil.spread_degrees(0.0)
	assert_eq(spread, _rifle.hip_spread_degrees, "settled hip spread")
	var largest: float = 0.0
	for _sample: int in 300:
		var angle: float = rad_to_deg(recoil.deviate(aim, spread).angle_to(aim))
		assert_true(angle <= spread + 0.0001, "inside the cone")
		largest = maxf(largest, angle)
	assert_gt(largest, spread * 0.8, "and fills it")


# --- Sight zero ---


func test_equipped_weapons_impact_at_zero_and_match_integrator_at_50_and_300() -> void:
	for slot: int in [0, 1]:
		_weapons.request_switch(slot)
		await wait_physics_frames(65)
		await _aim_fully()
		var data: WeaponData = _weapons.get_current_data()
		assert_eq(data.zero_distance_m, 100.0)
		for distance: float in [50.0, 100.0, 300.0]:
			var wall: StaticBody3D = _add_slab(Vector3(20.0, 20.0, 0.02), Vector3(0, 2, -distance - 0.01))
			await wait_physics_frames(2)
			_hits.clear()
			var eye: Vector3 = _player.get_eye_position()
			await _tap(&"fire")
			await wait_physics_frames(90)
			assert_eq(_hits.size(), 1, "%s at %d m" % [data.display_name, distance])
			if _hits.size() == 1:
				var offset: float = _hits[0].position.y - eye.y
				var expected: float = SightZeroing.height_at_distance(data.projectile, distance, data.sight_height_m, _weapons.get_zero_angle(), 9.81, _projectiles.air_density, 1.0 / 60.0)
				assert_almost_eq(offset, expected, 0.001, "live hit matches the drag integrator")
				if distance == data.zero_distance_m:
					assert_almost_eq(offset, 0.0, 0.01, "point of aim within 1 cm")
				else:
					assert_lt(offset, 0.0, "geometry-derived sights put both 50 and 300 m below aim")
			wall.free()


func test_switch_recalibrates_using_the_live_air_density() -> void:
	var initial: float = _weapons.get_zero_angle()
	_projectiles.air_density = 0.0
	_weapons.request_switch(1)
	await wait_physics_frames(65)
	var expected: float = SightZeroing.solve(_sniper.projectile, _sniper.zero_distance_m, _sniper.sight_height_m, 9.81, 0.0, 1.0 / 60.0)
	assert_almost_eq(_weapons.get_zero_angle(), expected, 0.000001)
	_weapons.request_switch(0)
	await wait_physics_frames(65)
	assert_lt(_weapons.get_zero_angle(), initial, "reequip recalibrates instead of keeping the old atmosphere")


func test_attachment_recompute_waits_for_reload_and_never_refills_ammo() -> void:
	Input.action_press("fire")
	await wait_physics_frames(10)
	Input.action_release("fire")
	await wait_physics_frames(8)
	await _tap(&"reload")
	var build: WeaponBuild = _weapons.get_build(0)
	var computations: int = build.computation_count
	var attachment := AttachmentData.new()
	attachment.slot = WeaponTypes.Slot.MAGAZINE
	attachment.compatible_classes = PackedInt32Array([WeaponTypes.Class.RIFLE])
	var modifier := StatModifier.new()
	modifier.stat = &"magazine_size"
	modifier.operation = StatModifier.Operation.ADD
	modifier.value = 10.0
	attachment.modifiers = [modifier]
	assert_true(_weapons.request_attachment(attachment.slot, attachment))
	await wait_physics_frames(5)
	assert_eq(build.computation_count, computations)
	await wait_physics_frames(_seconds(_rifle.reload_tactical_time) + 4)
	assert_eq(_weapons.get_current_data().magazine_size, 40)
	assert_eq(_weapons.get_current_logic().ammo, 30, "attachment does not supply the ten new rounds")
	assert_eq(build.computation_count, computations + 1)
	await wait_physics_frames(10)
	assert_eq(build.computation_count, computations + 1)
	assert_true(_weapons.request_attachment(attachment.slot, null))
	await wait_physics_frames(2)
	assert_eq(_weapons.get_current_data().magazine_size, 30)


func test_attachment_recalibrates_zero_without_mutating_launched_spec() -> void:
	await _aim_fully()
	var original: WeaponData = _weapons.get_current_data()
	var zero: float = _weapons.get_zero_angle()
	var attachment := AttachmentData.new()
	attachment.slot = WeaponTypes.Slot.BARREL
	attachment.compatible_classes = PackedInt32Array([WeaponTypes.Class.RIFLE])
	var modifier := StatModifier.new()
	modifier.stat = &"projectile.muzzle_velocity"
	modifier.value = 1.1
	attachment.modifiers = [modifier]
	assert_true(_weapons.request_attachment(attachment.slot, attachment))
	await wait_physics_frames(2)
	assert_eq(original.projectile.muzzle_velocity, 850.0)
	assert_almost_eq(_weapons.get_current_data().projectile.muzzle_velocity, 935.0, 0.00001)
	assert_lt(_weapons.get_zero_angle(), zero)
