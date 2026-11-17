class_name WeaponLoadout
extends Resource
## Strict primary/secondary contract; comparison mode preserves the MVP pair.
@export var primary: WeaponData
@export var secondary: WeaponData
@export var comparison_mode: bool = false


func is_valid() -> bool:
	if primary == null or secondary == null:
		return false
	return primary.role == WeaponTypes.Role.PRIMARY and primary.weapon_class <= WeaponTypes.Class.SHOTGUN and (comparison_mode or (secondary.role == WeaponTypes.Role.SECONDARY and secondary.weapon_class >= WeaponTypes.Class.PISTOL))


func weapons() -> Array[WeaponData]:
	return [primary, secondary] if is_valid() else []
