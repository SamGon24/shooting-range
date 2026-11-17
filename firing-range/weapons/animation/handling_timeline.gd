class_name HandlingTimeline
extends RefCounted
## Turns gameplay state into handling-animation state. Pure functions.
##
## There is no animation clock. Which events are running, and how far
## through each, are read from `WeaponLogic` every frame:
##
## - reloads from `get_reload_progress()` and `reload_phase`
## - action cycles and melee swings from `get_time_to_next_shot()`
## - raise and lower from the raise progress
##
## So pausing freezes the animation, an attachment that changes a reload time
## changes the animation by the same factor, and a cancelled or interrupted
## reload snaps the pose to whatever the logic now says (usually rest).


## Fills `events` (HandlingTrack.Event -> progress 0..1) for the logic's
## current state. `raise_blend` is the render-interpolated raise progress.
static func collect(logic: WeaponLogic, raise_blend: float, events: Dictionary) -> void:
	events.clear()
	if logic.is_reloading():
		events[reload_event(logic)] = logic.get_reload_progress()
	var interval: float = logic.data.shot_interval()
	var cycle_left: float = logic.get_time_to_next_shot()
	if cycle_left > WeaponLogic.TIME_EPSILON and interval > 0.0:
		events[HandlingTrack.Event.CYCLE] = clampf(1.0 - cycle_left / interval, 0.0, 1.0)
	if raise_blend < 1.0:
		events[HandlingTrack.Event.LOWERED] = clampf(1.0 - raise_blend, 0.0, 1.0)
	if logic.data.uses_ammo and logic.ammo <= 0 and not logic.is_reloading() and not events.has(HandlingTrack.Event.CYCLE):
		events[HandlingTrack.Event.EMPTY_HOLD] = 1.0


## The reload event the logic is in. Only meaningful while reloading.
static func reload_event(logic: WeaponLogic) -> HandlingTrack.Event:
	match logic.reload_phase:
		WeaponLogic.ReloadPhase.START:
			return HandlingTrack.Event.SHELL_START
		WeaponLogic.ReloadPhase.INSERT:
			return HandlingTrack.Event.SHELL_INSERT
		WeaponLogic.ReloadPhase.FINISH:
			return HandlingTrack.Event.SHELL_FINISH
	return HandlingTrack.Event.RELOAD_EMPTY if logic.is_reload_empty() else HandlingTrack.Event.RELOAD_TACTICAL


## The Resource time an event spans for `data`. `ammo` is the loaded count
## when the event starts (it picks empty versus tactical insert times), and
## `raising` picks raise versus lower time. Documentation and tests use this
## to check animations against the weapon's Resource timings.
static func event_duration(data: WeaponData, event: HandlingTrack.Event, ammo: int = 1, raising: bool = true) -> float:
	match event:
		HandlingTrack.Event.RELOAD_TACTICAL:
			return data.reload_tactical_time
		HandlingTrack.Event.RELOAD_EMPTY:
			return data.reload_empty_time
		HandlingTrack.Event.SHELL_START:
			return data.reload_policy.shell_start_time
		HandlingTrack.Event.SHELL_INSERT:
			return data.reload_time(ammo)
		HandlingTrack.Event.SHELL_FINISH:
			return data.reload_policy.shell_end_time
		HandlingTrack.Event.CYCLE:
			return data.shot_interval()
		HandlingTrack.Event.LOWERED:
			return data.raise_time if raising else data.lower_time
	return 0.0


## Samples `profile` at `events` into `pose`. `empty` hides the profile's
## empty-hidden parts.
static func evaluate(profile: HandlingProfile, events: Dictionary, empty: bool, pose: HandlingPose) -> void:
	pose.clear()
	if profile == null:
		return
	var shown: Dictionary[StringName, bool] = pose.shown_scratch
	var forced_hidden: Dictionary[StringName, bool] = pose.hidden_scratch
	for event: int in events:
		var progress: float = events[event]
		for track: HandlingTrack in profile.tracks_for(event):
			var weight: float = track.weight(progress)
			if weight > 0.0:
				pose.offsets[track.part] = pose.offset(track.part) + track.offset * weight
				pose.rotations[track.part] = pose.rotation(track.part) + track.rotation_degrees * (weight * PI / 180.0)
			if track.in_window(progress):
				if track.visibility == HandlingTrack.Visibility.HIDE:
					forced_hidden[track.part] = true
				else:
					shown[track.part] = true
	for part: StringName in profile.staged_parts:
		if not shown.has(part):
			pose.hidden[part] = true
	if empty:
		for part: StringName in profile.empty_hidden_parts:
			if not shown.has(part):
				pose.hidden[part] = true
	for part: StringName in forced_hidden:
		pose.hidden[part] = true


## Tracks whose copy-release point lies in (from, to] for `event`. A release
## fires once, on the frame its window opens.
static func releases_between(profile: HandlingProfile, event: HandlingTrack.Event, from: float, to: float) -> Array[HandlingTrack]:
	var released: Array[HandlingTrack] = []
	if profile == null:
		return released
	for track: HandlingTrack in profile.tracks_for(event):
		if track.releases_copy and from < track.window_start and track.window_start <= to:
			released.append(track)
	return released
