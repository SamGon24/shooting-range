class_name HitLogger
extends Node
## Prints every projectile hit to stdout when the game is started with the
## user argument `--log-hits`. For checking where shots land in automated
## runs:
##
##   godot --path . --quit-after 120 -- --pose=0,0,0,0,-3.85 --hold=fire --log-hits
##
## Does nothing without the argument.

const ARGUMENT: String = "--log-hits"


func _ready() -> void:
	if OS.get_cmdline_user_args().has(ARGUMENT):
		_connect.call_deferred()


func _connect() -> void:
	var system := get_tree().get_first_node_in_group(ProjectileSystem.GROUP) as ProjectileSystem
	if system == null:
		push_warning("HitLogger: no ProjectileSystem in the scene.")
		return
	system.projectile_hit.connect(_on_hit)


func _on_hit(hit: ProjectileHit) -> void:
	var collider_name: String = (hit.collider as Node).name if hit.collider is Node else "?"
	print(
		"HIT %-14s x %7.3f  y %7.3f  downrange %7.2f m  flight %.3f s  speed %.0f m/s  damage %.1f"
		% [
			collider_name,
			hit.position.x,
			hit.position.y,
			-hit.position.z,
			hit.travel_time,
			hit.velocity.length(),
			hit.damage,
		]
	)
