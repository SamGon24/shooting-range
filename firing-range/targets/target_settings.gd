class_name TargetSettings
extends Resource
## Shared dummy tuning. Distances and dimensions use metres, times seconds.

@export var max_health: float = 100.0
@export var plate_health: float = 50.0
@export_range(0, 3) var armor_plates: int = 0
@export var reset_seconds: float = 3.0
@export var pop_seconds: float = 0.15
@export var head_multiplier: float = 1.5
@export var sniper_head_multiplier: float = 2.0
@export var torso_multiplier: float = 1.0
@export var limb_multiplier: float = 0.8


func multiplier(zone: TargetHitZone.Zone, spec: ProjectileSpec) -> float:
	match zone:
		TargetHitZone.Zone.HEAD:
			return sniper_head_multiplier if spec.weapon_class == ProjectileSpec.WeaponClass.SNIPER else head_multiplier
		TargetHitZone.Zone.LIMB:
			return limb_multiplier
	return torso_multiplier
