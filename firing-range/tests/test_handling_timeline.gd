extends GutTest
## Handling animation timelines: pulse shapes, pose sampling, and event
## timing read straight from WeaponLogic so it always matches the Resources.

const RIFLE: WeaponData = preload("res://weapons/data/halberd_rifle.tres")
const SNIPER: WeaponData = preload("res://weapons/data/longwatch_sniper.tres")
const SHOTGUN: WeaponData = preload("res://weapons/data/breakwater_shotgun.tres")
const PISTOL: WeaponData = preload("res://weapons/data/wayline_pistol.tres")
const KNIFE: WeaponData = preload("res://weapons/data/latch_knife.tres")
const DT: float = 1.0 / 60.0


func _track(event: HandlingTrack.Event, part: StringName, offset: Vector3, times: Array[float]) -> HandlingTrack:
	var track := HandlingTrack.new()
	track.event = event
	track.part = part
	track.offset = offset
	track.out_start = times[0]
	track.out_end = times[1]
	track.back_start = times[2]
	track.back_end = times[3]
	return track


func _ticks(seconds: float) -> int:
	return ceili(seconds / DT - 0.0001)


func test_pulse_rests_eases_out_holds_and_returns() -> void:
	var track: HandlingTrack = _track(HandlingTrack.Event.RELOAD_TACTICAL, &"Magazine", Vector3.DOWN, [0.1, 0.3, 0.6, 0.8])
	assert_true(track.is_valid())
	assert_eq(track.weight(0.0), 0.0)
	assert_eq(track.weight(0.1), 0.0)
	assert_almost_eq(track.weight(0.2), 0.5, 0.0001)
	assert_eq(track.weight(0.3), 1.0)
	assert_eq(track.weight(0.45), 1.0)
	assert_almost_eq(track.weight(0.7), 0.5, 0.0001)
	assert_eq(track.weight(0.8), 0.0)
	assert_eq(track.weight(1.0), 0.0)
	var previous: float = 0.0
	for step: int in 31:
		var weight: float = track.weight(0.3 * float(step) / 30.0)
		assert_gte(weight, previous)
		previous = weight


func test_instant_and_open_ended_pulses() -> void:
	var held: HandlingTrack = _track(HandlingTrack.Event.SHELL_INSERT, &"", Vector3.UP, [0.0, 0.0, 1.0, 1.0])
	assert_eq(held.weight(0.0), 1.0)
	assert_eq(held.weight(1.0), 1.0)
	var leaving: HandlingTrack = _track(HandlingTrack.Event.SHELL_FINISH, &"", Vector3.UP, [0.0, 0.0, 0.0, 1.0])
	assert_eq(leaving.weight(0.0), 1.0)
	assert_almost_eq(leaving.weight(0.5), 0.5, 0.0001)
	assert_eq(leaving.weight(1.0), 0.0)


func test_invalid_orderings_are_rejected() -> void:
	assert_false(_track(HandlingTrack.Event.CYCLE, &"", Vector3.UP, [0.5, 0.4, 0.6, 0.7]).is_valid())
	assert_false(_track(HandlingTrack.Event.CYCLE, &"", Vector3.UP, [0.1, 0.6, 0.5, 0.7]).is_valid())
	var window: HandlingTrack = _track(HandlingTrack.Event.CYCLE, &"", Vector3.UP, [0.0, 0.1, 0.2, 0.3])
	window.visibility = HandlingTrack.Visibility.HIDE
	window.window_start = 0.6
	window.window_end = 0.5
	assert_false(window.is_valid())
	window.window_end = 0.7
	assert_true(window.is_valid())
	window.visibility = HandlingTrack.Visibility.SHOW
	window.releases_copy = true
	assert_false(window.is_valid(), "only a HIDE window can release a copy")


