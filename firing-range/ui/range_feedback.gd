class_name RangeFeedback
extends Node
## Observes target signals; never applies damage or performs hit detection.

signal feedback(kind: HitFeedback.Kind, point: Vector3, amount: float, headshot: bool)
signal stats_changed
signal damage_total(shot_id: int, target_id: int, point: Vector3, amount: float, headshot: bool)

const GROUP: StringName = &"range_feedback"

var stats: RangeStats = RangeStats.new()
var _clock: float = 0.0
## Hit/headshot bits per live shot since reset; pool-slot reuse is irrelevant.
var _eligible_shots: Dictionary[int, int] = {}
var _pellet_totals: Dictionary[int, Dictionary] = {}

class TargetTotal extends RefCounted:
	var amount: float = 0.0
	var headshot: bool = false
	var marker: int = -1


func _ready() -> void:
	add_to_group(GROUP)
	get_tree().node_added.connect(_on_node_added)
	_bind_from_tree.call_deferred()


func _physics_process(delta: float) -> void:
	_clock += delta


func reset_stats() -> void:
	stats.reset()
	_eligible_shots.clear()
	stats_changed.emit()


func _bind_from_tree() -> void:
	var system := get_tree().get_first_node_in_group(ProjectileSystem.GROUP) as ProjectileSystem
	if system != null:
		var callback: Callable = _on_shot_started.bind(system)
		if not system.shot_started.is_connected(callback):
			system.shot_started.connect(callback)
			system.shot_finished.connect(_on_shot_finished)
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


func _on_shot_started(shot_id: int, system: ProjectileSystem) -> void:
	if not system.is_scoring_shot(shot_id):
		return
	_eligible_shots[shot_id] = 0
	stats.record_shot()
	stats_changed.emit()


func _on_shot_finished(shot_id: int) -> void:
	_eligible_shots.erase(shot_id)
	_pellet_totals.erase(shot_id)


func _on_dummy_damaged(hit: ProjectileHit, zone: TargetSettings.Zone, amount: float, dummy: TargetDummy) -> void:
	var headshot: bool = zone == TargetSettings.Zone.HEAD
	var kind: HitFeedback.Kind = HitFeedback.pick(dummy.last_plate_breaks, dummy.state.dead)
	_record_hit(hit.shot_id, dummy.get_instance_id(), headshot, dummy.state.dead, true)
	if hit.source == DamageSource.Kind.PELLET:
		if not _pellet_totals.has(hit.shot_id):
			_pellet_totals[hit.shot_id] = {}
		var targets: Dictionary = _pellet_totals[hit.shot_id]
		var target_id: int = dummy.get_instance_id()
		if not targets.has(target_id):
			targets[target_id] = TargetTotal.new()
		var total: TargetTotal = targets[target_id]
		total.amount += amount
		total.headshot = total.headshot or headshot
		damage_total.emit(hit.shot_id, target_id, hit.position, total.amount, total.headshot)
		if kind > total.marker:
			total.marker = kind
			feedback.emit(kind, hit.position, 0.0, total.headshot)
		return
	feedback.emit(kind, hit.position, amount, headshot)


func _on_steel_rang(plate: SteelPlate) -> void:
	var hit: ProjectileHit = plate.last_hit
	_record_hit(hit.shot_id, plate.get_instance_id(), false, false, false)
	feedback.emit(HitFeedback.Kind.HIT, hit.position, 0.0, false)


func _record_hit(shot_id: int, target_id: int, headshot: bool, killed: bool, tracks_life: bool) -> void:
	if not _eligible_shots.has(shot_id):
		return
	var flags: int = _eligible_shots[shot_id]
	if flags == 0:
		stats.record_hit(target_id, headshot, killed, _clock, tracks_life)
	elif tracks_life:
		stats.record_target_damage(target_id, killed, _clock)
	if headshot and flags != 0 and (flags & 2) == 0:
		stats.headshots += 1
	_eligible_shots[shot_id] = flags | 1 | (2 if headshot else 0)
	stats_changed.emit()
