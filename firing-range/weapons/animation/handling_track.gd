class_name HandlingTrack
extends Resource
## One cosmetic motion of one viewmodel part during one handling event.
##
## Times are fractions (0..1) of the event's own duration. The duration is
## never stored here: it always comes from `WeaponLogic`, which takes it from
## the weapon's Resource times (reload, shell, cycle, raise and lower). So a
## track stays in step with gameplay whatever the tuning, and an attachment
## that slows a reload slows its animation by exactly the same factor.
##
## The motion is a pulse: it eases from rest to `offset` / `rotation_degrees`
## between `out_start` and `out_end`, holds, and eases back between
## `back_start` and `back_end`. `back_start = 1` means it never returns
## within this event (a later event takes over, as shell loading does).

enum Event {
	RELOAD_TACTICAL,
	RELOAD_EMPTY,
	SHELL_START,
	SHELL_INSERT,
	SHELL_FINISH,
	## Working the action after a shot (bolt, pump, slide), or a melee swing.
	CYCLE,
	## Raise and lower: progress is how far the weapon is put away.
	LOWERED,
	## Ammo-using weapon sitting empty, e.g. a slide locked back.
	EMPTY_HOLD,
}
enum Visibility { UNCHANGED, SHOW, HIDE }

@export var event: Event = Event.RELOAD_TACTICAL
## Node path inside the viewmodel; empty moves the whole model. A matching
## attachment mount (`Mounts/<part>`) follows the part rigidly.
@export var part: StringName = &""
## Local offset at full weight, metres.
@export var offset: Vector3 = Vector3.ZERO
## Local rotation at full weight, degrees (applied about the part's origin).
@export var rotation_degrees: Vector3 = Vector3.ZERO
@export_range(0.0, 1.0, 0.01) var out_start: float = 0.0
@export_range(0.0, 1.0, 0.01) var out_end: float = 0.0
@export_range(0.0, 1.0, 0.01) var back_start: float = 1.0
@export_range(0.0, 1.0, 0.01) var back_end: float = 1.0
## SHOW reveals a staged or empty-hidden part inside the window; HIDE hides
## it there and wins over any SHOW.
@export var visibility: Visibility = Visibility.UNCHANGED
@export_range(0.0, 1.0, 0.01) var window_start: float = 0.0
@export_range(0.0, 1.0, 0.01) var window_end: float = 1.0
## With HIDE: a pooled physics copy of the part drops as the window opens.
@export var releases_copy: bool = false


## 0 at rest, 1 at the full pose.
func weight(progress: float) -> float:
	var up: float = _ease(out_start, out_end, progress)
	var down: float = 0.0 if back_start >= 1.0 else _ease(back_start, back_end, progress)
	return up * (1.0 - down)


func in_window(progress: float) -> bool:
	if visibility == Visibility.UNCHANGED:
		return false
	if window_end >= 1.0:
		return progress >= window_start
	return progress >= window_start and progress < window_end


func is_valid() -> bool:
	var ordered: bool = 0.0 <= out_start and out_start <= out_end and out_end <= back_start and back_start <= back_end and back_end <= 1.0
	var window_ok: bool = 0.0 <= window_start and window_start <= window_end and window_end <= 1.0
	return ordered and window_ok and (not releases_copy or visibility == Visibility.HIDE)


static func _ease(from: float, to: float, progress: float) -> float:
	if to <= from:
		return 1.0 if progress >= from else 0.0
	return smoothstep(from, to, progress)
