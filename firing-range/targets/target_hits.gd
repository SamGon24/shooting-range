class_name TargetHits
extends Node
## Dispatches the existing ballistics report to the body it already hit.


func _ready() -> void:
	_connect_to_projectiles.call_deferred()


func _connect_to_projectiles() -> void:
	var system := get_tree().get_first_node_in_group(ProjectileSystem.GROUP) as ProjectileSystem
	if system != null:
		system.projectile_hit.connect(_on_hit)


func _on_hit(hit: ProjectileHit) -> void:
	if hit.spec != null and hit.spec.explosion != null and hit.source != DamageSource.Kind.SPLASH:
		var explosions := get_tree().get_first_node_in_group(ExplosionSystem.GROUP) as ExplosionSystem
		if explosions != null:
			explosions.detonate(hit)
		return
	if hit.collider is TargetHitZone:
		(hit.collider as TargetHitZone).receive_hit(hit)
	elif hit.collider is SteelPlate:
		(hit.collider as SteelPlate).receive_hit(hit)
	elif hit.collider is PhysicsProp:
		(hit.collider as PhysicsProp).receive_hit(hit)
