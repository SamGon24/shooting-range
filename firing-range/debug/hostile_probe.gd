class_name HostileProbe
extends Node
## Debug stand-in for enemy fire until bots exist. The `debug_incoming_fire`
## key (K) fires one real rifle round at the player's torso from a random
## bearing. It flies with `ProjectileSystem.HOSTILE_MASK`, so riot shields,
## cover and the player's hit zones all behave as they will against bots, and
## it never counts in range stats. `-- --incoming-fire` repeats it every
## `auto_interval_seconds` for captures and the perf probe; adding
## `--vulnerable` turns range invulnerability off for that run only, and
## `--incoming-interval=SECONDS` changes the repeat.

const WEAPON: WeaponData = preload("res://weapons/data/halberd_rifle.tres")

@export_range(5.0, 100.0, 1.0, "suffix:m") var distance_m: float = 20.0
@export_range(0.1, 10.0, 0.1, "suffix:s") var auto_interval_seconds: float = 1.0

var _round: ProjectileSpec
var _system: ProjectileSystem
var _health: PlayerHealth
var _rng := RandomNumberGenerator.new()
var _requested: bool = false
var _auto: bool = false
var _auto_elapsed: float = 0.0


func _ready() -> void:
	process_physics_priority = -15
	_round = WEAPON.projectile.duplicate() as ProjectileSpec
	_round.stats_eligible = false
	_auto = OS.get_cmdline_user_args().has("--incoming-fire")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--incoming-interval="):
			auto_interval_seconds = maxf(argument.get_slice("=", 1).to_float(), 0.05)
	_rng.seed = 1515
	_bind.call_deferred()


func _bind() -> void:
	_system = get_tree().get_first_node_in_group(ProjectileSystem.GROUP) as ProjectileSystem
	_health = get_tree().get_first_node_in_group(PlayerHealth.GROUP) as PlayerHealth
	if _health != null and OS.get_cmdline_user_args().has("--vulnerable"):
		_health.follow_range_setting = false
		_health.invulnerable = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_echo() and event.is_action_pressed("debug_incoming_fire"):
		_requested = true


func _physics_process(delta: float) -> void:
	var fire: bool = _requested or Input.is_action_just_pressed("debug_incoming_fire")
	_requested = false
	if _auto:
		_auto_elapsed += delta
		if _auto_elapsed >= auto_interval_seconds:
			_auto_elapsed -= auto_interval_seconds
			fire = true
	if fire:
		fire_once(_rng.randf_range(-PI, PI))


## Fires one round at the torso from `bearing` radians around the player
## (0 is the player's -Z). Returns the pool slot, or -1.
func fire_once(bearing: float) -> int:
	if _system == null or _health == null or _health.is_dead():
		return -1
	var target: Vector3 = _health.get_torso_zone().global_position
	var origin: Vector3 = target + Vector3(-sin(bearing), 0.0, -cos(bearing)) * distance_m
	return _system.fire(origin, target - origin, _round, ProjectileSystem.HOSTILE_MASK)
