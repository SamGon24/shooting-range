class_name GameFlow
extends Node
## Owns screen transitions and the saved selection, outside range simulation.
const RANGE: PackedScene = preload("res://range/range.tscn")
var config: LoadoutConfig
var config_path: String = LoadoutConfig.SAVE_PATH
var settings_path: String = "user://settings.cfg"
var scores_path: String = ChallengeScores.PATH
var active: Node
var _transition: int = 0


func _ready() -> void:
	config = LoadoutConfig.new()
	config.load_from_disk(config_path)
	# Existing probe/capture commands remain direct range runs.
	for argument: String in OS.get_cmdline_user_args():
		for rule: ChallengeRule in ChallengeMenu.RULES:
			if argument == "--challenge=" + String(rule.id):
				play(rule)
				return
	if wants_range(OS.get_cmdline_user_args()):
		play()
	elif "--armory" in OS.get_cmdline_user_args():
		show_armory()
	else:
		show_menu()


static func wants_range(arguments: PackedStringArray) -> bool:
	for argument: String in arguments:
		if argument == "--range" or argument == "--perf-probe" or argument.begins_with("--pose=") or argument.begins_with("--hold="):
			return true
	return false


func _clear() -> void:
	_transition += 1
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for action: StringName in [&"fire", &"aim", &"reload", &"jump", &"ui_accept"]:
		Input.action_release(action)
	if active != null:
		remove_child(active)
		active.queue_free()
	active = null


func show_menu(focus_armory: bool = false) -> void:
	_clear()
	var menu := MainMenu.new()
	menu.config = config
	menu.settings_path = settings_path
	menu.challenges_requested.connect(show_challenges.call_deferred)
	menu.play_requested.connect(play.call_deferred)
	menu.armory_requested.connect(show_armory.call_deferred)
	menu.quit_requested.connect(_quit.call_deferred)
	active = menu
	add_child(menu)
	if focus_armory:
		menu.armory_button.grab_focus()


func show_armory() -> void:
	_clear()
	var armory := Armory.new()
	armory.config = config
	armory.save_path = config_path
	armory.saved.connect(_saved.call_deferred)
	armory.cancelled.connect(show_menu.bind(true).call_deferred)
	active = armory
	add_child(armory)


func _saved(selection: LoadoutConfig) -> void:
	config = selection
	show_menu(true)


func show_challenges(result: ChallengeAttempt = null) -> void:
	_clear()
	var screen := ChallengeMenu.new()
	screen.scores = ChallengeScores.new(scores_path)
	screen.result = result
	if result != null:
		screen.save_error = screen.scores.record(result.rule.id, result.score())
		screen.back.connect(show_challenges.call_deferred)
	else:
		screen.back.connect(show_menu.call_deferred)
	screen.selected.connect(play.call_deferred)
	active = screen
	add_child(screen)


func play(rule: ChallengeRule = null) -> void:
	_clear()
	var transition: int = _transition
	# action_release does not clear just_pressed in the current physics tick.
	# Let two boundaries pass before the player can consume menu activation.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if transition != _transition:
		return
	var range_scene := RANGE.instantiate() as RangeBuilder
	range_scene.weapon_controller.initial_builds = [config.get_build(config.primary), config.get_build(config.secondary)]
	range_scene.pause_menu.settings_path = settings_path
	range_scene.pause_menu.return_to_menu_enabled = true
	range_scene.pause_menu.return_requested.connect(show_menu.call_deferred)
	active = range_scene
	add_child(range_scene)
	if rule != null:
		var hud := range_scene.get_node("Hud") as Hud
		hud.hide_free_range_stats()
		var overlay := ChallengeHud.new()
		overlay.player = range_scene.weapon_controller.player
		overlay.projectiles = get_tree().get_first_node_in_group(ProjectileSystem.GROUP) as ProjectileSystem
		overlay.attempt = ChallengeAttempt.new(rule)
		overlay.completed.connect(show_challenges.call_deferred)
		overlay.retry_requested.connect(play.bind(rule).call_deferred)
		range_scene.add_child(overlay)


func _quit() -> void:
	get_tree().quit()
