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
	_world.add_child(_player)
	_weapons = _player.get_node("Weapons") as WeaponController
	_rifle = _weapons.loadout[0]
	_sniper = _weapons.loadout[1]
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


func test_fire_launches_a_projectile_from_the_eye_along_the_aim() -> void:
	_add_slab(Vector3(40.0, 40.0, 1.0), Vector3(0.0, 0.0, -30.5))
	await wait_physics_frames(2)
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
		var drop: float = ProjectileMath.drop_at_distance(30.0, _rifle.projectile.muzzle_velocity, 9.81)
		assert_almost_eq(hit.position.y, _player.get_eye_position().y - drop, 0.003, "from eye height, minus gravity drop")
		assert_eq(hit.spec, _rifle.projectile)


func test_shots_follow_yaw_and_pitch() -> void:
	_player.yaw = deg_to_rad(90.0)  # Facing -X.
	_player.pitch = deg_to_rad(-45.0)
	await _tap(&"fire")
	await wait_physics_frames(4)
	assert_gt(_hits.size(), 0, "aimed down, so it hits the floor")
	if _hits.size() > 0:
		var eye_height: float = _player.get_eye_position().y
		assert_almost_eq(_hits[0].position.y, 0.0, 0.001)
		assert_almost_eq(_hits[0].position.x, -eye_height, 0.01, "45 degrees down lands one eye-height ahead")
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
