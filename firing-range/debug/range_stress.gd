class_name RangeStress
extends Node
## Opt-in worst-case probe fixture, never active in ordinary play.
## Keeps every dummy down (re-killing through the normal damage entry point
## on restore), all eight props awake and all three steel hinges moving.

var _props: Array[PhysicsProp] = []
var _plates: Array[SteelPlate] = []
var _dummies: Array[TargetDummy] = []
var _spec: ProjectileSpec
var _elapsed: float = 0.0


func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--perf-stress"):
		set_physics_process(false)
		return
	add_to_group(&"range_stress")
	_start.call_deferred()


func _start() -> void:
	var weapon := load("res://weapons/data/longwatch_sniper.tres") as WeaponData
	_spec = weapon.projectile
	for node: Node in get_tree().get_nodes_in_group(&"target_dummy"):
		var dummy := node as TargetDummy
		if OS.get_cmdline_user_args().has("--perf-popdown"):
			dummy.ragdoll_enabled = false
		_dummies.append(dummy)
		dummy.restored.connect(_kill.bind(dummy))
		_kill(dummy)
	for node: Node in get_tree().get_nodes_in_group(&"physics_prop"):
		_props.append(node as PhysicsProp)
	for node: Node in get_tree().get_nodes_in_group(&"steel_plate"):
		_plates.append(node as SteelPlate)


func _kill(dummy: TargetDummy) -> void:
	var hit := ProjectileHit.new()
	hit.spec = _spec
	hit.damage = 400.0
	hit.velocity = Vector3(0, 0, -900)
	hit.collider = dummy.zones[1]
	hit.position = dummy.zones[1].global_position + Vector3(0, 0.1, 0.1)
	dummy.receive_hit(hit, TargetSettings.Zone.TORSO)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	for dummy: TargetDummy in _dummies:
		if dummy.ragdoll.active:
			for part: RigidBody3D in dummy.ragdoll.parts:
				part.sleeping = false
				part.apply_torque_impulse(Vector3(0, 0.005, 0))
	for index: int in _props.size():
		var prop: PhysicsProp = _props[index]
		prop.sleeping = false
		if prop.linear_velocity.length() > 4.0:
			prop.linear_velocity = prop.linear_velocity.normalized() * 4.0
		var direction := Vector3(sin(_elapsed + float(index)), 0, cos(_elapsed + float(index)))
		prop.apply_impulse(direction * prop.mass * delta * 8.0, Vector3.UP * 0.2)
	for plate: SteelPlate in _plates:
		plate.apply_torque_impulse(Vector3.RIGHT * 0.03)


func get_active_part_count() -> int:
	var count: int = 0
	for dummy: TargetDummy in _dummies:
		if dummy.ragdoll.active:
			for part: RigidBody3D in dummy.ragdoll.parts:
				if not part.freeze and not part.sleeping:
					count += 1
	return count


func get_prop_count() -> int:
	return _props.size()
