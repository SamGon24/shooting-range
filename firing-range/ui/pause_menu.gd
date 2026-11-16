class_name PauseMenu
extends CanvasLayer
## Always-processing, InputMap-driven menu. SceneTree pause freezes all
## gameplay, audio, physics and the stats clock; this layer alone stays live.

## Alternate path is used by isolated save/load tests.
var settings_path: String = "user://settings.cfg"
var _shade: ColorRect
var _panel: PanelContainer
var _rows: VBoxContainer
var _resume: Button
var _focusables: Array[Control] = []
var _capture_before: bool = false
var _status: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 200
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.65)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left = -330
	_panel.offset_right = 330
	_panel.offset_top = -290
	_panel.offset_bottom = 290
	add_child(_panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	margin.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 10)
	scroll.add_child(_rows)
	var title := Label.new()
	title.text = "PAUSED — SETTINGS"
	title.add_theme_font_size_override("font_size", 24)
	_rows.add_child(title)
	_resume = Button.new()
	_resume.text = "Resume"
	_resume.pressed.connect(set_paused.bind(false))
	_rows.add_child(_resume)
	_focusables.append(_resume)
	_add_slider("Sensitivity", "mouse_sensitivity", 0.01, 1.0, 0.01)
	_add_slider("ADS sensitivity multiplier", "ads_sensitivity_multiplier", 0.1, 2.0, 0.05)
	_add_slider("Vertical FOV", "fov_degrees", 50.0, 100.0, 1.0)
	_add_slider("Head bob scale", "head_bob_scale", 0.0, 2.0, 0.05)
	_add_slider("FOV kick scale", "fov_kick_scale", 0.0, 2.0, 0.05)
	_add_slider("Master volume", "master_volume", 0.0, 1.0, 0.05)
	_add_slider("Effects volume", "effects_volume", 0.0, 1.0, 0.05)
	var fps := CheckButton.new()
	fps.text = "Show gameplay FPS"
	fps.button_pressed = ViewSettings.show_fps
	fps.toggled.connect(func(value: bool) -> void: ViewSettings.show_fps = value)
	_rows.add_child(fps)
	_focusables.append(fps)
	_status = Label.new()
	_status.text = "Up/Down: select   Left/Right: adjust   Enter/A: activate\nEsc / Start / B: resume. Settings save on resume."
	_status.add_theme_font_size_override("font_size", 14)
	_rows.add_child(_status)
	for index: int in _focusables.size():
		var control: Control = _focusables[index]
		control.focus_neighbor_top = control.get_path_to(_focusables[posmod(index - 1, _focusables.size())])
		control.focus_neighbor_bottom = control.get_path_to(_focusables[(index + 1) % _focusables.size()])
		control.focus_previous = control.focus_neighbor_top
		control.focus_next = control.focus_neighbor_bottom
	visible = false


func _add_slider(title: String, key: String, minimum: float, maximum: float, increment: float) -> void:
	var row := HBoxContainer.new()
	_rows.add_child(row)
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
	_focusables.append(slider)


func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("pause") or (visible and event.is_action_pressed("ui_cancel")):
		set_paused(not visible)
		get_viewport().set_input_as_handled()


func set_paused(paused: bool) -> void:
	if paused == visible:
		return
	if paused:
		for control: Control in _focusables:
			if control is HSlider:
				(control as HSlider).value = float(ViewSettings.get(control.name))
			elif control is CheckButton:
				(control as CheckButton).button_pressed = ViewSettings.show_fps
		_capture_before = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		visible = true
		get_tree().paused = true
		_resume.grab_focus()
	else:
		ViewSettings.save_to_disk(settings_path)
		visible = false
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _capture_before else Input.MOUSE_MODE_VISIBLE
	# Avoid a menu activation becoming fire/jump on the first resumed tick.
	for action: StringName in [&"fire", &"aim", &"reload", &"jump"]:
		Input.action_release(action)
	var weapons := get_tree().get_first_node_in_group(WeaponController.GROUP) as WeaponController
	if weapons != null:
		weapons.clear_input_latches()


func _exit_tree() -> void:
	if get_tree() != null and visible:
		get_tree().paused = false
