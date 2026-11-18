class_name ProjectileHit
extends RefCounted
## What a projectile reports when it hits something.

var source: DamageSource.Kind = DamageSource.Kind.BALLISTIC
## Unique trigger event; all pellets in a volley share it, unlike pool slots.
var shot_id: int = -1
## Contact delivery can supply an impulse without inventing bullet speed.
var impulse_override: Vector3 = Vector3.ZERO

## World position of the impact.
var position: Vector3
## Surface normal at the impact, pointing away from the surface.
var normal: Vector3
## The physics object that was hit.
var collider: Object
## Projectile velocity at the moment of impact, m/s.
var velocity: Vector3
## Seconds between firing and impact, to the nearest physics tick.
var travel_time: float
## Path length flown, metres.
var travel_distance: float
## What was fired.
var spec: ProjectileSpec
## Damage after falloff over `travel_distance`. Targets apply their own
## hit-zone multipliers and armor on top.
var damage: float
## Pool slot the projectile flew in, matching `projectile_fired`.
var slot: int = -1


func momentum() -> Vector3:
	if not impulse_override.is_zero_approx():
		return impulse_override
	return velocity * (spec.mass_grams * 0.001) if spec != null else Vector3.ZERO
