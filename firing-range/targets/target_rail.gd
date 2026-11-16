class_name TargetRail
extends Node3D
## A reflected distance clock preserves speed, including endpoint overshoot.
## Children (including a dummy) move with this carrier at the physics tick.

@export var length: float = 4.0
@export var speed: float = 1.5
var distance: float = 0.0
var direction: float = 1.0
var _origin: Vector3


func _ready() -> void:
	_origin = position


func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if length <= 0.0:
		return
	# Map the outgoing/returning leg onto a single increasing phase, then
	# fold it into the rail. Handles even multiple reversals in one step.
	var phase: float = distance if direction > 0.0 else 2.0 * length - distance
	phase = fposmod(phase + speed * delta, 2.0 * length)
	distance = phase if phase < length else 2.0 * length - phase
	direction = 1.0 if phase < length else -1.0
	position = _origin + Vector3.RIGHT * distance
