class_name ReloadData
extends Resource

enum Kind { MAGAZINE, SHELL, SINGLE_ROUND, NONE }
@export var kind: Kind = Kind.MAGAZINE


func is_supported() -> bool:
	return kind != Kind.SHELL


func can_reload(ammo: int, capacity: int) -> bool:
	return kind != Kind.NONE and ammo < capacity


func refill(ammo: int, capacity: int) -> int:
	assert(is_supported(), "Interruptible shell reload arrives in Milestone 8")
	return mini(ammo + 1, capacity) if kind == Kind.SINGLE_ROUND else capacity
