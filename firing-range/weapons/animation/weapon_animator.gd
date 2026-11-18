class_name WeaponAnimator
extends RefCounted
## Applies handling profiles to the greybox viewmodels. Cosmetic only.
##
## Every frame, the current weapon's pose is sampled from its `WeaponLogic`
## through `HandlingTimeline` and written onto the model's named parts on
## top of their rest transforms. Nothing is accumulated between frames, so a
## cancelled reload or a switch away leaves no stale offsets behind.
##
## Parts are hidden by scaling them down rather than with `visible`: under
## the camera rig, toggling `visible` stops the renderer receiving later
## transform changes (see `WeaponView._set_model_shown`).

## Emitted the frame a releasing track opens its hide window, before the
## part is hidden. `follower` is the attachment mount that moves with it,
## or null.
signal copy_released(part: Node3D, follower: Node3D)

const HIDDEN_SCALE: Vector3 = Vector3(0.0001, 0.0001, 0.0001)
const MOUNTS_PREFIX: String = "Mounts/"


class Rig:
	extends RefCounted
	var profile: HandlingProfile
	var model: Node3D
	var nodes: Dictionary[StringName, Node3D] = {}
	var rests: Dictionary[StringName, Transform3D] = {}
	var followers: Dictionary[StringName, Node3D] = {}
	var follower_rests: Dictionary[StringName, Transform3D] = {}


var _rigs: Dictionary[WeaponData, Rig] = {}
var _events: Dictionary = {}
var _previous: Dictionary = {}
var _previous_rig: Rig
var _pose: HandlingPose = HandlingPose.new()


## Records the rest pose of every part `definition.handling` moves.
func bind(definition: WeaponData, model: Node3D) -> void:
	var rig := Rig.new()
	rig.profile = definition.handling
	rig.model = model
	_rigs[definition] = rig
	if rig.profile == null:
		return
	if not rig.profile.is_valid():
		push_warning("WeaponAnimator: %s has an invalid handling profile." % definition.display_name)
		rig.profile = null
		return
	for part: StringName in rig.profile.get_parts():
		var node: Node3D = model if part.is_empty() else model.get_node_or_null(NodePath(part)) as Node3D
		if node == null:
			push_warning("WeaponAnimator: %s has no part '%s'." % [definition.display_name, part])
			continue
		rig.nodes[part] = node
		rig.rests[part] = node.transform
		if part.is_empty():
			continue
		var follower: Node3D = model.get_node_or_null(NodePath(MOUNTS_PREFIX + String(part))) as Node3D
		if follower != null:
			rig.followers[part] = follower
			rig.follower_rests[part] = follower.transform


## Poses `definition`'s model for `logic` at the given raise blend.
func apply(definition: WeaponData, logic: WeaponLogic, raise_blend: float) -> void:
	var rig: Rig = _rigs.get(definition)
	if rig == null or rig.profile == null:
		return
	HandlingTimeline.collect(logic, raise_blend, _events)
	if rig != _previous_rig:
		_previous.clear()
		_previous_rig = rig
	for event: int in _events:
		var progress: float = _events[event]
		var from: float = _previous.get(event, -1.0)
		if from > progress:
			from = -1.0
		for track: HandlingTrack in HandlingTimeline.releases_between(rig.profile, event, from, progress):
			var part: Node3D = rig.nodes.get(track.part)
			if part != null:
				copy_released.emit(part, rig.followers.get(track.part))
	_previous.clear()
	_previous.merge(_events)

	HandlingTimeline.evaluate(rig.profile, _events, logic.data.uses_ammo and logic.ammo <= 0, _pose)
	for part: StringName in rig.nodes:
		var node: Node3D = rig.nodes[part]
		node.transform = _pose.apply_to(part, rig.rests[part], HIDDEN_SCALE)
		if rig.followers.has(part):
			rig.followers[part].transform = node.transform * rig.rests[part].affine_inverse() * rig.follower_rests[part]


## Puts every animated part of `definition`'s model back at rest.
func reset(definition: WeaponData) -> void:
	var rig: Rig = _rigs.get(definition)
	if rig == null:
		return
	for part: StringName in rig.nodes:
		rig.nodes[part].transform = rig.rests[part]
	for part: StringName in rig.followers:
		rig.followers[part].transform = rig.follower_rests[part]
	if rig == _previous_rig:
		_previous.clear()


## Rest transform recorded for a part, for tests and debugging.
func get_rest(definition: WeaponData, part: StringName) -> Transform3D:
	var rig: Rig = _rigs.get(definition)
	return rig.rests.get(part, Transform3D.IDENTITY) if rig != null else Transform3D.IDENTITY


func get_pose() -> HandlingPose:
	return _pose
