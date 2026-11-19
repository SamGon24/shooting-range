class_name ChallengeScores
extends RefCounted

const PATH := "user://scores.cfg"
var path: String
var _file := ConfigFile.new()
var _load_error: Error

func _init(save_path: String = PATH) -> void:
	path = save_path
	_load_error = _file.load(path)

func best(id: StringName) -> int:
	var value: Variant = _file.get_value("best", id, -1)
	return maxi(value, -1) if value is int else -1

func record(id: StringName, score: int) -> Error:
	if _load_error != OK and _load_error != ERR_FILE_NOT_FOUND:
		return _load_error
	var previous: int = best(id)
	if score <= previous:
		return OK
	_file.set_value("best", id, score)
	var error: Error = _file.save(path)
	if error != OK:
		if previous >= 0:
			_file.set_value("best", id, previous)
		else:
			_file.erase_section_key("best", id)
	return error