func test_evaluate_sums_tracks_and_resolves_visibility() -> void:
	var profile := HandlingProfile.new()
	var tilt: HandlingTrack = _track(HandlingTrack.Event.RELOAD_EMPTY, &"", Vector3(0.0, -0.1, 0.0), [0.0, 0.2, 0.8, 1.0])
	tilt.rotation_degrees = Vector3(0.0, 0.0, 30.0)
	var mag: HandlingTrack = _track(HandlingTrack.Event.RELOAD_EMPTY, &"Magazine", Vector3(0.0, -0.3, 0.0), [0.1, 0.3, 0.5, 0.7])
	mag.visibility = HandlingTrack.Visibility.HIDE
	mag.window_start = 0.3
	mag.window_end = 0.5
	mag.releases_copy = true
	var shell: HandlingTrack = _track(HandlingTrack.Event.RELOAD_EMPTY, &"Shell", Vector3.ZERO, [0.0, 0.0, 1.0, 1.0])
	shell.visibility = HandlingTrack.Visibility.SHOW
	shell.window_start = 0.6
	var shown_then_hidden: HandlingTrack = _track(HandlingTrack.Event.RELOAD_EMPTY, &"Shell", Vector3.ZERO, [0.0, 0.0, 1.0, 1.0])
	shown_then_hidden.visibility = HandlingTrack.Visibility.HIDE
	shown_then_hidden.window_start = 0.9
	profile.tracks = [tilt, mag, shell, shown_then_hidden]
	profile.staged_parts = [&"Shell"]
	profile.empty_hidden_parts = [&"Rocket"]
	assert_true(profile.is_valid())
	assert_eq(profile.get_parts(), [&"", &"Magazine", &"Shell", &"Rocket"] as Array[StringName])

	var pose := HandlingPose.new()
	HandlingTimeline.evaluate(profile, {HandlingTrack.Event.RELOAD_EMPTY: 0.4}, true, pose)
	assert_almost_eq(pose.offset(&"").y, -0.1, 0.00001)
	assert_almost_eq(pose.rotation(&"").z, deg_to_rad(30.0), 0.00001)
	assert_almost_eq(pose.offset(&"Magazine").y, -0.3, 0.00001)
	assert_true(pose.is_hidden(&"Magazine"))
	assert_true(pose.is_hidden(&"Shell"), "staged until its window")
	assert_true(pose.is_hidden(&"Rocket"), "empty-hidden while empty")
	HandlingTimeline.evaluate(profile, {HandlingTrack.Event.RELOAD_EMPTY: 0.7}, false, pose)
	assert_false(pose.is_hidden(&"Magazine"))
	assert_false(pose.is_hidden(&"Shell"))
	assert_false(pose.is_hidden(&"Rocket"))
	HandlingTimeline.evaluate(profile, {HandlingTrack.Event.RELOAD_EMPTY: 0.95}, false, pose)
	assert_true(pose.is_hidden(&"Shell"), "HIDE wins over SHOW")
	HandlingTimeline.evaluate(profile, {HandlingTrack.Event.RELOAD_EMPTY: 1.0}, false, pose)
	assert_eq(pose.offset(&""), Vector3.ZERO)
	assert_eq(pose.offset(&"Magazine"), Vector3.ZERO)

	assert_eq(HandlingTimeline.releases_between(profile, HandlingTrack.Event.RELOAD_EMPTY, 0.2, 0.3), [mag] as Array[HandlingTrack])
	assert_true(HandlingTimeline.releases_between(profile, HandlingTrack.Event.RELOAD_EMPTY, 0.3, 0.6).is_empty(), "releases once")
	assert_true(HandlingTimeline.releases_between(profile, HandlingTrack.Event.RELOAD_TACTICAL, 0.0, 1.0).is_empty())

	var rest := Transform3D(Basis.IDENTITY, Vector3(0.0, -0.1, 0.0))
	HandlingTimeline.evaluate(profile, {HandlingTrack.Event.RELOAD_EMPTY: 0.4}, false, pose)
	var hidden: Transform3D = pose.apply_to(&"Magazine", rest, Vector3.ONE * 0.0001)
	assert_almost_eq(hidden.origin.y, -0.4, 0.00001)
	assert_almost_eq(hidden.basis.get_scale().x, 0.0001, 0.000001)


