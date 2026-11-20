extends GutTest

func test_menu_to_accuracy_result_and_fresh_retry() -> void:
	var flow := GameFlow.new()
	flow.scores_path = "/tmp/gut_m16_flow_%d.cfg" % get_instance_id()
	add_child_autoqfree(flow)
	(flow.active as MainMenu).challenges_requested.emit()
	await wait_process_frames(2)
	var menu := flow.active as ChallengeMenu
	assert_not_null(menu)
	menu.selected.emit(ChallengeMenu.RULES[1])
	await wait_physics_frames(6)
	var hud := flow.active.get_child(-1) as ChallengeHud
	assert_not_null(hud)
	var system: ProjectileSystem = hud.projectiles
	var plate := get_tree().get_first_node_in_group(&"steel_plate") as SteelPlate
	var old: int = system.begin_damage_event()
	hud._physics_process(3.1)
	var hostile: int = system.begin_damage_event(false)
	for id: int in [old, hostile]:
		plate.last_hit = ProjectileHit.new()
		plate.last_hit.shot_id = id
		plate.rang.emit()
		system.end_damage_event(id)
	assert_eq(hud.attempt.shots, 0)
	assert_eq(hud.attempt.hits, 0)
	for i: int in 10:
		var id: int = system.begin_damage_event()
		plate.last_hit = ProjectileHit.new()
		plate.last_hit.shot_id = id
		plate.rang.emit()
		system.end_damage_event(id)
	await wait_physics_frames(4)
	var results := flow.active as ChallengeMenu
	assert_not_null(results)
	assert_eq(results.result.score(), 100)
	assert_eq(ChallengeScores.new(flow.scores_path).best(&"accuracy"), 100)
	var retry := InputEventJoypadButton.new()
	retry.button_index = JOY_BUTTON_DPAD_RIGHT
	retry.pressed = true
	Input.parse_input_event(retry)
	await wait_physics_frames(6)
	var next := flow.active.get_child(-1) as ChallengeHud
	assert_not_null(next)
	assert_eq(next.attempt.shots, 0)
	assert_eq(next.attempt.rule.id, &"accuracy")
	retry.pressed = false
	Input.parse_input_event(retry)
	await wait_process_frames(2)
	DirAccess.remove_absolute(flow.scores_path)

func test_steel_requires_a_launch_behind_the_line_and_pausing_freezes_countdown() -> void:
	var flow := GameFlow.new()
	flow.settings_path = "/tmp/gut_m16_pause_%d.cfg" % get_instance_id()
	add_child_autoqfree(flow)
	flow.play(ChallengeMenu.RULES[2])
	await wait_physics_frames(6)
	var range_scene := flow.active as RangeBuilder
	var hud := range_scene.get_child(-1) as ChallengeHud
	range_scene.pause_menu.set_paused(true)
	var before: float = hud._countdown
	await wait_physics_frames(4)
	assert_eq(hud._countdown, before)
	range_scene.pause_menu.set_paused(false)
	hud._physics_process(3.1)
	hud.player.global_position.z = -2
	var rejected: int = hud.projectiles.begin_damage_event()
	hud.projectiles.end_damage_event(rejected)
	assert_eq(hud.attempt.shots, 0)
	hud.player.global_position.z = 2
	var accepted: int = hud.projectiles.begin_damage_event()
	hud.projectiles.end_damage_event(accepted)
	assert_eq(hud.attempt.shots, 1)
	DirAccess.remove_absolute(flow.settings_path)
