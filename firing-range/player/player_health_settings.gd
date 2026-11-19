class_name PlayerHealthSettings
extends TargetSettings
## Player tuning. Inherits the dummy's health, plate and hit-zone multiplier
## fields so both follow the same armor-first rules. `reset_seconds` is the
## time spent on the death screen before respawning.

## Seconds without taking damage before health starts to regenerate.
@export_range(0.0, 30.0, 0.1, "suffix:s") var regen_delay_seconds: float = 4.0
## Health restored per second once regeneration starts. Armor never regenerates.
@export_range(0.0, 200.0, 1.0, "suffix:hp/s") var regen_per_second: float = 25.0
## Spare plates carried outside the vest at spawn.
@export_range(0, 20) var spare_plates: int = 5
## Seconds to insert one plate, counted once the weapon is fully put away.
@export_range(0.1, 5.0, 0.05, "suffix:s") var plate_insert_seconds: float = 1.2
