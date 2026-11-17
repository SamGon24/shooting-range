class_name ProjectileSpec
extends Resource
## What a weapon fires. Units are SI except where the suffix says otherwise
## (grams and millimetres read more naturally for bullets).

@export var source: DamageSource.Kind = DamageSource.Kind.BALLISTIC

enum WeaponClass { DEFAULT, SNIPER }

## Selects target multiplier rules independently of projectile damage.
@export var weapon_class: WeaponClass = WeaponClass.DEFAULT

## Speed leaving the barrel, m/s.
@export_range(50.0, 1500.0, 1.0, "suffix:m/s") var muzzle_velocity: float = 850.0
## Multiplies world gravity for this projectile. 1 is real gravity.
@export_range(0.0, 2.0, 0.01) var gravity_scale: float = 1.0
## The projectile is removed after this long without hitting anything.
@export_range(0.1, 10.0, 0.1, "suffix:s") var max_lifetime: float = 3.0

@export_group("Damage")
## Damage at the muzzle and out to `falloff_start_distance`.
@export_range(0.0, 500.0, 0.5) var damage: float = 30.0
## Damage starts falling off past this distance, metres.
@export_range(0.0, 1000.0, 1.0, "suffix:m") var falloff_start_distance: float = 50.0
## Damage reaches its minimum at this distance and stays there.
@export_range(0.0, 1000.0, 1.0, "suffix:m") var falloff_end_distance: float = 150.0
## Damage beyond `falloff_end_distance`, as a fraction of `damage`.
@export_range(0.0, 1.0, 0.01) var min_damage_fraction: float = 1.0

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


## Damage after flying `distance` metres: full up to the falloff start, then
## linear down to `min_damage_fraction` at the falloff end.
func damage_at_distance(distance: float) -> float:
	if distance <= falloff_start_distance:
		return damage
	if distance >= falloff_end_distance or falloff_end_distance <= falloff_start_distance:
		return damage * min_damage_fraction
	var t: float = (distance - falloff_start_distance) / (falloff_end_distance - falloff_start_distance)
	return damage * lerpf(1.0, min_damage_fraction, t)