## Counts the ticks each event is reported, so the animation's duration is
## the logic's duration, which comes from the Resource. Reloads report from
## their starting tick (progress 0). Cycles and raises start the tick after
## the shot or switch, already one tick along, and end at their final tick,
## so they report one tick fewer than their length.
func _event_ticks(logic: WeaponLogic, input: WeaponInput, limit: int) -> Dictionary:
	var counts: Dictionary = {}
	var events: Dictionary = {}
	for tick: int in limit:
		logic.tick(DT, input)
		input.trigger_pressed = false
		input.reload_pressed = false
		HandlingTimeline.collect(logic, logic.raise_progress, events)
		for event: int in events:
			counts[event] = counts.get(event, 0) + 1
	return counts


func test_magazine_reload_events_span_the_resource_reload_times() -> void:
	for data: WeaponData in [RIFLE, PISTOL, SNIPER]:
		var logic := WeaponLogic.new(data)
		logic.equip_instantly()
		logic.ammo = 3
		var input := WeaponInput.new()
		input.reload_pressed = true
		var counts: Dictionary = _event_ticks(logic, input, 400)
		assert_eq(counts.get(HandlingTrack.Event.RELOAD_TACTICAL, 0), _ticks(data.reload_tactical_time), data.display_name)
		assert_false(counts.has(HandlingTrack.Event.RELOAD_EMPTY))
		logic.ammo = 0
		input.reload_pressed = true
		counts = _event_ticks(logic, input, 400)
		assert_eq(counts.get(HandlingTrack.Event.RELOAD_EMPTY, 0), _ticks(data.reload_empty_time), data.display_name)
		assert_almost_eq(HandlingTimeline.event_duration(data, HandlingTrack.Event.RELOAD_EMPTY), data.reload_empty_time, 0.000001)


func test_reload_progress_runs_from_zero_to_one_over_the_reload() -> void:
	var logic := WeaponLogic.new(RIFLE)
	logic.equip_instantly()
	logic.ammo = 0
	var input := WeaponInput.new()
	input.reload_pressed = true
	logic.tick(DT, input)
	input.reload_pressed = false
	var events: Dictionary = {}
	HandlingTimeline.collect(logic, 1.0, events)
	assert_eq(events.keys(), [HandlingTrack.Event.RELOAD_EMPTY])
	assert_eq(events[HandlingTrack.Event.RELOAD_EMPTY], 0.0)
	for tick: int in _ticks(RIFLE.reload_empty_time) / 2:
		logic.tick(DT, input)
	HandlingTimeline.collect(logic, 1.0, events)
	assert_almost_eq(events[HandlingTrack.Event.RELOAD_EMPTY], 0.5, DT / RIFLE.reload_empty_time + 0.0001)


func test_shell_phases_span_start_insert_and_finish_times() -> void:
	var logic := WeaponLogic.new(SHOTGUN)
	logic.equip_instantly()
	logic.ammo = 4
	var input := WeaponInput.new()
	input.reload_pressed = true
	var counts: Dictionary = _event_ticks(logic, input, 300)
	assert_eq(counts.get(HandlingTrack.Event.SHELL_START, 0), _ticks(SHOTGUN.reload_policy.shell_start_time))
	assert_eq(counts.get(HandlingTrack.Event.SHELL_INSERT, 0), 2 * _ticks(SHOTGUN.reload_tactical_time))
	assert_eq(counts.get(HandlingTrack.Event.SHELL_FINISH, 0), _ticks(SHOTGUN.reload_policy.shell_end_time))
	assert_eq(logic.ammo, 6)
	assert_almost_eq(HandlingTimeline.event_duration(SHOTGUN, HandlingTrack.Event.SHELL_INSERT, 0), SHOTGUN.reload_empty_time, 0.000001)
	assert_almost_eq(HandlingTimeline.event_duration(SHOTGUN, HandlingTrack.Event.SHELL_INSERT, 2), SHOTGUN.reload_tactical_time, 0.000001)


