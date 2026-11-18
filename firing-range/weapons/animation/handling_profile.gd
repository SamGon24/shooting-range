class_name HandlingProfile
extends Resource
## The procedural handling animation for a family of weapons: a list of
## cosmetic tracks plus which viewmodel parts are normally hidden. Profiles
## live in `weapons/animation/data/` and a weapon picks one through
## `WeaponData.handling`. Nothing here feeds back into gameplay.

@export var tracks: Array[HandlingTrack] = []
## Hidden unless a SHOW track window is open (a shell on its way in).
@export var staged_parts: Array[StringName] = []
## Hidden while the weapon holds no ammo, unless a SHOW window is open (a
## rocket in the tube, an LMG belt in the feed tray).
@export var empty_hidden_parts: Array[StringName] = []

var _by_event: Dictionary[int, Array] = {}


func tracks_for(event: HandlingTrack.Event) -> Array:
	if _by_event.is_empty():
		for track: HandlingTrack in tracks:
			if not _by_event.has(track.event):
				_by_event[track.event] = []
			_by_event[track.event].append(track)
	return _by_event.get(event, [])


func has_event(event: HandlingTrack.Event) -> bool:
	return not tracks_for(event).is_empty()


## Every node path this profile moves or hides, in a stable order. The empty
## name stands for the whole model.
func get_parts() -> Array[StringName]:
	var parts: Array[StringName] = []
	for track: HandlingTrack in tracks:
		if not parts.has(track.part):
			parts.append(track.part)
	for part: StringName in staged_parts + empty_hidden_parts:
		if not parts.has(part):
			parts.append(part)
	return parts


func is_valid() -> bool:
	for track: HandlingTrack in tracks:
		if track == null or not track.is_valid():
			return false
	return true
