extends GutTest

const PATH: String = "/tmp/gut_m11_flow.cfg"
const SETTINGS: String = "/tmp/gut_m11_flow_settings.cfg"
const SMG: WeaponData = preload("res://weapons/data/rill_smg.tres")
const PISTOL: WeaponData = preload("res://weapons/data/wayline_pistol.tres")
const MAG: AttachmentData = preload("res://weapons/attachments/data/extended_mag.tres")


func after_each() -> void:
	get_tree().paused = false
	for action: StringName in [&"ui_accept", &"ui_cancel", &"ui_down", &"ui_up", &"ui_focus_next", &"pause", &"jump", &"fire"]:
		Input.action_release(action)
	DirAccess.remove_absolute(PATH)
	DirAccess.remove_absolute(SETTINGS)


func _flow() -> GameFlow:
	var flow := GameFlow.new()
	flow.config_path = PATH
	flow.settings_path = SETTINGS
	add_child_autoqfree(flow)
	return flow


func _action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func _joy(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame


func test_default_menu_focus_settings_and_controller_cancel_restore_focus() -> void:
	var flow: GameFlow = _flow()
	var menu := flow.active as MainMenu
	assert_not_null(menu)
	assert_same(get_viewport().gui_get_focus_owner(), menu.play_button)
	await _action(&"ui_down")
	assert_same(get_viewport().gui_get_focus_owner(), menu.armory_button)
	await _joy(JOY_BUTTON_DPAD_DOWN)
	assert_same(get_viewport().gui_get_focus_owner(), menu.settings_button)
	await _joy(JOY_BUTTON_A)
	assert_same(get_viewport().gui_get_focus_owner(), menu.settings_back)
	await _action(&"ui_focus_next")
	assert_true(get_viewport().gui_get_focus_owner() is HSlider)
	await _joy(JOY_BUTTON_B)
	assert_same(get_viewport().gui_get_focus_owner(), menu.settings_button)
	assert_true(FileAccess.file_exists(SETTINGS))
	assert_false(get_tree().paused)


func test_saved_armory_build_enters_range_returns_to_menu_and_survives_restart() -> void:
	var flow: GameFlow = _flow()
	flow.show_armory()
	var armory := flow.active as Armory
	assert_true(armory.select_weapon(SMG))
	assert_true(armory.set_attachment(WeaponTypes.Slot.MAGAZINE, MAG))
	armory.save()
	await wait_process_frames(2)
	assert_true(flow.active is MainMenu)
	assert_same(flow.config.primary, SMG)
	assert_same(get_viewport().gui_get_focus_owner(), (flow.active as MainMenu).armory_button)
	Input.action_press("fire")
	Input.action_press("jump")
	flow.play()
	await wait_physics_frames(5)
	var range_scene := flow.active as RangeBuilder
	assert_not_null(range_scene)
	var controller: WeaponController = range_scene.weapon_controller
	assert_same(controller.get_current_data().definition(), SMG)
	assert_same(controller.get_secondary_selection(), PISTOL)
	assert_same(controller.get_build(0).get_attachment(WeaponTypes.Slot.MAGAZINE), MAG)
	assert_eq(controller.get_current_logic().ammo, controller.get_current_data().magazine_size)
	assert_false(Input.is_action_pressed("fire"))
	assert_false(Input.is_action_pressed("jump"))
	range_scene.pause_menu.settings_path = SETTINGS
	range_scene.pause_menu.set_paused(true)
	range_scene.pause_menu.call("_return_to_menu")
	await wait_process_frames(2)
	assert_true(flow.active is MainMenu)
	assert_false(get_tree().paused)
	assert_eq(get_tree().get_nodes_in_group(WeaponController.GROUP).size(), 0)
	var restarted: GameFlow = _flow()
	assert_same(restarted.config.primary, SMG)
	assert_same(restarted.config.get_build(SMG).get_attachment(WeaponTypes.Slot.MAGAZINE), MAG)


func test_armory_controller_popup_navigation_disabled_slots_and_cancel_discard_draft() -> void:
	var flow: GameFlow = _flow()
	flow.show_armory()
	var armory := flow.active as Armory
	assert_same(get_viewport().gui_get_focus_owner(), armory.weapon_picker)
	# Open the weapon popup, choose the next primary, then activate it.
	await _joy(JOY_BUTTON_A)
	await _joy(JOY_BUTTON_DPAD_DOWN)
	await _joy(JOY_BUTTON_A)
	assert_same(armory.draft.selection(armory.role), SMG)
	var scroll := armory.get("_stat_scroll") as ScrollContainer
	scroll.grab_focus()
	await _joy(JOY_BUTTON_DPAD_RIGHT)
	assert_gt(scroll.scroll_vertical, 0)
	armory.select_role(WeaponTypes.Role.SECONDARY)
	await _action(&"ui_focus_next")
	assert_same(get_viewport().gui_get_focus_owner(), armory.attachment_pickers[0])
	await _action(&"ui_focus_next")
	assert_same(get_viewport().gui_get_focus_owner(), armory.attachment_pickers[2])
	await _action(&"ui_focus_next")
	assert_same(get_viewport().gui_get_focus_owner(), armory.attachment_pickers[4])
	await _joy(JOY_BUTTON_B)
	assert_true(flow.active is MainMenu)
	assert_same(flow.config.primary, (LoadoutConfig.new()).primary)
	assert_false(FileAccess.file_exists(PATH))


func test_debug_arguments_preserve_direct_range_launches() -> void:
	assert_true(GameFlow.wants_range(["--perf-probe", "--perf-fire"]))
	assert_true(GameFlow.wants_range(["--range"]))
	assert_true(GameFlow.wants_range(["--pose=0,0,2,0,0"]))
	assert_true(GameFlow.wants_range(["--hold=fire@1-2"]))
	assert_false(GameFlow.wants_range([]))
	assert_false(GameFlow.wants_range(["--armory"]))


func test_cancelling_a_pending_range_transition_cannot_reopen_the_range() -> void:
	var flow: GameFlow = _flow()
	flow.play()
	flow.show_menu()
	await wait_physics_frames(4)
	assert_true(flow.active is MainMenu)
	assert_eq(get_tree().get_nodes_in_group(WeaponController.GROUP).size(), 0)
