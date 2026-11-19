class_name WeaponLogic
extends RefCounted
## State machine for one weapon. No nodes and no input map: `tick` takes a
## `WeaponInput` and a time step, so every timing is testable to the tick.
##
## Main states: HOLSTERED -> RAISING -> READY <-> FIRING / RELOADING, and
## LOWERING back to HOLSTERED. Aiming is tracked separately as a 0..1
## progress, because it overlaps READY and FIRING.
##
## Shots remove one round; magazine completion fills the gun, while shell
## reloads credit each completed insert. Cancellation never grants a round.

signal fired
signal dry_fired
signal reload_started(is_empty: bool, duration: float)
signal reload_finished
signal reload_cancelled
signal shell_inserted(ammo: int)
signal state_changed(new_state: State)
signal raised
signal lowered

enum State { HOLSTERED, RAISING, READY, FIRING, RELOADING, LOWERING }
enum AimState { HIP, AIMING_IN, AIMED, AIMING_OUT }
enum ReloadPhase { NONE, START, INSERT, FINISH }

## Slack for comparing accumulated tick times against zero.
const TIME_EPSILON: float = 0.00001

var data: WeaponData
var state: State = State.HOLSTERED
var ammo: int = 0

## 0 at the hip, 1 fully aimed. Moves linearly over `data.ads_time`.
var aim_progress: float = 0.0
var previous_aim_progress: float = 0.0
## 0 put away, 1 fully up.
var raise_progress: float = 0.0
var previous_raise_progress: float = 0.0

var _aim_target: float = 0.0
var _time_to_next_shot: float = 0.0
var _reload_time_left: float = 0.0
var _reload_duration: float = 0.0
var _reload_is_empty: bool = false
var _reload_queued: bool = false
var _carry_remainder: bool = false
var reload_phase: ReloadPhase = ReloadPhase.NONE
var _shell_fire_requested: bool = false
var _sprint_recovery_left: float = 0.0


func _init(weapon_data: WeaponData) -> void:
	data = weapon_data
	ammo = data.magazine_size if data.uses_ammo else 0


## Advances the weapon by one tick. Returns how many shots were fired.
func tick(delta: float, input: WeaponInput) -> int:
	previous_aim_progress = aim_progress
	previous_raise_progress = raise_progress
	_sprint_recovery_left = data.sprint_to_fire_time if input.sprinting else maxf(_sprint_recovery_left - delta, 0.0)

	var shots: int = 0
	_carry_remainder = false
	match state:
		State.RAISING:
			raise_progress = minf(raise_progress + delta / data.raise_time, 1.0)
			if raise_progress >= 1.0 - TIME_EPSILON:
				raise_progress = 1.0
				_set_state(State.READY)
				raised.emit()
		State.LOWERING:
			raise_progress = maxf(raise_progress - delta / data.lower_time, 0.0)
			if raise_progress <= TIME_EPSILON:
				_holster()
				lowered.emit()
		State.RELOADING:
			if _uses_shells():
				shots = _tick_shell_reload(delta, input)
			else:
				_reload_time_left -= delta
				if _reload_time_left <= TIME_EPSILON:
					ammo = data.reload_policy.refill(ammo, data.magazine_size) if data.reload_policy != null else data.magazine_size
					_set_state(State.READY)
					reload_finished.emit()
		State.READY, State.FIRING:
			shots = _tick_ready(input)

	_tick_aim(delta, input)
	# Time passes after this tick's decisions. A negative remainder is only
	# carried while the trigger keeps the weapon firing; otherwise it would
	# make the first interval after a pause one tick short.
	_time_to_next_shot -= delta
	if not _carry_remainder:
		_time_to_next_shot = maxf(_time_to_next_shot, 0.0)
	return shots


## Starts bringing the weapon up. Continues from wherever it is, so a switch
## cancelled halfway does not restart from the bottom.
func start_raise() -> void:
	if state == State.READY or state == State.FIRING or state == State.RELOADING:
		return
	_set_state(State.RAISING)


## Starts putting the weapon away. Cancels a reload in progress without
## touching the ammo count.
func start_lower() -> void:
	if state == State.HOLSTERED or state == State.LOWERING:
		return
	if state == State.RELOADING:
		_reload_time_left = 0.0
		reload_phase = ReloadPhase.NONE
		_shell_fire_requested = false
		reload_cancelled.emit()
	_reload_queued = false
	_set_state(State.LOWERING)


## Puts the weapon straight into READY, fully raised. Used for the weapon the
## player starts with.
func equip_instantly() -> void:
	raise_progress = 1.0
	previous_raise_progress = 1.0
	_set_state(State.READY)


## Full ammo, nothing in progress and put away, as after a respawn.
func reset_for_respawn() -> void:
	if state == State.RELOADING:
		reload_cancelled.emit()
	_reload_time_left = 0.0
	reload_phase = ReloadPhase.NONE
	_shell_fire_requested = false
	_reload_queued = false
	_sprint_recovery_left = 0.0
	ammo = data.magazine_size if data.uses_ammo else 0
	_holster()


func is_reloading() -> bool:
	return state == State.RELOADING


func is_reload_empty() -> bool:
	return state == State.RELOADING and _reload_is_empty


## 0 when a reload has just started, 1 when it is about to finish.
func get_reload_progress() -> float:
	if state != State.RELOADING or _reload_duration <= 0.0:
		return 0.0
	return clampf(1.0 - _reload_time_left / _reload_duration, 0.0, 1.0)


