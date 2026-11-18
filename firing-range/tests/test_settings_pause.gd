extends GutTest

const SETTINGS_SCRIPT: Script = preload("res://player/view_settings.gd")

class TickCounter:
	extends Node
	var ticks: int = 0
	func _physics_process(_delta: float) -> void:
		ticks += 1


func after_each() -> void:
	get_tree().paused = false
	Input.action_release("ui_focus_next")
	Input.action_release("ui_down")
	Input.action_release("ui_cancel")
	Input.action_release("pause")


func test_every_setting_survives_an_isolated_disk_round_trip() -> void:
	var source: Node = SETTINGS_SCRIPT.new()
	var restored: Node = SETTINGS_SCRIPT.new()
	autofree(source)
	autofree(restored)
	var values: Dictionary[String, Variant] = {"fov_degrees":82.0,"mouse_sensitivity":0.23,"invert_y":true,"head_bob_scale":0.2,"fov_kick_scale":1.5,"ads_sensitivity_multiplier":0.65,"master_volume":0.4,"effects_volume":0.7,"show_fps":false,"ttk_from_first_shot":true}
	for key: String in values:
		source.set(key, values[key])
	var path: String = "user://gut_m6_settings.cfg"
	assert_eq(source.call("save_to_disk", path), OK)
	restored.call("load_from_disk", path)
	for key: String in values:
		assert_eq(restored.get(key), values[key], key)
	DirAccess.remove_absolute(path)


func test_pause_freezes_gameplay_ticks_physics_projectiles_and_stats_clock() -> void:
	var world := Node3D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child_autofree(world)
	var counter := TickCounter.new()
	world.add_child(counter)
	var feedback := RangeFeedback.new()
	world.add_child(feedback)
	var system := ProjectileSystem.new()
	world.add_child(system)
	var prop := PhysicsProp.new()
	prop.gravity_scale = 0.0
	prop.position.x = 10.0
	world.add_child(prop)
	prop.linear_velocity = Vector3.RIGHT
	var menu := PauseMenu.new()
	menu.settings_path = "user://gut_m6_menu.cfg"
	world.add_child(menu)
	await wait_physics_frames(3)
	var slot: int = system.fire(Vector3(0, 20, 0), Vector3.FORWARD, ProjectileSpec.new())
	await wait_physics_frames(2)
	menu.set_paused(true)
	var ticks: int = counter.ticks
	var clock: float = feedback.get("_clock")
	var position: Vector3 = prop.global_position
	var bullet: Vector3 = system.get_slot_position(slot)
	await get_tree().create_timer(0.2, true).timeout
	assert_eq(counter.ticks, ticks)
	assert_eq(feedback.get("_clock"), clock)
	assert_eq(prop.global_position, position)
	assert_eq(system.get_slot_position(slot), bullet)
	assert_true(get_viewport().gui_get_focus_owner() is Button)
	menu.set_paused(false)
	await wait_physics_frames(3)
	assert_gt(counter.ticks, ticks)
	assert_gt(float(feedback.get("_clock")), clock)
	DirAccess.remove_absolute(menu.settings_path)


func test_focus_actions_and_cancel_work_while_game_is_paused() -> void:
	var menu := PauseMenu.new()
	menu.settings_path = "user://gut_m6_focus.cfg"
	add_child_autofree(menu)
	menu.set_paused(true)
	var first: Control = get_viewport().gui_get_focus_owner()
	var event := InputEventAction.new()
	event.action = &"ui_focus_next"
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	assert_ne(get_viewport().gui_get_focus_owner(), first)
	assert_true(get_viewport().gui_get_focus_owner() is HSlider)
	event = InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	assert_false(get_tree().paused)
	assert_false(menu.visible)
	DirAccess.remove_absolute(menu.settings_path)


func test_menu_actions_have_controller_bindings() -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_START
	assert_true(InputMap.event_is_action(event, &"pause"))
	event.button_index = JOY_BUTTON_A
	assert_true(InputMap.event_is_action(event, &"ui_accept"))
	event.button_index = JOY_BUTTON_B
	assert_true(InputMap.event_is_action(event, &"ui_cancel"))


func test_shared_settings_panels_edit_and_refresh_the_same_live_values() -> void:
	var original: float = ViewSettings.fov_degrees
	var first := SettingsPanel.new()
	var second := SettingsPanel.new()
	add_child_autofree(first)
	add_child_autofree(second)
	assert_eq(first.focusables.size(), 9)
	var slider := first.find_child("fov_degrees", true, false) as HSlider
	slider.value = 81.0
	assert_eq(ViewSettings.fov_degrees, 81.0)
	second.refresh()
	var other := second.find_child("fov_degrees", true, false) as HSlider
	assert_eq(other.value, 81.0)
	ViewSettings.fov_degrees = original


func test_the_ttk_toggle_edits_and_refreshes_the_shared_preference() -> void:
	var original: bool = ViewSettings.ttk_from_first_shot
	var first := SettingsPanel.new()
	var second := SettingsPanel.new()
	add_child_autofree(first)
	add_child_autofree(second)
	var toggle := first.find_child("ttk_from_first_shot", true, false) as CheckButton
	var fps := first.find_child("show_fps", true, false) as CheckButton
	assert_not_null(toggle)
	assert_ne(toggle, fps)
	toggle.button_pressed = not original
	assert_eq(ViewSettings.ttk_from_first_shot, not original)
	second.refresh()
	assert_eq((second.find_child("ttk_from_first_shot", true, false) as CheckButton).button_pressed, not original)
	assert_eq((second.find_child("show_fps", true, false) as CheckButton).button_pressed, ViewSettings.show_fps, "each toggle refreshes from its own setting")
	ViewSettings.ttk_from_first_shot = original
