extends Node
## Autoload `ViewSettings`: player-facing view options (FOV, mouse sensitivity,
## head bob). Persisted to `user://settings.cfg`.
##
## Preferences never change movement tuning or projectile simulation.

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


var ads_sensitivity_multiplier: float = 1.0:
	set(value):
		ads_sensitivity_multiplier = clampf(value, 0.1, 2.0)
		changed.emit()

var master_volume: float = 1.0:
	set(value):
		master_volume = clampf(value, 0.0, 1.0)
		changed.emit()

var effects_volume: float = 1.0:
	set(value):
		effects_volume = clampf(value, 0.0, 1.0)
		changed.emit()

var show_fps: bool = true:
	set(value):
		show_fps = value
		changed.emit()

## False starts the range's time-to-kill clock at the first damaging hit on a
## dummy (the original behaviour). True starts it when the shot that first
## damaged the dummy was fired, so bullet flight time counts.
var ttk_from_first_shot: bool = false:
	set(value):
		ttk_from_first_shot = value
		changed.emit()

## Range mode: hits on the player are reported but do no damage. Game modes
## that need a vulnerable player set this on their own PlayerHealth.
var range_invulnerable: bool = true:
	set(value):
		range_invulnerable = value
		changed.emit()

## False spawns (and respawns) the player with an empty vest; plates are
## then inserted from the spares by hand.
var preload_plates: bool = true:
	set(value):
		preload_plates = value
		changed.emit()

## Shows the plates in the vest and the spares carried on the HUD.
var show_armor_plates: bool = true:
	set(value):
		show_armor_plates = value
		changed.emit()

var stick_x: float = 180.0
var stick_y: float = 120.0
var stick_deadzone: float = 0.15
var stick_dynamic: bool = false
var stick_invert_y: bool = false
var aim_assist: float = 0.5
var rumble_scale: float = 0.5
var toggle_ads: bool = false
var toggle_crouch: bool = false
var toggle_sprint: bool = false
var auto_sprint: bool = false

const KEYS: PackedStringArray = ["stick_x", "stick_y", "stick_deadzone", "stick_dynamic", "stick_invert_y", "aim_assist", "rumble_scale", "toggle_ads", "toggle_crouch", "toggle_sprint", "auto_sprint", "fov_degrees", "mouse_sensitivity", "invert_y", "head_bob_scale", "fov_kick_scale", "ads_sensitivity_multiplier", "master_volume", "effects_volume", "show_fps", "ttk_from_first_shot", "range_invulnerable", "show_armor_plates", "preload_plates"]


func _ready() -> void:
	load_from_disk()
	changed.connect(_apply_audio)
	_apply_audio()


func _apply_audio() -> void:
	for entry: Array in [[&"Master", master_volume], [&"Effects", effects_volume]]:
		var index: int = AudioServer.get_bus_index(entry[0])
		if index >= 0:
			var volume: float = entry[1]
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))
			AudioServer.set_bus_mute(index, volume <= 0.0)


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


func load_from_disk(path: String = SAVE_PATH) -> void:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	for key: String in KEYS:
		set(key, config.get_value(SECTION, key, get(key)))


func save_to_disk(path: String = SAVE_PATH) -> Error:
	var config := ConfigFile.new()
	# Retain other sections if later phases add their own preferences.
	config.load(path)
	for key: String in KEYS:
		config.set_value(SECTION, key, get(key))
	var error: Error = config.save(path)
	if error != OK:
		push_warning("ViewSettings: could not save %s (error %d)" % [path, error])
	return error