## Seconds until the weapon can fire again. 0 when it is ready now.
func get_time_to_next_shot() -> float:
	return maxf(_time_to_next_shot, 0.0)


func get_aim_state() -> AimState:
	if aim_progress <= 0.0:
		return AimState.HIP
	if aim_progress >= 1.0:
		return AimState.AIMED
	return AimState.AIMING_IN if _aim_target > 0.5 else AimState.AIMING_OUT


func can_reload() -> bool:
	return data.uses_ammo and (data.reload_policy.can_reload(ammo, data.magazine_size) if data.reload_policy != null else ammo < data.magazine_size) and (state == State.READY or state == State.FIRING)


func _tick_ready(input: WeaponInput) -> int:
	var cooled_down: bool = _time_to_next_shot <= TIME_EPSILON
	if state == State.FIRING and cooled_down:
		_set_state(State.READY)

	# A reload pressed mid-cycle (between shots, or while working the bolt)
	# is remembered and starts as soon as the weapon is ready.
	if input.reload_pressed and can_reload():
		_reload_queued = true
	if _reload_queued and cooled_down:
		_start_reload()
		return 0

	var wants_shot: bool = data.wants_shot(input.trigger_held, input.trigger_pressed)
	if data.uses_ammo and ammo <= 0:
		# An empty magazine reloads itself when the trigger is pulled.
		if input.trigger_pressed:
			dry_fired.emit()
		if input.trigger_held and cooled_down and (data.reload_policy == null or data.reload_policy.kind != ReloadData.Kind.NONE):
			_start_reload()
		return 0

	if not wants_shot or input.sprinting or _sprint_recovery_left > TIME_EPSILON:
		return 0
	_carry_remainder = true

	# The remainder of the interval is carried from shot to shot, so the
	# average rate is exact even when the interval is not a whole number of
	# ticks (700 rpm is 5.14 ticks).
	var shots: int = 0
	while _time_to_next_shot <= TIME_EPSILON and (not data.uses_ammo or ammo > 0):
		if data.uses_ammo:
			ammo -= 1
		shots += 1
		_time_to_next_shot += data.shot_interval()
		fired.emit()
		if not data.automatic:
			break
	if shots > 0:
		_set_state(State.FIRING)
	return shots


func _tick_aim(delta: float, input: WeaponInput) -> void:
	var can_aim: bool = data.can_aim and (state == State.READY or state == State.FIRING)
	_aim_target = 1.0 if (input.aim_held and can_aim and not input.sprinting) else 0.0
	aim_progress = move_toward(aim_progress, _aim_target, delta / data.ads_time)
	# Snap away accumulated float error so "fully aimed" is exactly 1.
	if absf(aim_progress - _aim_target) <= TIME_EPSILON:
		aim_progress = _aim_target


func _start_reload() -> void:
	_reload_queued = false
	_reload_is_empty = ammo <= 0
	_reload_duration = data.reload_time(ammo)
	_reload_time_left = _reload_duration
	_shell_fire_requested = false
	if _uses_shells():
		_start_shell_phase(ReloadPhase.START)
	_set_state(State.RELOADING)
	reload_started.emit(_reload_is_empty, _reload_duration)


func _holster() -> void:
	raise_progress = 0.0
	aim_progress = 0.0
	previous_aim_progress = 0.0
	_time_to_next_shot = 0.0
	_set_state(State.HOLSTERED)


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)


func _uses_shells() -> bool:
	return data.reload_policy != null and data.reload_policy.kind == ReloadData.Kind.SHELL


func _start_shell_phase(phase: ReloadPhase) -> void:
	reload_phase = phase
	match phase:
		ReloadPhase.START:
			_reload_duration = data.reload_policy.shell_start_time
		ReloadPhase.INSERT:
			_reload_duration = data.reload_time(ammo)
		ReloadPhase.FINISH:
			_reload_duration = data.reload_policy.shell_end_time
	_reload_time_left = _reload_duration


func _tick_shell_reload(delta: float, input: WeaponInput) -> int:
	if data.wants_shot(input.trigger_held, input.trigger_pressed) and not input.sprinting:
		_shell_fire_requested = true
	if _shell_fire_requested and ammo > 0 and reload_phase != ReloadPhase.FINISH:
		# Discard an unfinished insert; completed rounds remain loaded.
		_start_shell_phase(ReloadPhase.FINISH)
	_reload_time_left -= delta
	while _reload_time_left <= TIME_EPSILON:
		var remainder: float = maxf(-_reload_time_left, 0.0)
		match reload_phase:
			ReloadPhase.START:
				_start_shell_phase(ReloadPhase.INSERT)
			ReloadPhase.INSERT:
				ammo = data.reload_policy.refill(ammo, data.magazine_size)
				shell_inserted.emit(ammo)
				_start_shell_phase(ReloadPhase.FINISH if ammo >= data.magazine_size or _shell_fire_requested else ReloadPhase.INSERT)
			ReloadPhase.FINISH:
				reload_phase = ReloadPhase.NONE
				_set_state(State.READY)
				reload_finished.emit()
				if not _shell_fire_requested:
					return 0
				_shell_fire_requested = false
				var resumed := WeaponInput.new()
				resumed.trigger_pressed = true
				resumed.trigger_held = true
				resumed.aim_held = input.aim_held
				resumed.sprinting = input.sprinting
				return _tick_ready(resumed)
		_reload_time_left -= remainder
	return 0
