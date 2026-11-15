extends Node
## Autoload `ViewSettings`: player-facing view options (FOV, mouse sensitivity,
## head bob). Persisted to `user://settings.cfg`.
##
## These are presentation/input preferences only. Nothing here may change
## movement or hit results.

signal changed

const SAVE_PATH: String = "user://settings.cfg"
const SECTION: String = "view"

## Vertical FOV limits in degrees (Godot cameras use vertical FOV).
const FOV_MIN: float = 50.0
const FOV_MAX: float = 100.0
const FOV_STEP: float = 5.0

## Degrees of camera rotation per mouse count.
const SENSITIVITY_MIN: float = 0.01
const SENSITIVITY_MAX: float = 1.0
const SENSITIVITY_STEP_RATIO: float = 1.1

## Vertical field of view in degrees. 65 vertical is about 97 horizontal at 16:9.
var fov_degrees: float = 65.0:
	set(value):
		fov_degrees = clampf(value, FOV_MIN, FOV_MAX)
		changed.emit()

## Degrees of rotation per mouse count, before any per-weapon ADS scaling.
var mouse_sensitivity: float = 0.10:
	set(value):
		mouse_sensitivity = clampf(value, SENSITIVITY_MIN, SENSITIVITY_MAX)
		changed.emit()

var invert_y: bool = false:
	set(value):
		invert_y = value
		changed.emit()

## 0 disables head bob and landing dip entirely, 1 is the authored amount.
var head_bob_scale: float = 1.0:
	set(value):
		head_bob_scale = clampf(value, 0.0, 2.0)
		changed.emit()

## 0 disables the sprint/slide FOV kick, 1 is the authored amount.
var fov_kick_scale: float = 1.0:
	set(value):
		fov_kick_scale = clampf(value, 0.0, 2.0)
		changed.emit()


func _ready() -> void:
	load_from_disk()


## Horizontal FOV in degrees for the given aspect ratio (width / height).
func horizontal_fov_degrees(aspect: float) -> float:
	var half_vertical: float = deg_to_rad(fov_degrees) * 0.5
	return rad_to_deg(2.0 * atan(tan(half_vertical) * aspect))


func step_fov(direction: int) -> void:
	fov_degrees += FOV_STEP * float(direction)


func step_sensitivity(direction: int) -> void:
	if direction > 0:
		mouse_sensitivity *= SENSITIVITY_STEP_RATIO
	elif direction < 0:
		mouse_sensitivity /= SENSITIVITY_STEP_RATIO


func load_from_disk() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	fov_degrees = float(config.get_value(SECTION, "fov_degrees", fov_degrees))
	mouse_sensitivity = float(config.get_value(SECTION, "mouse_sensitivity", mouse_sensitivity))
	invert_y = bool(config.get_value(SECTION, "invert_y", invert_y))
	head_bob_scale = float(config.get_value(SECTION, "head_bob_scale", head_bob_scale))
	fov_kick_scale = float(config.get_value(SECTION, "fov_kick_scale", fov_kick_scale))


func save_to_disk() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "fov_degrees", fov_degrees)
	config.set_value(SECTION, "mouse_sensitivity", mouse_sensitivity)
	config.set_value(SECTION, "invert_y", invert_y)
	config.set_value(SECTION, "head_bob_scale", head_bob_scale)
	config.set_value(SECTION, "fov_kick_scale", fov_kick_scale)
	var error: Error = config.save(SAVE_PATH)
	if error != OK:
		push_warning("ViewSettings: could not save %s (error %d)" % [SAVE_PATH, error])
