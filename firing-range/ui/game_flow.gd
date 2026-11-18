class_name GameFlow
extends Node
## Owns screen transitions and the saved selection, outside range simulation.
const RANGE: PackedScene = preload("res://range/range.tscn")
var config: LoadoutConfig
var config_path: String = LoadoutConfig.SAVE_PATH
var settings_path: String = "user://settings.cfg"
var active: Node
var _transition: int = 0


func _ready() -> void:
	config = LoadoutConfig.new()
	config.load_from_disk(config_path)
	# Existing probe/capture commands remain direct range runs.
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


func play() -> void:
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
	range_scene.pause_menu.return_to_menu_enabled = true
	range_scene.pause_menu.return_requested.connect(show_menu.call_deferred)
	active = range_scene
	add_child(range_scene)


func _quit() -> void:
	get_tree().quit()
