class_name RangeFeedback
extends Node
## Observes target signals; never applies damage or performs hit detection.

signal feedback(kind: HitFeedback.Kind, point: Vector3, amount: float, headshot: bool)
signal stats_changed

const GROUP: StringName = &"range_feedback"

var stats: RangeStats = RangeStats.new()
var _clock: float = 0.0
## Slots launched since the latest stats reset; also deduplicates reports.
var _eligible_slots: Dictionary[int, bool] = {}


func _ready() -> void:
	add_to_group(GROUP)
	get_tree().node_added.connect(_on_node_added)
	_bind_from_tree.call_deferred()


func _physics_process(delta: float) -> void:
	_clock += delta


func reset_stats() -> void:
	stats.reset()
	_eligible_slots.clear()
	stats_changed.emit()


func _bind_from_tree() -> void:
	var system := get_tree().get_first_node_in_group(ProjectileSystem.GROUP) as ProjectileSystem
	if system != null and not system.projectile_fired.is_connected(_on_fired):
		system.projectile_fired.connect(_on_fired)
		system.projectile_expired.connect(_on_expired)
	for group: StringName in [&"target_dummy", &"steel_plate"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			_bind_target(node)


func _on_node_added(node: Node) -> void:
	if node is TargetDummy or node is SteelPlate:
		_bind_target.call_deferred(node)


func _bind_target(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	if node is TargetDummy:
		var dummy := node as TargetDummy
		var callback: Callable = _on_dummy_damaged.bind(dummy)
		if not dummy.damaged.is_connected(callback):
			dummy.damaged.connect(callback)
			dummy.restored.connect(stats.end_life.bind(dummy.get_instance_id()))
	elif node is SteelPlate:
		var plate := node as SteelPlate
		var callback: Callable = _on_steel_rang.bind(plate)
		if not plate.rang.is_connected(callback):
			plate.rang.connect(callback)


func _on_fired(slot: int, _origin: Vector3, _velocity: Vector3, _spec: ProjectileSpec) -> void:
	_eligible_slots[slot] = true
	stats.record_shot()
	stats_changed.emit()


func _on_expired(slot: int) -> void:
	_eligible_slots.erase(slot)


func _on_dummy_damaged(hit: ProjectileHit, zone: TargetSettings.Zone, amount: float, dummy: TargetDummy) -> void:
	var headshot: bool = zone == TargetSettings.Zone.HEAD
	var kind: HitFeedback.Kind = HitFeedback.pick(dummy.last_plate_breaks, dummy.state.dead)
	if _eligible_slots.has(hit.slot):
		_eligible_slots.erase(hit.slot)
		stats.record_hit(dummy.get_instance_id(), headshot, dummy.state.dead, _clock)
		stats_changed.emit()
	feedback.emit(kind, hit.position, amount, headshot)


func _on_steel_rang(plate: SteelPlate) -> void:
	var hit: ProjectileHit = plate.last_hit
	if _eligible_slots.has(hit.slot):
		_eligible_slots.erase(hit.slot)
		stats.record_hit(plate.get_instance_id(), false, false, _clock, false)
		stats_changed.emit()
	feedback.emit(HitFeedback.Kind.HIT, hit.position, 0.0, false)
