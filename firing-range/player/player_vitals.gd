class_name PlayerVitals
extends TargetHealth
## Node-free player state on top of the dummy's armor-first health: delayed
## health regeneration, spare plates and plate insertion. Stepped at 60 Hz.

var since_damage: float = 0.0
var spare_plates: int = 0
## True while a plate insert is counting. The owner starts it only once the
## weapon is put away; `advance_insert` does the timing.
var inserting: bool = false
var insert_elapsed: float = 0.0


func _init(tuning: PlayerHealthSettings) -> void:
	super(tuning)


func tuning() -> PlayerHealthSettings:
	return settings as PlayerHealthSettings


func reset() -> void:
	super.reset()
	since_damage = 0.0
	spare_plates = (settings as PlayerHealthSettings).spare_plates
	inserting = false
	insert_elapsed = 0.0


func apply_damage(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	super.apply_damage(amount)
	since_damage = 0.0
	if dead:
		inserting = false
		insert_elapsed = 0.0


func max_armor() -> float:
	return float(plate_count) * settings.plate_health


## Health regeneration while alive; while dead, the inherited respawn clock.
## Returns true only on the tick that restores the player.
func advance(delta: float) -> bool:
	if dead:
		return super.advance(delta)
	since_damage += delta
	# Only the part of this tick past the delay regenerates, so the result
	# does not depend on where tick boundaries fall.
	var past_delay: float = since_damage - tuning().regen_delay_seconds
	if past_delay > 0.0 and health < settings.max_health:
		health = minf(settings.max_health, health + tuning().regen_per_second * minf(delta, past_delay))
	return false


func can_insert_plate() -> bool:
	return not dead and spare_plates > 0 and armor < max_armor() - 0.0001


## Fills the lowest damaged or empty plate to full. Returns false if no
## plate could be used.
func insert_plate() -> bool:
	if not can_insert_plate():
		return false
	var full_plates: int = floori(armor / settings.plate_health + 0.0001)
	armor = minf(float(full_plates + 1) * settings.plate_health, max_armor())
	spare_plates -= 1
	return true


func begin_insert() -> bool:
	if inserting or not can_insert_plate():
		return false
	inserting = true
	insert_elapsed = 0.0
	return true


func cancel_insert() -> void:
	inserting = false
	insert_elapsed = 0.0


## Insert progress from 0 to 1.
func insert_progress() -> float:
	return clampf(insert_elapsed / tuning().plate_insert_seconds, 0.0, 1.0) if inserting else 0.0


## Times the current insert. Returns true on the tick a plate goes in.
func advance_insert(delta: float) -> bool:
	if not inserting:
		return false
	insert_elapsed += delta
	if insert_elapsed + 0.000001 < tuning().plate_insert_seconds:
		return false
	inserting = false
	insert_elapsed = 0.0
	return insert_plate()


## Health and plate durability, for the HUD. Each plate is 0..1.
func plate_fill(index: int) -> float:
	return clampf((armor - float(index) * settings.plate_health) / settings.plate_health, 0.0, 1.0)
