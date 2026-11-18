extends GutTest

var saved: Dictionary = {}

func before_each() -> void:
	for key: String in ViewSettings.KEYS:
		saved[key] = ViewSettings.get(key)

func after_each() -> void:
	for key: String in saved:
		ViewSettings.set(key, saved[key])
	GameInput.clear()
	GameInput.controller_active = false
	GameInput.active_device = -1

func test_radial_dead_zone_and_curves() -> void:
	assert_eq(ControllerMath.response(Vector2(0.1, 0.1), 0.15, false), Vector2.ZERO)
	assert_almost_eq(ControllerMath.response(Vector2(0.575, 0), 0.15, false).x, 0.5, 0.00001)
	assert_almost_eq(ControllerMath.response(Vector2(0.575, 0), 0.15, true).x, 0.125, 0.00001)
	assert_almost_eq(ControllerMath.response(Vector2.ONE, 0.15, false).length(), 1.0, 0.00001)

func test_look_integrates_same_angle_at_different_tick_rates() -> void:
	var sums: Array[Vector2] = []
	for rate: int in [30, 60, 120]:
		var total := Vector2.ZERO
		for tick: int in rate:
			total += ControllerMath.look(Vector2(0.6, 0.7), 1.0 / rate, Vector2(180,120), 0.15, true, false, 0.5, 0.5, true)
		sums.append(total)
	assert_almost_eq(sums[0].x, sums[2].x, 0.00001)
	assert_almost_eq(sums[1].y, sums[2].y, 0.00001)

func test_assist_only_scales_supplied_look_and_cannot_move_idle_aim() -> void:
	var original := Vector2(0.4, -0.6)
	var normal: Vector2 = ControllerMath.look(original, 0.1, Vector2(180,120), 0.15, false, false, 1, 0, true)
	var slowed: Vector2 = ControllerMath.look(original, 0.1, Vector2(180,120), 0.15, false, false, 1, 1, true)
	assert_almost_eq(slowed.x, normal.x * 0.25, 0.00001)
	assert_eq(ControllerMath.look(Vector2.ZERO, 1, Vector2(180,120), 0.15, false, false, 1, 1, true), Vector2.ZERO)
	assert_eq(original, Vector2(0.4,-0.6))

func test_mouse_look_path_is_unchanged_even_with_controller_assist_enabled() -> void:
	var scene: PackedScene = load("res://player/player.tscn")
	var player := scene.instantiate() as PlayerController
	add_child_autofree(player)
	player.set_physics_process(false)
	ViewSettings.mouse_sensitivity = 0.23
	ViewSettings.invert_y = false
	ViewSettings.aim_assist = 1.0
	player.look_sensitivity_scale = 0.7
	for active: bool in [false,true]:
		GameInput.controller_active = active
		player.yaw = 0
		player.pitch = 0
		player.recoil_yaw = 0.03
		player.recoil_pitch = -0.02
		var relative := Vector2(12,-7)
		var horizontal: Vector2 = RecoilLogic.absorb(0.03, -relative.x * deg_to_rad(0.23) * 0.7)
		var vertical: Vector2 = RecoilLogic.absorb(-0.02, -relative.y * deg_to_rad(0.23) * 0.7)
		player._apply_look(relative)
		assert_almost_eq(player.yaw, horizontal.y, 0.000001)
		assert_almost_eq(player.pitch, vertical.y, 0.000001)
		assert_almost_eq(player.recoil_yaw, horizontal.x, 0.000001)
		assert_almost_eq(player.recoil_pitch, vertical.x, 0.000001)

func test_prompts_ignore_drift_and_disconnect_clears_actions() -> void:
	var motion := InputEventJoypadMotion.new()
	motion.device = 3
	motion.axis_value = 0.05
	GameInput.observe(motion)
	assert_false(GameInput.controller_active)
	motion.axis_value = 0.8
	GameInput.observe(motion)
	assert_true(GameInput.controller_active)
	assert_eq(GameInput.prompt("fire"), "RT")
	Input.action_press("fire")
	GameInput.toggles["aim"] = true
	GameInput.connection_changed(3, false)
	assert_false(Input.is_action_pressed("fire"))
	assert_true(GameInput.toggles.is_empty())
	assert_false(GameInput.controller_active)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	GameInput.observe(key)
	assert_false(GameInput.controller_active)

func test_binding_round_trip_and_conflict_rejection() -> void:
	var logical := InputEventKey.new()
	logical.keycode = KEY_TAB
	var restored := GameInput.decode(GameInput.encode(logical)) as InputEventKey
	assert_eq(restored.keycode, KEY_TAB)
	assert_eq(restored.physical_keycode, 0)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_R
	assert_eq(GameInput.conflict("jump", key), "reload")
	assert_false(GameInput.rebind("jump", key).is_empty())
	var old: Array[InputEvent] = InputMap.action_get_events("jump")
	key.physical_keycode = KEY_J
	assert_eq(GameInput.rebind("jump", key), "")
	var path: String = "user://gut_m13_bindings.cfg"
	assert_eq(GameInput.save_bindings(path), OK)
	InputMap.action_erase_events("jump")
	GameInput.load_bindings(path)
	assert_true(InputMap.action_has_event("jump", key))
	InputMap.action_erase_events("jump")
	for event: InputEvent in old:
		InputMap.action_add_event("jump", event)
	DirAccess.remove_absolute(path)

func test_assist_setting_does_not_change_an_in_flight_projectile() -> void:
	var system := ProjectileSystem.new()
	add_child_autofree(system)
	system.set_physics_process(false)
	var spec := ProjectileSpec.new()
	var first: int = system.fire(Vector3(0,100,0), Vector3.FORWARD, spec)
	var second: int = system.fire(Vector3(0,100,0), Vector3.FORWARD, spec)
	ViewSettings.aim_assist = 1
	GameInput.controller_active = true
	for tick: int in 10:
		ControllerMath.look(Vector2.ONE, 1.0/60, Vector2(180,120), 0.15, true, false, 1, 1, true)
		system.advance(1.0/60)
		assert_eq(system.get_slot_position(first), system.get_slot_position(second))
		assert_eq(system.get_slot_velocity(first), system.get_slot_velocity(second))

func test_disconnect_opens_pause_and_clears_weapon_edges() -> void:
	var menu := PauseMenu.new()
	menu.settings_path = "user://gut_m13_pause.cfg"
	add_child_autofree(menu)
	GameInput.controller_active = true
	GameInput.active_device = 5
	Input.action_press("aim")
	GameInput.connection_changed(5, false)
	assert_true(get_tree().paused)
	assert_true(menu.visible)
	assert_false(Input.is_action_pressed("aim"))
	menu.set_paused(false)
	DirAccess.remove_absolute(menu.settings_path)

func test_remapping_window_captures_synthetic_button_and_reports_conflict() -> void:
	var dialog := BindingMenu.new()
	add_child_autofree(dialog)
	var old: Array[InputEvent] = InputMap.action_get_events("jump")
	dialog.waiting = &"jump"
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_X
	event.pressed = true
	dialog._input(event)
	assert_true(dialog.status.text.contains("reload"))
	assert_eq(InputMap.action_get_events("jump").size(), old.size())
