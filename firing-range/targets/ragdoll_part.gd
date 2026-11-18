class_name RagdollPart
extends RigidBody3D
## One rigid part of a dummy's corpse. Bullets stop on it and push it.
##
## A corpse is cosmetic: it takes no damage, never changes health, armor or
## the range statistics, and feeds no hit feedback. A shot that strikes one
## is still a miss. The part only turns the projectile's momentum into a
## shove at the point of impact, like a prop.

var ragdoll: DummyRagdoll


func receive_hit(hit: ProjectileHit) -> void:
	if ragdoll == null or not ragdoll.active:
		return
	apply_impulse(hit.momentum() * ragdoll.impulse_scale, hit.position - global_position)
