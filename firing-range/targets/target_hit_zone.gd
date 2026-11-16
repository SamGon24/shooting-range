class_name TargetHitZone
extends AnimatableBody3D
## A solid zone for the existing projectile sweep; no independent detection.

enum Zone { HEAD, TORSO, LIMB }

var zone: Zone = Zone.TORSO
var dummy: TargetDummy


func receive_hit(hit: ProjectileHit) -> void:
	dummy.receive_hit(hit, zone)
