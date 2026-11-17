class_name DeliveryData
extends Resource
## Non-ballistic runtime implementations arrive with their weapon milestones.

enum Kind { BALLISTIC, PELLET, EXPLOSIVE, MELEE }
@export var kind: Kind = Kind.BALLISTIC


func is_supported() -> bool:
	return kind == Kind.BALLISTIC


func launch(system: ProjectileSystem, origin: Vector3, direction: Vector3, spec: ProjectileSpec) -> int:
	assert(is_supported(), "Delivery is reserved for a later weapon milestone")
	return system.fire(origin, direction, spec)
