class_name PlayerStatusView
extends Control
## Read-only health bar, vest plates, spare count and plate-insert progress.

@export var bar_width: float = 252.0
@export var health_height: float = 10.0
@export var plate_height: float = 8.0
@export var plate_gap: float = 6.0
## Distance of the health bar's bottom edge above the screen bottom. The bar
## is centred; the left edge holds debug lists and the right the ammo.
@export var bottom_margin: float = 46.0
@export var health_color: Color = Color(0.92, 0.94, 0.95)
@export var low_health_color: Color = Color(1.0, 0.35, 0.3)
@export var plate_color: Color = Color(0.25, 0.65, 1.0)
@export var empty_color: Color = Color(0.0, 0.0, 0.0, 0.45)
@export var progress_width: float = 220.0

var health: PlayerHealth
var _plates_label: Label
var _insert_label: Label
var _signature: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plates_label = _make_label(14)
	_insert_label = _make_label(15)
	_insert_label.text = "INSERTING PLATE"
	_insert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ViewSettings.changed.connect(queue_redraw)
	GameInput.device_changed.connect(func() -> void: _signature = "")


func _make_label(size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(label)
	return label


func _process(_delta: float) -> void:
	if health == null:
		return
	var vitals: PlayerVitals = health.vitals
	# Redraw only when something visible changed.
	var signature: String = "%.1f|%.1f|%d|%.3f|%s|%s|%s" % [vitals.health, vitals.armor, vitals.spare_plates, health.plate_progress(), health.plating, vitals.dead, ViewSettings.show_armor_plates]
	if signature == _signature:
		return
	_signature = signature
	_layout()
	queue_redraw()


func get_plates_text() -> String:
	return _plates_label.text if _plates_label.visible else ""


func _health_origin() -> Vector2:
	return Vector2((size.x - bar_width) * 0.5, size.y - bottom_margin - health_height)


func _layout() -> void:
	var vitals: PlayerVitals = health.vitals
	_plates_label.visible = ViewSettings.show_armor_plates and not vitals.dead
	_plates_label.text = "VEST %d/%d   SPARES %d   [%s] PLATE" % [vitals.remaining_plates(), vitals.plate_count, vitals.spare_plates, GameInput.prompt(&"apply_plate").replace(" - Physical", "")]
	_plates_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plates_label.size.x = bar_width + 120.0
	_plates_label.position = _health_origin() + Vector2(-60.0, -plate_height - plate_gap - 26.0)
	_insert_label.visible = health.plating and not vitals.dead
	_insert_label.size.x = progress_width
	_insert_label.position = Vector2((size.x - progress_width) * 0.5, size.y * 0.66)


func _draw() -> void:
	if health == null or health.vitals.dead:
		return
	var vitals: PlayerVitals = health.vitals
	var origin: Vector2 = _health_origin()
	var fraction: float = vitals.health / vitals.settings.max_health
	draw_rect(Rect2(origin - Vector2.ONE, Vector2(bar_width, health_height) + Vector2.ONE * 2.0), Color(0, 0, 0, 0.6), false, 1.0)
	draw_rect(Rect2(origin, Vector2(bar_width, health_height)), empty_color)
	draw_rect(Rect2(origin, Vector2(bar_width * fraction, health_height)), low_health_color if fraction < 0.35 else health_color)
	if ViewSettings.show_armor_plates and vitals.plate_count > 0:
		var count: int = vitals.plate_count
		var width: float = (bar_width - plate_gap * float(count - 1)) / float(count)
		for index: int in count:
			var corner := Vector2(origin.x + float(index) * (width + plate_gap), origin.y - plate_height - plate_gap)
			draw_rect(Rect2(corner, Vector2(width, plate_height)), empty_color)
			draw_rect(Rect2(corner, Vector2(width * vitals.plate_fill(index), plate_height)), plate_color)
	if health.plating:
		var bar := Rect2(Vector2((size.x - progress_width) * 0.5, size.y * 0.66 + 26.0), Vector2(progress_width, 6.0))
		draw_rect(bar, empty_color)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * health.plate_progress(), bar.size.y)), plate_color)
