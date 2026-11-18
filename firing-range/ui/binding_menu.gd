class_name BindingMenu
extends Window
var waiting: StringName = &""
var status: Label
var buttons: Dictionary[StringName, Button] = {}

func _ready() -> void:
	title = "Remap controls"
	transient = true
	exclusive = true
	close_requested.connect(queue_free)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.follow_focus = true
	add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	status = Label.new()
	status.text = "Select action, then press a key, mouse button or pad input."
	rows.add_child(status)
	var controls: Array[Control] = []
	for action: StringName in GameInput.defaults:
		if String(action).begins_with("ui_"):
			continue
		var button := Button.new()
		button.text = String(action) + " : " + GameInput.prompt(action)
		button.pressed.connect(func() -> void:
			waiting = action
			status.text = "Waiting for " + String(action) + " (Esc cancels)")
		rows.add_child(button)
		buttons[action] = button
		controls.append(button)
	var reset := Button.new()
	reset.text = "Restore default bindings"
	reset.pressed.connect(func() -> void:
		for action: StringName in GameInput.defaults:
			InputMap.action_erase_events(action)
			for event: InputEvent in GameInput.defaults[action]:
				InputMap.action_add_event(action, event)
		GameInput.save_bindings()
		status.text = "Defaults restored")
	rows.add_child(reset)
	controls.append(reset)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(queue_free)
	rows.add_child(back)
	controls.append(back)
	SettingsPanel.wire_focus(controls)
	controls[0].grab_focus()

func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if waiting.is_empty():
		if event.is_action_pressed("ui_cancel"):
			queue_free()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		waiting = &""
		status.text = "Cancelled"
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion or not event.is_pressed():
		return
	if event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) < 0.6:
		return
	if GameInput.encode(event).is_empty():
		return
	var error: String = GameInput.rebind(waiting, event)
	if error.is_empty():
		var saved: Error = GameInput.save_bindings()
		status.text = "Saved" if saved == OK else "Could not save bindings"
		buttons[waiting].text = String(waiting) + " : " + event.as_text()
	else:
		status.text = error
	waiting = &""
	get_viewport().set_input_as_handled()
