class_name DamageIndicator
extends Control
## Pooled arcs around the crosshair pointing at where damage came from. Each
## stores the world direction and re-aims as the player turns. Cosmetic only.

@export_range(1, 16) var capacity: int = 6
@export var lifetime: float = 1.6
@export var radius: float = 120.0
@export var arc_radians: float = 0.55
@export var thickness: float = 7.0
@export var damage_color: Color = Color(1.0, 0.2, 0.15, 0.9)
@export var blocked_color: Color = Color(1.0, 1.0, 1.0, 0.55)

var player: PlayerController
var _directions: PackedVector3Array = PackedVector3Array()
var _ages: PackedFloat32Array = PackedFloat32Array()
var _applied: PackedByteArray = PackedByteArray()
var _next: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_directions.resize(capacity)
	_ages.resize(capacity)
	_applied.resize(capacity)
	_ages.fill(lifetime)


func show_damage(incoming: Vector3, applied: bool) -> void:
	if is_nan(DamageDirection.screen_angle(incoming, 0.0)):
		return
	_directions[_next] = incoming
	_ages[_next] = 0.0
	_applied[_next] = 1 if applied else 0
	_next = (_next + 1) % capacity
	queue_redraw()


func clear() -> void:
	_ages.fill(lifetime)
	queue_redraw()


func active_count() -> int:
	var count: int = 0
	for age: float in _ages:
		if age < lifetime:
			count += 1
	return count


## Screen angle of the newest active arc, NAN if none.
func newest_angle() -> float:
	var index: int = posmod(_next - 1, capacity)
	if _ages[index] >= lifetime or player == null:
		return NAN
	return DamageDirection.screen_angle(_directions[index], player.yaw)


func _process(delta: float) -> void:
	if active_count() == 0:
		return
	for index: int in capacity:
		_ages[index] = minf(_ages[index] + delta, lifetime)
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var centre: Vector2 = size * 0.5
	for index: int in capacity:
		if _ages[index] >= lifetime:
			continue
		var angle: float = DamageDirection.screen_angle(_directions[index], player.yaw)
		var color: Color = damage_color if _applied[index] == 1 else blocked_color
		color.a *= 1.0 - _ages[index] / lifetime
		# Screen angle 0 is up and clockwise; draw_arc measures from +X.
		var middle: float = angle - PI * 0.5
		draw_arc(centre, radius, middle - arc_radians * 0.5, middle + arc_radians * 0.5, 16, color, thickness, true)
