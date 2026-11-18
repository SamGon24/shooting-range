class_name DebugPose
extends Node
## Command-line helpers for Movie Maker captures. Does nothing without its
## arguments.
##
## `--pose=x,y,z,yaw_deg,pitch_deg` places the player. Position is in metres;
## yaw 0 looks downrange (-Z), 180 looks back at the movement test area.
##
## `--hold=action[@seconds[-release]],...` presses input actions and keeps
## them down, each from the given time after start (default 0) until the
## optional release time. For example, switch to the second weapon, aim after
## 1.5 s, and fire from 2.5 s to 3 s:
##
##   godot --path . --write-movie /tmp/frames/frame.png --quit-after 240 \
##       -- --pose=0,0,0,0,-1 --hold=weapon_2,aim@1.5,fire@2.5-3
##
## A held action is pressed again if the engine lets go of it, as it does
## when an unfocused capture window loses focus.

const POSE_PREFIX: String = "--pose="
const HOLD_PREFIX: String = "--hold="
const PLAYER_GROUP: StringName = &"player"

var _elapsed: float = 0.0
## Actions not yet released: [action, press seconds, release seconds or
## INF] triples.
var _pending_holds: Array[Array] = []


func _ready() -> void:
	# Press actions at the very start of a physics tick, so gameplay code
	# sees "just pressed" on that same tick.
	process_physics_priority = -1000
	set_physics_process(false)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(POSE_PREFIX):
			_apply_pose.call_deferred(argument.trim_prefix(POSE_PREFIX))
		elif argument.begins_with(HOLD_PREFIX):
			_parse_holds(argument.trim_prefix(HOLD_PREFIX))
	if not _pending_holds.is_empty():
		set_physics_process(true)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	for index: int in range(_pending_holds.size() - 1, -1, -1):
		var action: StringName = _pending_holds[index][0]
		var at_seconds: float = _pending_holds[index][1]
		var release_seconds: float = _pending_holds[index][2]
		if _elapsed >= release_seconds:
			Input.action_release(action)
			_pending_holds.remove_at(index)
		elif _elapsed >= at_seconds and not Input.is_action_pressed(action):
			Input.action_press(action)
	if _pending_holds.is_empty():
		set_physics_process(false)


func _parse_holds(value: String) -> void:
	for entry: String in value.split(",", false):
		var parts: PackedStringArray = entry.split("@")
		var action := StringName(parts[0])
		if not InputMap.has_action(action):
			push_warning("DebugPose: unknown action '%s' in --hold" % action)
			continue
		var times: PackedStringArray = parts[1].split("-") if parts.size() > 1 else PackedStringArray(["0"])
		var at_seconds: float = times[0].to_float()
		var release_seconds: float = times[1].to_float() if times.size() > 1 else INF
		_pending_holds.append([action, at_seconds, release_seconds])


func _apply_pose(value: String) -> void:
	var parts: PackedFloat64Array = value.split_floats(",")
	if parts.size() != 5:
		push_warning("DebugPose: expected --pose=x,y,z,yaw_deg,pitch_deg, got '%s'" % value)
		return
	var player := get_tree().get_first_node_in_group(PLAYER_GROUP) as PlayerController
	if player == null:
		push_warning("DebugPose: no node in group '%s'" % PLAYER_GROUP)
		return
	player.teleport(Vector3(parts[0], parts[1], parts[2]), deg_to_rad(parts[3]))
	player.pitch = deg_to_rad(parts[4])
