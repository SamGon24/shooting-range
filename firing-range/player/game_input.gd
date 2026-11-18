extends Node
## Input preferences and device lifecycle. Never owns ballistic state.
signal device_changed
signal controller_lost
const BINDINGS_PATH: String = "user://bindings.cfg"
var prompt_label: Label
var menu_prompts: bool = false
var disconnect_notice: String = ""
var controller_active: bool = false
var active_device: int = -1
var toggles: Dictionary[String, bool] = {}
var defaults: Dictionary[StringName, Array] = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for action: StringName in [ &"look_left", &"look_right", &"look_up", &"look_down", &"weapon_swap", &"melee" ]:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.0)
	for entry: Array in [["move_left",0,-1.0],["move_right",0,1.0],["move_forward",1,-1.0],["move_back",1,1.0],["look_left",2,-1.0],["look_right",2,1.0],["look_up",3,-1.0],["look_down",3,1.0],["fire",5,1.0],["aim",4,1.0]]:
		var motion := InputEventJoypadMotion.new()
		motion.device = -1
		motion.axis = int(entry[1]) as JoyAxis
		motion.axis_value = float(entry[2])
		InputMap.action_add_event(entry[0], motion)
	for entry: Array in [["jump",0],["crouch",1],["reload",2],["weapon_swap",3],["weapon_prev",9],["weapon_next",10],["sprint",7],["melee",8],["zero_cycle",11],["range_stats_reset",4]]:
		var button := InputEventJoypadButton.new()
		button.device = -1
		button.button_index = int(entry[1]) as JoyButton
		InputMap.action_add_event(entry[0], button)
	var melee_key := InputEventKey.new()
	melee_key.physical_keycode = KEY_V
	InputMap.action_add_event("melee", melee_key)
	for action: StringName in InputMap.get_actions():
		defaults[action] = InputMap.action_get_events(action)
	load_bindings()
	Input.joy_connection_changed.connect(connection_changed)
	var layer := CanvasLayer.new()
	layer.layer = 210
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(12, 694)
	label.add_theme_font_size_override("font_size", 12)
	layer.add_child(label)
	prompt_label = label
	device_changed.connect(_refresh_prompts)
	_refresh_prompts()

func _process(_delta: float) -> void:
	var in_menu: bool = get_tree().paused or get_tree().get_first_node_in_group(WeaponController.GROUP) == null
	if in_menu != menu_prompts:
		menu_prompts = in_menu
		_refresh_prompts()

func _refresh_prompts() -> void:
	if prompt_label == null:
		return
	prompt_label.text = disconnect_notice + "  "
	if menu_prompts:
		prompt_label.text += "%s Select  |  %s Back" % [prompt("ui_accept"), prompt("ui_cancel")]
	else:
		prompt_label.text += "%s Fire  |  %s Reload  |  %s Pause" % [prompt("fire"), prompt("reload"), prompt("pause")]

func _input(event: InputEvent) -> void:
	observe(event)

func observe(event: InputEvent) -> void:
	var pad: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
	if event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) <= maxf(0.2, ViewSettings.stick_deadzone):
		return
	if not pad and not (event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length_squared() < 1.0:
		return
	var had_notice: bool = not disconnect_notice.is_empty()
	disconnect_notice = ""
	active_device = event.device if pad else -1
	if controller_active != pad or had_notice:
		controller_active = pad
		device_changed.emit()

func connection_changed(device: int, connected: bool) -> void:
	if connected or device != active_device:
		return
	disconnect_notice = "Controller disconnected. Reconnect or use keyboard/mouse."
	clear()
	Input.stop_joy_vibration(device)
	active_device = -1
	controller_active = false
	device_changed.emit()
	controller_lost.emit()

func clear() -> void:
	toggles.clear()
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)
	var weapons := get_tree().get_first_node_in_group(WeaponController.GROUP) as WeaponController
	if weapons != null:
		weapons.clear_input_latches()

func held(action: String, toggle: bool) -> bool:
	if not toggle:
		return Input.is_action_pressed(action)
	if Input.is_action_just_pressed(action):
		toggles[action] = not toggles.get(action, false)
	return toggles.get(action, false)

