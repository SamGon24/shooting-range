class_name FeedbackView
extends Control
## Cosmetic hitmarker and fixed-size screen labels anchored to world hits.
## All labels are pooled once; feedback never creates nodes or alters damage.

@export_group("Marker")
@export var marker_hold_seconds: float = 0.10
@export var marker_fade_seconds: float = 0.18
@export var marker_gap: float = 8.0
@export var marker_length: float = 7.0
@export var marker_thickness: float = 2.0
@export var kill_length: float = 12.0
@export var hit_color: Color = Color.WHITE
@export var armor_color: Color = Color(0.25, 0.65, 1.0)
@export var kill_color: Color = Color(1.0, 0.22, 0.20)
@export var marker_outline_color: Color = Color(0.0, 0.0, 0.0, 0.7)

@export_group("Damage numbers")
@export_range(1, 128) var number_capacity: int = 24
@export var number_lifetime: float = 0.8
@export var number_rise_pixels_per_second: float = 36.0
@export var number_horizontal_offset: float = 16.0
@export var number_font_size: int = 22
@export var number_outline_size: int = 4
@export var number_color: Color = Color.WHITE
@export var headshot_color: Color = Color(1.0, 0.78, 0.25)

var marker_kind: HitFeedback.Kind = HitFeedback.Kind.HIT
var _marker_age: float = INF
var _labels: Array[Label] = []
var _points: PackedVector3Array = PackedVector3Array()
var _ages: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0
var _number_keys: Dictionary[String, int] = {}
var _slot_keys: PackedStringArray = PackedStringArray()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_points.resize(number_capacity)
	_ages.resize(number_capacity)
	_slot_keys.resize(number_capacity)
	for index: int in number_capacity:
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", number_font_size)
		label.add_theme_constant_override("outline_size", number_outline_size)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.visible = false
		add_child(label)
		_labels.append(label)
		_ages[index] = number_lifetime


func show_feedback(kind: HitFeedback.Kind, point: Vector3, amount: float, headshot: bool) -> void:
	# Briefly retain a stronger marker if another target is hit immediately.
	if not is_marker_active() or kind >= marker_kind:
		marker_kind = kind
		_marker_age = 0.0
		queue_redraw()
	if amount <= 0.0:
		return
	var index: int = _allocate_number()
	_write_number(index, point, amount, headshot)


## Update one pooled label for all pellets of a shot hitting one target,
## even if their travel times put the impacts in different physics ticks.
func show_damage_total(shot_id: int, target_id: int, point: Vector3, amount: float, headshot: bool) -> void:
	var key: String = "%d:%d" % [shot_id, target_id]
	var index: int = _number_keys.get(key, -1)
	if index < 0:
		index = _allocate_number()
		_number_keys[key] = index
		_slot_keys[index] = key
	_write_number(index, point, amount, headshot)


func _allocate_number() -> int:
	var index: int = _next
	if not _slot_keys[index].is_empty():
		_number_keys.erase(_slot_keys[index])
		_slot_keys[index] = ""
	_next = (_next + 1) % number_capacity
	return index


func _write_number(index: int, point: Vector3, amount: float, headshot: bool) -> void:
	var label: Label = _labels[index]
	label.text = str(roundi(amount))
	label.add_theme_color_override("font_color", headshot_color if headshot else number_color)
	label.modulate.a = 1.0
	_points[index] = point
	_ages[index] = 0.0
	_update_numbers()


func clear_feedback() -> void:
	_marker_age = INF
	_number_keys.clear()
	_slot_keys.fill("")
	for index: int in _labels.size():
		_ages[index] = number_lifetime
		_labels[index].visible = false
	queue_redraw()


func is_marker_active() -> bool:
	return _marker_age < marker_hold_seconds + marker_fade_seconds


func get_marker_color() -> Color:
	match marker_kind:
		HitFeedback.Kind.ARMOR_BREAK:
			return armor_color
		HitFeedback.Kind.KILL:
			return kill_color
	return hit_color


func _process(delta: float) -> void:
	if is_marker_active():
		_marker_age += delta
		queue_redraw()
	for index: int in _ages.size():
		_ages[index] += delta
	_update_numbers()


func _update_numbers() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	for index: int in _labels.size():
		var label: Label = _labels[index]
		label.visible = _ages[index] < number_lifetime and camera != null
		if not label.visible:
			continue
		label.visible = not camera.is_position_behind(_points[index])
		if not label.visible:
			continue
		var side: float = -1.0 if index % 2 == 0 else 1.0
		label.position = camera.unproject_position(_points[index]) - label.size * 0.5 + Vector2(side * number_horizontal_offset, -_ages[index] * number_rise_pixels_per_second)
		label.modulate.a = clampf(1.0 - _ages[index] / number_lifetime, 0.0, 1.0)


func _draw() -> void:
	if not is_marker_active():
		return
	var alpha: float = 1.0 - clampf((_marker_age - marker_hold_seconds) / marker_fade_seconds, 0.0, 1.0)
	var color: Color = get_marker_color()
	color.a *= alpha
	var outline: Color = marker_outline_color
	outline.a *= alpha
	var centre: Vector2 = size * 0.5
	for direction: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var unit: Vector2 = direction.normalized()
		var gap: float = 0.0 if marker_kind == HitFeedback.Kind.KILL else marker_gap
		var length: float = kill_length if marker_kind == HitFeedback.Kind.KILL else marker_length
		var from: Vector2 = centre + unit * gap
		var to: Vector2 = centre + unit * (gap + length)
		draw_line(from, to, outline, marker_thickness + 2.0, true)
		draw_line(from, to, color, marker_thickness, true)
