class_name DeliveryData
extends Resource
## Ballistic and pellet delivery share the existing pooled projectile sweep.

enum Kind { BALLISTIC, PELLET, EXPLOSIVE, MELEE }
@export var kind: Kind = Kind.BALLISTIC
@export_range(1, 32) var pellet_count: int = 8
@export_range(0.0, 15.0, 0.05, "suffix:°") var pellet_spread_degrees: float = 3.0


func is_supported() -> bool:
	return kind in [Kind.BALLISTIC, Kind.PELLET, Kind.EXPLOSIVE]


func launch(system: ProjectileSystem, origin: Vector3, direction: Vector3, spec: ProjectileSpec, rng: RandomNumberGenerator = null) -> int:
	assert(is_supported(), "Delivery is reserved for a later weapon milestone")
	if kind == Kind.BALLISTIC:
		return system.fire(origin, direction, spec)
	if kind == Kind.EXPLOSIVE:
		assert(spec.explosion != null, "Explosive delivery needs explosion tuning")
		return system.fire(origin, direction, spec)
	assert(rng != null, "Pellet delivery requires the weapon's seeded RNG")
	var directions := PackedVector3Array()
	for index: int in pellet_count:
		directions.append(ConeSpread.sample(direction, pellet_spread_degrees, rng))
	return system.fire_volley(origin, directions, spec)
