class_name AttachmentDebug
extends CanvasLayer
## Temporary Armory controls: all input is through remappable actions.
const CATALOG: AttachmentCatalog = preload("res://weapons/attachments/data/catalog.tres")
const ACTIONS: PackedStringArray = ["attachment_muzzle", "attachment_barrel", "attachment_optic", "attachment_stock", "attachment_magazine"]
var _controller: WeaponController
var _overlay: CanvasLayer
var _label: Label
var _requests: Array[int] = []
var _clear_requested: bool = false


func _ready() -> void:
	layer = 11
	process_physics_priority = -10
	_label = Label.new()
	_label.anchor_top = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_left = 24
	_label.offset_top = -155
	_label.offset_right = 600
	_label.offset_bottom = -24
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_constant_override("outline_size", 3)
	add_child(_label)
	_bind.call_deferred()


func _bind() -> void:
	_controller = get_tree().get_first_node_in_group(WeaponController.GROUP) as WeaponController
	_overlay = get_tree().get_first_node_in_group(&"debug_overlay") as CanvasLayer
	if _controller != null:
		_controller.weapon_changed.connect(_on_weapon_changed)
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	for slot: int in ACTIONS.size():
		if event.is_action_pressed(ACTIONS[slot]) and not _requests.has(slot):
			_requests.append(slot)
	if event.is_action_pressed("attachment_clear"):
		_clear_requested = true


func _physics_process(_delta: float) -> void:
	if _controller == null or _controller.get_current_data() == null:
		return
	for slot: int in ACTIONS.size():
		if Input.is_action_just_pressed(ACTIONS[slot]) and not _requests.has(slot):
			_requests.append(slot)
	if _clear_requested or Input.is_action_just_pressed("attachment_clear"):
		for slot: int in ACTIONS.size():
			_controller.request_attachment(slot as WeaponTypes.Slot, null)
		_clear_requested = false
		_requests.clear()
		_refresh()
	for slot: int in _requests:
		cycle(slot as WeaponTypes.Slot)
	_requests.clear()


func cycle(slot: WeaponTypes.Slot) -> void:
	var current: AttachmentData = _controller.get_requested_attachment(slot)
	var next: AttachmentData = CATALOG.next_attachment(current, slot, _controller.get_current_data().weapon_class)
	_controller.request_attachment(slot, next)
	_refresh()


func _process(_delta: float) -> void:
	visible = _overlay != null and _overlay.visible


func _on_weapon_changed(_data: WeaponData) -> void:
	_refresh()


func _refresh() -> void:
	var lines := PackedStringArray()
	for slot: int in ACTIONS.size():
		var attachment: AttachmentData = _controller.get_requested_attachment(slot as WeaponTypes.Slot)
		lines.append("F%d %s: %s" % [5 + slot, WeaponTypes.SLOT_NAMES[slot], attachment.display_name if attachment != null else "None (native)"])
	lines.append("F10 Clear current weapon attachments")
	_label.text = "\n".join(lines)
