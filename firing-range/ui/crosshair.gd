class_name Crosshair
extends Control
## A simple four-line crosshair with a centre dot, drawn at the middle of
## the screen. The extra radius projects the current gameplay spread cone.

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


var spread_radius: float = 0.0


## Project a cone half-angle through the active camera's vertical FOV.
func set_spread(spread_degrees: float, vertical_fov: float, viewport_height: float) -> void:
	var radius: float = tan(deg_to_rad(spread_degrees)) * viewport_height / (2.0 * tan(deg_to_rad(vertical_fov) * 0.5))
	if not is_equal_approx(radius, spread_radius):
		spread_radius = radius
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var centre: Vector2 = (size * 0.5).floor()
	for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		var from: Vector2 = centre + direction * (gap + spread_radius)
		var to: Vector2 = centre + direction * (gap + spread_radius + line_length)
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
