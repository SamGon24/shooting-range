class_name TargetHealth
extends RefCounted
## Node-free armor, health and reset clock; stepped by the dummy at 60 Hz.

var settings: TargetSettings
var health: float
var armor: float
var dead: bool = false
var down_time: float = 0.0
var plate_count: int


func _init(tuning: TargetSettings, plates: int = -1) -> void:
	settings = tuning
	plate_count = clampi(tuning.armor_plates if plates < 0 else plates, 0, 3)
	reset()


func reset() -> void:
	health = settings.max_health
	armor = float(plate_count) * settings.plate_health
	dead = false
	down_time = 0.0


func apply_damage(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	var absorbed: float = minf(armor, amount)
	armor -= absorbed
	health = maxf(0.0, health - (amount - absorbed))
	dead = health <= 0.0


## Returns true only on the tick that restores the target.
func advance(delta: float) -> bool:
	if not dead:
		return false
	down_time += delta
	if down_time + 0.000001 < settings.reset_seconds:
		return false
	reset()
	return true


func remaining_plates() -> int:
	return ceili(armor / settings.plate_health)
