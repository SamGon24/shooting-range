class_name StatComparison
extends RefCounted
## Numeric comparisons use the same cached snapshots as gameplay.
const REFERENCE_FOV: float = 65.0
const FIELDS: Array[Array] = [
	["projectile.damage", "Damage", "", false],
	["projectile.muzzle_velocity", "Velocity", "m/s", false],
	["rounds_per_minute", "Cyclic rate", "rpm", false],
	["shot_interval", "Shot interval", "s", true],
	["magazine_size", "Capacity", "", false],
	["ads_time", "ADS time", "s", true],
	["reload_tactical_time", "Tactical reload", "s", true],
	["reload_empty_time", "Empty reload", "s", true],
	["full_reload", "Full empty reload", "s", true],
	["projectile.falloff_start_distance", "Falloff starts", "m", false],
	["projectile.falloff_end_distance", "Falloff ends", "m", false],
	["projectile.min_damage_fraction", "Minimum damage", "%", false],
	["recoil_scale", "Recoil scale", "%", true],
	["aimed_recoil_scale", "Aimed recoil", "%", true],
	["hip_spread_degrees", "Hip cone", "°", true],
	["aimed_spread_degrees", "Aimed cone", "°", true],
	["spread_per_shot_degrees", "Bloom / shot", "°", true],
	["max_bloom_degrees", "Maximum bloom", "°", true],
	["recoil_recovery_rate", "Recoil recovery", "°/s", false],
	["raise_time", "Equip time", "s", true],
	["lower_time", "Holster time", "s", true],
	["sprint_to_fire_time", "Sprint recovery", "s", true],
	["magnification", "Optic zoom", "×", false],
	["ads_sensitivity_scale", "ADS sensitivity", "%", false],
	["sight_height_m", "Sight height", "m", false],
]


static func rows(base: WeaponData, fitted: WeaponData) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var kind: DeliveryData.Kind = base.delivery.kind
	if kind == DeliveryData.Kind.MELEE:
		result.append(_row("Damage", base.projectile.damage, fitted.projectile.damage, "", false))
		result.append(_row("Reach", base.delivery.contact.reach_m, fitted.delivery.contact.reach_m, "m", false))
		result.append(_row("Attack interval", base.shot_interval(), fitted.shot_interval(), "s", true))
		result.append(_row("Movement speed", base.movement_speed_scale * 100.0, fitted.movement_speed_scale * 100.0, "%", false))
		return result
	if kind == DeliveryData.Kind.EXPLOSIVE:
		result.append(_row("Blast damage", base.projectile.explosion.damage, fitted.projectile.explosion.damage, "", false))
		result.append(_row("Blast radius", base.projectile.explosion.radius_m, fitted.projectile.explosion.radius_m, "m", false))
		result.append(_row("Arming distance", base.projectile.explosion.arming_distance_m, fitted.projectile.explosion.arming_distance_m, "m", false))
	if kind == DeliveryData.Kind.PELLET:
		result.append(_row("Pellets / shot", base.delivery.pellet_count, fitted.delivery.pellet_count, "", false))
		result.append(_row("Pellet cone", base.delivery.pellet_spread_degrees, fitted.delivery.pellet_spread_degrees, "°", true))
	for field: Array in FIELDS:
		var key: String = field[0]
		var label: String = field[1]
		if kind == DeliveryData.Kind.EXPLOSIVE and (key == "projectile.damage" or key.begins_with("projectile.falloff") or key == "projectile.min_damage_fraction"):
			continue
		var shells: bool = base.reload_policy.kind == ReloadData.Kind.SHELL
		if key == "full_reload" and not shells:
			continue
		if shells and key == "reload_tactical_time":
			label = "Shell insert"
		elif shells and key == "reload_empty_time":
			label = "First empty insert"
		elif kind == DeliveryData.Kind.PELLET and key == "projectile.damage":
			label = "Damage / pellet"
		result.append(_row(label, value(base, key), value(fitted, key), field[2], field[3]))
	return result


static func value(data: WeaponData, key: String) -> float:
	match key:
		"shot_interval": return data.shot_interval()
		"full_reload": return data.reload_policy.shell_start_time + data.reload_empty_time + float(data.magazine_size - 1) * data.reload_tactical_time + data.reload_policy.shell_end_time
		"magnification": return tan(deg_to_rad(REFERENCE_FOV * 0.5)) / tan(deg_to_rad(data.ads_fov_degrees * 0.5))
	var number: float = float(data.projectile.get(key.trim_prefix("projectile."))) if key.begins_with("projectile.") else float(data.get(key))
	return number * 100.0 if key in ["projectile.min_damage_fraction", "recoil_scale", "aimed_recoil_scale", "ads_sensitivity_scale"] else number


static func _row(label: String, base: float, fitted: float, unit: String, lower_better: bool) -> Dictionary:
	return {"label": label, "base": base, "fitted": fitted, "delta": fitted - base, "unit": unit, "lower_better": lower_better}


static func format_value(number: float, unit: String, signed: bool = false) -> String:
	var prefix: String = "+" if signed and number > 0.00001 else ""
	return prefix + ("%.2f" % number).trim_suffix("0").trim_suffix(".0") + (" " + unit if not unit.is_empty() else "")
