class_name CameraFeel
extends Node3D
## Cosmetic camera motion: head bob, landing dip, slide drop/tilt and the
## sprint/slide FOV kick.
##
## This node only reads player state and offsets itself (and the camera FOV)
## relative to the gameplay eye. It never writes to the player, so nothing
## here can change movement or, later, where bullets go.

@export var player: PlayerController
@export var camera: Camera3D

@export_group("Head bob")
## Metres travelled per full bob cycle (one left step plus one right step).
@export_range(0.5, 6.0, 0.05, "suffix:m") var bob_stride_length: float = 2.6
@export_range(0.0, 0.2, 0.001, "suffix:m") var bob_vertical_amplitude: float = 0.03
@export_range(0.0, 0.2, 0.001, "suffix:m") var bob_horizontal_amplitude: float = 0.018
## Speed at which the bob reaches its authored amplitude, m/s.
@export_range(0.5, 12.0, 0.1, "suffix:m/s") var bob_reference_speed: float = 4.5
## Bob never grows past this multiple of the authored amplitude.
@export_range(1.0, 3.0, 0.05) var bob_max_scale: float = 1.4
## How quickly the bob fades in and out, 1/s.
@export_range(1.0, 30.0, 0.5, "suffix:1/s") var bob_blend_rate: float = 10.0

@export_group("Landing dip")
## Downward camera velocity (m/s) added per m/s of landing speed.
@export_range(0.0, 1.0, 0.01) var landing_kick_per_speed: float = 0.4
@export_range(0.0, 3.0, 0.05, "suffix:m/s") var landing_kick_max: float = 1.4
## Spring that pulls the camera back up. Higher is snappier.
@export_range(20.0, 600.0, 5.0) var landing_spring_stiffness: float = 180.0
## 1.0 is critically damped (no bounce).
@export_range(0.2, 2.0, 0.05) var landing_spring_damping_ratio: float = 0.9

@export_group("Slide")
@export_range(0.0, 0.5, 0.01, "suffix:m") var slide_camera_drop: float = 0.18
@export_range(0.0, 15.0, 0.5, "suffix:°") var slide_roll_degrees: float = 3.5
@export_range(1.0, 30.0, 0.5, "suffix:1/s") var slide_blend_rate: float = 12.0

@export_group("FOV kick")
@export_range(0.0, 20.0, 0.5, "suffix:°") var sprint_fov_add: float = 4.0
@export_range(0.0, 20.0, 0.5, "suffix:°") var slide_fov_add: float = 7.0
@export_range(1.0, 30.0, 0.5, "suffix:1/s") var fov_blend_rate: float = 8.0

## Set by the weapon view while aiming: 0 at the hip, 1 fully aimed. The
## camera FOV blends from the player's FOV setting to `aim_fov_degrees`.
var aim_blend: float = 0.0
## Vertical FOV when fully aimed, from the current weapon.
var aim_fov_degrees: float = 65.0

var _bob_phase: float = 0.0
var _bob_weight: float = 0.0
var _dip: float = 0.0
var _dip_velocity: float = 0.0
var _slide_blend: float = 0.0
var _fov_kick: float = 0.0


func _ready() -> void:
	if player == null or camera == null:
		push_error("CameraFeel: `player` and `camera` must be assigned.")
		set_process(false)
		return
	player.landed.connect(_on_player_landed)
	camera.fov = ViewSettings.fov_degrees


func _process(delta: float) -> void:
	var speed: float = player.get_horizontal_speed()
	var grounded: bool = player.is_grounded()
	var sliding: bool = player.is_sliding()
	var bob_scale: float = ViewSettings.head_bob_scale

	# Head bob: the phase advances with distance travelled, so steps stay in
	# sync with ground speed instead of with time.
	var bob_target: float = 0.0
	if grounded and not sliding:
		bob_target = clampf(speed / bob_reference_speed, 0.0, bob_max_scale)
		_bob_phase = wrapf(_bob_phase + speed * delta / bob_stride_length * TAU, 0.0, TAU * 2.0)
	_bob_weight = lerpf(_bob_weight, bob_target, _blend(bob_blend_rate, delta))

	var bob_x: float = sin(_bob_phase) * bob_horizontal_amplitude * _bob_weight * bob_scale
	var bob_y: float = -absf(sin(_bob_phase)) * bob_vertical_amplitude * _bob_weight * bob_scale

	_step_landing_spring(delta)

	_slide_blend = lerpf(_slide_blend, 1.0 if sliding else 0.0, _blend(slide_blend_rate, delta))

	position = Vector3(
		bob_x,
		bob_y - _dip * bob_scale - slide_camera_drop * _slide_blend,
		0.0
	)
	rotation = Vector3(0.0, 0.0, deg_to_rad(slide_roll_degrees) * _slide_blend)

	var kick_target: float = 0.0
	if sliding:
		kick_target = slide_fov_add
	elif player.is_sprinting and speed > player.settings.walk_speed:
		kick_target = sprint_fov_add
	_fov_kick = lerpf(_fov_kick, kick_target, _blend(fov_blend_rate, delta))
	var hip_fov: float = ViewSettings.fov_degrees + _fov_kick * ViewSettings.fov_kick_scale
	camera.fov = lerpf(hip_fov, aim_fov_degrees, clampf(aim_blend, 0.0, 1.0))


func _on_player_landed(impact_speed: float) -> void:
	_dip_velocity += minf(impact_speed * landing_kick_per_speed, landing_kick_max)


## Damped spring pulling `_dip` back to zero. Sub-stepped so a long frame
## cannot make it unstable.
func _step_landing_spring(delta: float) -> void:
	const MAX_STEP: float = 1.0 / 120.0
	var damping: float = 2.0 * sqrt(landing_spring_stiffness) * landing_spring_damping_ratio
	var remaining: float = minf(delta, 0.1)
	while remaining > 0.0:
		var step: float = minf(remaining, MAX_STEP)
		_dip_velocity += (-landing_spring_stiffness * _dip - damping * _dip_velocity) * step
		_dip += _dip_velocity * step
		remaining -= step


## Frame-rate independent blend factor for `lerpf(current, target, factor)`.
func _blend(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)
