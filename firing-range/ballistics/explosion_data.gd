class_name ExplosionData
extends Resource
## Radial damage / impulse tuning. Distances are measured from impact.

@export_range(0.0, 100.0, 0.1, "suffix:m") var arming_distance_m: float = 10.0
@export_range(0.1, 20.0, 0.1, "suffix:m") var radius_m: float = 6.0
@export_range(0.0, 20.0, 0.1, "suffix:m") var inner_radius_m: float = 1.0
@export_range(0.0, 500.0, 1.0) var damage: float = 180.0
@export_range(0.0, 200.0, 1.0, "suffix:N·s") var impulse_n_s: float = 45.0
@export var occlusion: bool = true
@export_range(0.001, 0.1, 0.001, "suffix:m") var surface_offset_m: float = 0.02


func is_armed(distance_m: float) -> bool:
	return distance_m >= arming_distance_m


func falloff(distance_m: float) -> float:
	if distance_m >= radius_m:
		return 0.0
	if distance_m <= inner_radius_m:
		return 1.0
	return clampf((radius_m - distance_m) / maxf(radius_m - inner_radius_m, 0.0001), 0.0, 1.0)


func damage_at_distance(distance_m: float) -> float:
	return damage * falloff(distance_m)


func impulse_at(displacement: Vector3) -> Vector3:
	var direction: Vector3 = displacement.normalized() if not displacement.is_zero_approx() else Vector3.UP
	return direction * impulse_n_s * falloff(displacement.length())
