class_name GuardProbe
extends Node
## A non-scoring incoming round makes shield blocking testable in the range.
const ROUND: ProjectileSpec = preload("res://debug/data/guard_probe_round.tres")
@export_range(1.0, 50.0, 1.0, "suffix:m") var distance_m: float = 15.0
var _weapons: WeaponController
var _system: ProjectileSystem
var _requested: bool = false


func _ready() -> void:
	process_physics_priority = -15
	_bind.call_deferred()


func _bind() -> void:
	_weapons = get_tree().get_first_node_in_group(WeaponController.GROUP) as WeaponController
	_system = get_tree().get_first_node_in_group(ProjectileSystem.GROUP) as ProjectileSystem


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_echo() and event.is_action_pressed("shield_test_fire"):
		_requested = true


func _physics_process(_delta: float) -> void:
	if not _requested and not Input.is_action_just_pressed("shield_test_fire"):
		return
	_requested = false
	if _weapons == null or _system == null or _weapons.get_current_data().guard == null:
		return
	if _weapons.get_current_logic().state not in [WeaponLogic.State.READY, WeaponLogic.State.FIRING]:
		return
	var player: PlayerController = _weapons.player
	var aim: Basis = player.get_aim_basis()
	_system.fire(player.get_eye_position() - aim.z * distance_m, aim.z, ROUND)
