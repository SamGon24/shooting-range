class_name ReloadData
extends Resource

enum Kind { MAGAZINE, SHELL, SINGLE_ROUND, NONE }
@export var kind: Kind = Kind.MAGAZINE
@export_range(0.0, 2.0, 0.01, "suffix:s") var shell_start_time: float = 0.2
@export_range(0.0, 2.0, 0.01, "suffix:s") var shell_end_time: float = 0.2


func is_supported() -> bool:
	return true


func can_reload(ammo: int, capacity: int) -> bool:
	return kind != Kind.NONE and ammo < capacity


func refill(ammo: int, capacity: int) -> int:
	return mini(ammo + 1, capacity) if kind in [Kind.SINGLE_ROUND, Kind.SHELL] else capacity
