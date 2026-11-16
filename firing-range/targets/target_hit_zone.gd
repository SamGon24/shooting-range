class_name TargetHitZone
extends AnimatableBody3D
## A solid zone for the existing projectile sweep; no independent detection.

const Zone = TargetSettings.Zone

var zone: TargetSettings.Zone = Zone.TORSO
var dummy: TargetDummy


func receive_hit(hit: ProjectileHit) -> void:
	dummy.receive_hit(hit, zone)
