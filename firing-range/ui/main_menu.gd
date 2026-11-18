class_name MainMenu
extends Control
signal play_requested
signal armory_requested
signal quit_requested

var config: LoadoutConfig
var settings_path: String = "user://settings.cfg"
var play_button: Button
var armory_button: Button
var settings_button: Button
var settings_back: Button
var _home: VBoxContainer
var _settings: VBoxContainer
var _panel: SettingsPanel
var _status: Label


func _ready() -> void:
	var margin: MarginContainer = MenuStyle.backdrop(self)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 70)
	margin.add_child(columns)
	_home = VBoxContainer.new()
	_home.custom_minimum_size.x = 360
	_home.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_home.add_theme_constant_override("separation", 16)
	columns.add_child(_home)
	_home.add_child(MenuStyle.label("FIRING RANGE", 42))
	_home.add_child(MenuStyle.label("BUILD. TEST. REFINE.", 16, MenuStyle.ACCENT))
	_home.add_child(HSeparator.new())
	play_button = MenuStyle.button("Play", func() -> void: play_requested.emit())
	armory_button = MenuStyle.button("Armory", func() -> void: armory_requested.emit())
	settings_button = MenuStyle.button("Settings", show_settings)
	var quit_button: Button = MenuStyle.button("Quit", func() -> void: quit_requested.emit())
	for button: Button in [play_button, armory_button, settings_button, quit_button]:
		_home.add_child(button)
	SettingsPanel.wire_focus([play_button, armory_button, settings_button, quit_button])
	var summary := VBoxContainer.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	summary.add_theme_constant_override("separation", 18)
	columns.add_child(summary)
	summary.add_child(MenuStyle.label("YOUR LOADOUT", 16, MenuStyle.ACCENT))
	summary.add_child(MenuStyle.label(config.primary.display_name, 28))
	summary.add_child(MenuStyle.label(config.secondary.display_name, 28))
	summary.add_child(MenuStyle.label("Five lanes. Nine weapons. One place to find your feel.", 16, MenuStyle.MUTED))
	summary.add_child(MenuStyle.label("Arrows / D-pad: navigate   Enter / A: select", 14, MenuStyle.MUTED))
	_settings = VBoxContainer.new()
	_settings.add_theme_constant_override("separation", 16)
	_settings.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_settings.offset_left = -310
	_settings.offset_right = 310
	_settings.offset_top = -270
	_settings.offset_bottom = 270
	add_child(_settings)
	_settings.add_child(MenuStyle.label("SETTINGS", 30))
	settings_back = MenuStyle.button("Save & Back", close_settings)
	_settings.add_child(settings_back)
	_panel = SettingsPanel.new()
	_settings.add_child(_panel)
	_status = MenuStyle.label("Changes apply live. Save & Back keeps them for next time.", 14, MenuStyle.MUTED)
	_settings.add_child(_status)
	var focusables: Array[Control] = [settings_back]
	focusables.append_array(_panel.focusables)
	SettingsPanel.wire_focus(focusables)
	_settings.hide()
	play_button.grab_focus()


func show_settings() -> void:
	(_home.get_parent() as Control).hide()
	_panel.refresh()
	_settings.show()
	settings_back.grab_focus()


func close_settings() -> void:
	var error: Error = ViewSettings.save_to_disk(settings_path)
	if error != OK:
		_status.text = "Could not save settings. Please try again."
		return
	_settings.hide()
	(_home.get_parent() as Control).show()
	settings_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _settings.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		close_settings()
		get_viewport().set_input_as_handled()