func test_cycle_spans_the_shot_interval_for_bolt_pump_and_melee() -> void:
	for data: WeaponData in [SNIPER, SHOTGUN, KNIFE, PISTOL]:
		var logic := WeaponLogic.new(data)
		logic.equip_instantly()
		var input := WeaponInput.new()
		input.trigger_pressed = true
		input.trigger_held = true
		var counts: Dictionary = _event_ticks(logic, input, 200)
		assert_eq(counts.get(HandlingTrack.Event.CYCLE, 0), _ticks(data.shot_interval()) - 1, data.display_name)
		assert_almost_eq(HandlingTimeline.event_duration(data, HandlingTrack.Event.CYCLE), data.shot_interval(), 0.000001)


func test_raise_and_lower_follow_their_own_times_and_reverse_smoothly() -> void:
	var logic := WeaponLogic.new(RIFLE)
	logic.start_raise()
	var input := WeaponInput.new()
	var counts: Dictionary = _event_ticks(logic, input, 120)
	assert_eq(counts.get(HandlingTrack.Event.LOWERED, 0), _ticks(RIFLE.raise_time) - 1)
	logic.start_lower()
	counts = _event_ticks(logic, input, 120)
	# Lowering reports every tick through the holstered tick, plus the rest
	# of the window while it stays holstered.
	var events: Dictionary = {}
	HandlingTimeline.collect(logic, logic.raise_progress, events)
	assert_eq(events[HandlingTrack.Event.LOWERED], 1.0)
	assert_eq(HandlingTimeline.event_duration(RIFLE, HandlingTrack.Event.LOWERED, 1, false), RIFLE.lower_time)
	# Reversing halfway continues from the same lowered amount: no jump.
	logic.start_raise()
	for tick: int in 6:
		logic.tick(DT, input)
	logic.start_lower()
	var before: float = logic.raise_progress
	logic.tick(DT, input)
	assert_almost_eq(logic.raise_progress, before - DT / RIFLE.lower_time, 0.00001)


func test_cancel_and_interrupt_drop_the_reload_event_immediately() -> void:
	var logic := WeaponLogic.new(RIFLE)
	logic.equip_instantly()
	logic.ammo = 0
	var input := WeaponInput.new()
	input.reload_pressed = true
	logic.tick(DT, input)
	input.reload_pressed = false
	for tick: int in 40:
		logic.tick(DT, input)
	logic.start_lower()
	var events: Dictionary = {}
	HandlingTimeline.collect(logic, logic.raise_progress, events)
	assert_false(events.has(HandlingTrack.Event.RELOAD_EMPTY))
	assert_false(events.has(HandlingTrack.Event.RELOAD_TACTICAL))

	var shells := WeaponLogic.new(SHOTGUN)
	shells.equip_instantly()
	shells.ammo = 3
	input.reload_pressed = true
	for tick: int in 20:
		shells.tick(DT, input)
		input.reload_pressed = false
	HandlingTimeline.collect(shells, 1.0, events)
	assert_true(events.has(HandlingTrack.Event.SHELL_INSERT))
	input.trigger_pressed = true
	input.trigger_held = true
	shells.tick(DT, input)
	HandlingTimeline.collect(shells, 1.0, events)
	assert_false(events.has(HandlingTrack.Event.SHELL_INSERT), "firing ends the insert at once")
	assert_true(events.has(HandlingTrack.Event.SHELL_FINISH))


func test_empty_hold_only_when_empty_and_settled() -> void:
	var logic := WeaponLogic.new(PISTOL)
	logic.equip_instantly()
	logic.ammo = 1
	var input := WeaponInput.new()
	input.trigger_pressed = true
	input.trigger_held = true
	logic.tick(DT, input)
	var events: Dictionary = {}
	HandlingTimeline.collect(logic, 1.0, events)
	assert_true(events.has(HandlingTrack.Event.CYCLE))
	assert_false(events.has(HandlingTrack.Event.EMPTY_HOLD))
	input.trigger_pressed = false
	input.trigger_held = false
	for tick: int in 20:
		logic.tick(DT, input)
	HandlingTimeline.collect(logic, 1.0, events)
	assert_eq(events, {HandlingTrack.Event.EMPTY_HOLD: 1.0})
	var knife := WeaponLogic.new(KNIFE)
	knife.equip_instantly()
	HandlingTimeline.collect(knife, 1.0, events)
	assert_true(events.is_empty(), "ammo-free weapons never hold empty")
