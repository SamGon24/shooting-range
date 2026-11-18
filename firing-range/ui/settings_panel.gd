class_name SettingsPanel
extends VBoxContainer
## Shared live settings for the pause and front-end menus.
var focusables: Array[Control] = []


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_add_slider("Sensitivity", "mouse_sensitivity", 0.01, 1.0, 0.01)
	_add_slider("ADS sensitivity multiplier", "ads_sensitivity_multiplier", 0.1, 2.0, 0.05)
	_add_slider("Vertical FOV", "fov_degrees", 50.0, 100.0, 1.0)
	_add_slider("Head bob scale", "head_bob_scale", 0.0, 2.0, 0.05)
	_add_slider("FOV kick scale", "fov_kick_scale", 0.0, 2.0, 0.05)
	_add_slider("Master volume", "master_volume", 0.0, 1.0, 0.05)
	_add_slider("Effects volume", "effects_volume", 0.0, 1.0, 0.05)
	_add_toggle("Show gameplay FPS", "show_fps")
	_add_toggle("Time to kill starts at the first shot", "ttk_from_first_shot")


func refresh() -> void:
	for control: Control in focusables:
		if control is HSlider:
			(control as HSlider).value = float(ViewSettings.get(control.name))
		elif control is CheckButton:
			(control as CheckButton).button_pressed = bool(ViewSettings.get(control.name))


func _add_toggle(title: String, key: String) -> void:
	var toggle := CheckButton.new()
	toggle.name = key
	toggle.text = title
	toggle.button_pressed = bool(ViewSettings.get(key))
	toggle.toggled.connect(func(value: bool) -> void: ViewSettings.set(key, value))
	add_child(toggle)
	focusables.append(toggle)


func _add_slider(title: String, key: String, minimum: float, maximum: float, increment: float) -> void:
	var row := HBoxContainer.new()
	add_child(row)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 250
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = key
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = increment
	slider.value = float(ViewSettings.get(key))
	slider.custom_minimum_size = Vector2(220, 30)
	slider.focus_mode = Control.FOCUS_ALL
	row.add_child(slider)
	var readout := Label.new()
	readout.custom_minimum_size.x = 60
	readout.text = "%.2f" % slider.value
	row.add_child(readout)
	slider.value_changed.connect(func(value: float) -> void:
		ViewSettings.set(key, value)
		readout.text = "%.2f" % value)
	focusables.append(slider)



static func wire_focus(controls: Array[Control]) -> void:
	for index: int in controls.size():
		var control: Control = controls[index]
		control.focus_neighbor_top = control.get_path_to(controls[posmod(index - 1, controls.size())])
		control.focus_neighbor_bottom = control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = control.focus_neighbor_top
		control.focus_next = control.focus_neighbor_bottom