func vibrate(kind: String = "fire") -> void:
	if not controller_active or active_device < 0:
		return
	var amount: float = clampf(ViewSettings.rumble_scale, 0.0, 1.0)
	Input.start_joy_vibration(active_device, amount * 0.4, amount, 0.18 if kind != "reload" else 0.3)

func encode(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		return {"type":"key", "code":key.physical_keycode if key.physical_keycode != 0 else key.keycode, "physical":key.physical_keycode != 0}
	if event is InputEventMouseButton:
		return {"type":"mouse", "code":(event as InputEventMouseButton).button_index}
	if event is InputEventJoypadButton:
		return {"type":"button", "code":(event as InputEventJoypadButton).button_index}
	if event is InputEventJoypadMotion:
		return {"type":"axis", "code":(event as InputEventJoypadMotion).axis, "sign":signf((event as InputEventJoypadMotion).axis_value)}
	return {}

func decode(data: Dictionary) -> InputEvent:
	var event: InputEvent
	var code: int = int(data.get("code", -1))
	if code < 0 or code > 0x7fffffff:
		return null
	match data.get("type", ""):
		"key":
			var key := InputEventKey.new()
			if bool(data.get("physical", true)):
				key.physical_keycode = code as Key
			else:
				key.keycode = code as Key
			event = key
		"mouse":
			if code > 9: return null
			var mouse := InputEventMouseButton.new()
			mouse.button_index = code as MouseButton
			event = mouse
		"button":
			if code >= JOY_BUTTON_MAX: return null
			var button := InputEventJoypadButton.new()
			button.button_index = code as JoyButton
			event = button
		"axis":
			if code >= JOY_AXIS_MAX: return null
			var motion := InputEventJoypadMotion.new()
			motion.axis = code as JoyAxis
			motion.axis_value = float(data.get("sign", 1.0))
			event = motion
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		event.device = -1
	return event

func conflict(action: StringName, event: InputEvent) -> String:
	for other: StringName in InputMap.get_actions():
		if other == action or String(other).begins_with("ui_"):
			continue
		for binding: InputEvent in InputMap.action_get_events(other):
			if encode(binding) == encode(event):
				return String(other)
	return ""

func rebind(action: StringName, event: InputEvent) -> String:
	var other: String = conflict(action, event)
	if not other.is_empty():
		return "Already bound to " + other
	# Replace this device category; preserve the other devices.
	for old: InputEvent in InputMap.action_get_events(action):
		if encode(old).get("type") == encode(event).get("type"):
			InputMap.action_erase_event(action, old)
	InputMap.action_add_event(action, event)
	device_changed.emit()
	return ""

func save_bindings(path: String = BINDINGS_PATH) -> Error:
	var config := ConfigFile.new()
	config.set_value("format", "version", 1)
	for action: StringName in defaults:
		if String(action).begins_with("ui_"):
			continue
		var events: Array[Dictionary] = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(encode(event))
		config.set_value("actions", action, events)
	return config.save(path)

func load_bindings(path: String = BINDINGS_PATH) -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK or config.get_value("format", "version", 0) != 1:
		return
	for action: StringName in defaults:
		if String(action).begins_with("ui_"):
			continue
		var stored: Variant = config.get_value("actions", action, null)
		if not stored is Array:
			continue
		var events: Array[InputEvent] = []
		for data: Variant in stored:
			if data is Dictionary:
				var event: InputEvent = decode(data)
				if event != null:
					events.append(event)
		if events.is_empty():
			continue
		InputMap.action_erase_events(action)
		for event: InputEvent in events:
			InputMap.action_add_event(action, event)

func prompt(action: StringName) -> String:
	for event: InputEvent in InputMap.action_get_events(action):
		if controller_active and event is InputEventJoypadButton:
			if active_device in Input.get_connected_joypads() and not Input.is_joy_known(active_device):
				return event.as_text()
			var labels: Dictionary = {0:"A",1:"B",2:"X",3:"Y",4:"Back",6:"Start",7:"LS",8:"RS",9:"LB",10:"RB",11:"D-pad Up"}
			return str(labels.get((event as InputEventJoypadButton).button_index, event.as_text()))
		if controller_active and event is InputEventJoypadMotion:
			return {4:"LT",5:"RT"}.get((event as InputEventJoypadMotion).axis, event.as_text())
		if not controller_active and (event is InputEventKey or event is InputEventMouseButton):
			return event.as_text()
	return String(action)
