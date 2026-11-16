class_name Crosshair
extends Control
## A simple four-line crosshair with a centre dot, drawn at the middle of
## the screen. Static for now; Milestone 5 makes the gap follow weapon spread.

## Distance from the centre to the start of each line, pixels.
@export_range(0.0, 40.0, 0.5, "suffix:px") var gap: float = 6.0:
	set(value):
		gap = value
		queue_redraw()
@export_range(1.0, 40.0, 0.5, "suffix:px") var line_length: float = 8.0
@export_range(1.0, 6.0, 0.5, "suffix:px") var thickness: float = 2.0
@export_range(0.0, 6.0, 0.5, "suffix:px") var dot_size: float = 2.0
@export var color: Color = Color(1.0, 1.0, 1.0, 0.9)
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.6)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var centre: Vector2 = (size * 0.5).floor()
	for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		var from: Vector2 = centre + direction * gap
		var to: Vector2 = centre + direction * (gap + line_length)
		_draw_bar(from, to, thickness + 2.0, outline_color)
		_draw_bar(from, to, thickness, color)
	if dot_size > 0.0:
		_draw_square(centre, dot_size + 2.0, outline_color)
		_draw_square(centre, dot_size, color)


func _draw_bar(from: Vector2, to: Vector2, width: float, bar_color: Color) -> void:
	var top_left := Vector2(minf(from.x, to.x), minf(from.y, to.y))
	var extent := Vector2(absf(to.x - from.x), absf(to.y - from.y))
	var half: float = width * 0.5
	# Grow the thin axis to `width`, and the long axis by the outline margin.
	var margin: float = (width - thickness) * 0.5
	if extent.x > extent.y:
		draw_rect(Rect2(top_left.x - margin, top_left.y - half, extent.x + margin * 2.0, width), bar_color)
	else:
		draw_rect(Rect2(top_left.x - half, top_left.y - margin, width, extent.y + margin * 2.0), bar_color)


func _draw_square(centre: Vector2, side: float, square_color: Color) -> void:
	draw_rect(Rect2(centre - Vector2.ONE * side * 0.5, Vector2.ONE * side), square_color)
