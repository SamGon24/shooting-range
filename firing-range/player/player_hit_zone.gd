class_name PlayerHitZone
extends AnimatableBody3D
## A solid player zone for hostile projectile sweeps. Only shots fired with
## `ProjectileSystem.HOSTILE_MASK` (and blasts) can reach this layer.

const LAYER: int = 16

var zone: TargetSettings.Zone = TargetSettings.Zone.TORSO
var health: PlayerHealth


func receive_hit(hit: ProjectileHit) -> void:
	health.receive_hit(hit, zone)
