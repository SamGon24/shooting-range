class_name ProjectileSpec
extends Resource
## What a weapon fires. Units are SI except where the suffix says otherwise
## (grams and millimetres read more naturally for bullets).

## Speed leaving the barrel, m/s.
@export_range(50.0, 1500.0, 1.0, "suffix:m/s") var muzzle_velocity: float = 850.0
## Multiplies world gravity for this projectile. 1 is real gravity.
@export_range(0.0, 2.0, 0.01) var gravity_scale: float = 1.0
## The projectile is removed after this long without hitting anything.
@export_range(0.1, 10.0, 0.1, "suffix:s") var max_lifetime: float = 3.0

@export_group("Air drag")
## Quadratic drag: deceleration = 0.5 * air density * Cd * area / mass * v².
## Cd is held constant (no Mach dependence). 0 turns drag off.
@export_range(0.0, 1.0, 0.001) var drag_coefficient: float = 0.0
@export_range(0.1, 100.0, 0.01, "suffix:g") var mass_grams: float = 4.0
@export_range(1.0, 20.0, 0.01, "suffix:mm") var diameter_mm: float = 5.7


## Drag factor k in 1/m, so drag deceleration is k * |v| * v.
func drag_factor(air_density: float) -> float:
	if drag_coefficient <= 0.0 or mass_grams <= 0.0:
		return 0.0
	var radius: float = diameter_mm * 0.0005
	var area: float = PI * radius * radius
	return 0.5 * air_density * drag_coefficient * area / (mass_grams * 0.001)
