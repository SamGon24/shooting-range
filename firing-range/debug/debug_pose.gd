class_name DebugPose
extends Node
## Places the player at a fixed pose from the command line, for Movie Maker
## screenshots of a specific view:
##
##   godot --path . --write-movie /tmp/frames/frame.png --quit-after 60 \
##       -- --pose=0,0,12,180,-5
##
## The values are x, y, z in metres, then yaw and pitch in degrees. Yaw 0
## looks downrange (-Z); 180 looks back at the movement test area.
## Does nothing without the `--pose=` argument.

const PREFIX: String = "--pose="
const PLAYER_GROUP: StringName = &"player"


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(PREFIX):
			_apply.call_deferred(argument.trim_prefix(PREFIX))
			return


func _apply(value: String) -> void:
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
