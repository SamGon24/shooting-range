extends GutTest
## WeaponLogic stepped tick by tick at 60 Hz: fire rate, magazine, reloads,
## aiming and raise/lower. No nodes involved.

const TICK: float = 1.0 / 60.0
const RIFLE: WeaponData = preload("res://weapons/data/halberd_rifle.tres")
const SNIPER: WeaponData = preload("res://weapons/data/longwatch_sniper.tres")

var _input: WeaponInput


func before_each() -> void:
	_input = WeaponInput.new()


func _ready_weapon(data: WeaponData) -> WeaponLogic:
	var logic := WeaponLogic.new(data)
	logic.equip_instantly()
	return logic


func _ticks_for(seconds: float) -> int:
	return roundi(seconds / TICK)


## Ticks the weapon `ticks` times with the current input. `trigger_pressed`
## and `reload_pressed` are edge inputs, so they are cleared after one tick.
func _run(logic: WeaponLogic, ticks: int) -> int:
	var shots: int = 0
	for _tick: int in ticks:
		shots += logic.tick(TICK, _input)
		_input.trigger_pressed = false
		_input.reload_pressed = false
	return shots


func _pull_trigger() -> void:
	_input.trigger_held = true
	_input.trigger_pressed = true


func _release_trigger() -> void:
	_input.trigger_held = false
	_input.trigger_pressed = false


# --- Weapon data ---


func test_weapons_match_the_design_brief() -> void:
	assert_true(RIFLE.automatic, "rifle is full-auto")
	assert_almost_eq(RIFLE.projectile.muzzle_velocity, 850.0, 0.001)
	assert_false(SNIPER.automatic, "sniper fires one round per trigger pull")
	assert_almost_eq(SNIPER.projectile.muzzle_velocity, 900.0, 0.001)
	assert_true(SNIPER.scoped)
	assert_gt(SNIPER.bolt_cycle_time, 0.0)
	for data: WeaponData in [RIFLE, SNIPER]:
		assert_ne(data.display_name, "Weapon", "has its own name")
		assert_gt(data.reload_empty_time, data.reload_tactical_time, "%s: empty reload is slower" % data.display_name)
		assert_lt(data.ads_sensitivity_scale, 1.0)


func test_shot_interval_uses_the_slower_of_rate_and_bolt() -> void:
	assert_almost_eq(RIFLE.shot_interval(), 60.0 / 700.0, 0.000001)
	assert_almost_eq(SNIPER.shot_interval(), SNIPER.bolt_cycle_time, 0.000001)


# --- Fire rate ---


func test_first_shot_fires_on_the_tick_the_trigger_is_pulled() -> void:
	var logic: WeaponLogic = _ready_weapon(RIFLE)
	_pull_trigger()
	assert_eq(_run(logic, 1), 1)
	assert_eq(logic.ammo, RIFLE.magazine_size - 1)
	assert_eq(logic.state, WeaponLogic.State.FIRING)


func test_600_rpm_fires_exactly_every_sixth_tick() -> void:
	var data: WeaponData = RIFLE.duplicate() as WeaponData
	data.rounds_per_minute = 600.0
	data.magazine_size = 100
	var logic: WeaponLogic = _ready_weapon(data)
	_input.trigger_held = true

	var shot_ticks: Array[int] = []
	for tick: int in 60:
		if logic.tick(TICK, _input) > 0:
			shot_ticks.append(tick)
	assert_eq(shot_ticks, [0, 6, 12, 18, 24, 30, 36, 42, 48, 54] as Array[int], "10 shots in one second")


func test_rate_is_the_same_after_an_idle_pause() -> void:
	var data: WeaponData = RIFLE.duplicate() as WeaponData
	data.rounds_per_minute = 600.0
	var logic: WeaponLogic = _ready_weapon(data)
	_run(logic, 37)  # Sit idle for a while first.

	_input.trigger_held = true
	var shot_ticks: Array[int] = []
	for tick: int in 20:
		if logic.tick(TICK, _input) > 0:
			shot_ticks.append(tick)
	assert_eq(shot_ticks, [0, 6, 12, 18] as Array[int], "first interval is a full 6 ticks")


func test_rifle_rate_of_fire_averages_700_rpm() -> void:
	var data: WeaponData = RIFLE.duplicate() as WeaponData
	data.magazine_size = 200
	var logic: WeaponLogic = _ready_weapon(data)
	_input.trigger_held = true

	# 700 rpm is 5.14 ticks per shot, so shots alternate between 5 and 6
	# ticks apart. Over 6 seconds that must come to exactly 70 shots, plus
	# the one fired at t = 0.
	var shots: int = _run(logic, 360)
	assert_eq(shots, 70, "6 s at 700 rpm")
	assert_eq(logic.ammo, 200 - 70)


func test_rifle_shot_spacing_is_five_or_six_ticks() -> void:
	var logic: WeaponLogic = _ready_weapon(RIFLE)
	_input.trigger_held = true
	var last_shot_tick: int = -1
	for tick: int in 120:
		var shots: int = logic.tick(TICK, _input)
		assert_lte(shots, 1, "never two shots in one tick at this rate")
		if shots == 1:
			if last_shot_tick >= 0:
				assert_between(tick - last_shot_tick, 5, 6)
			last_shot_tick = tick


func test_releasing_the_trigger_stops_fire_and_does_not_bank_a_shot() -> void:
	var logic: WeaponLogic = _ready_weapon(RIFLE)
	_pull_trigger()
	_run(logic, 3)
	_release_trigger()
	assert_eq(_run(logic, 120), 0, "no shots with the trigger up")
	assert_eq(logic.state, WeaponLogic.State.READY)

	_pull_trigger()
	assert_eq(_run(logic, 1), 1, "exactly one shot on the next pull, not a burst")


func test_sniper_needs_a_new_pull_for_each_shot() -> void:
	var logic: WeaponLogic = _ready_weapon(SNIPER)
	_pull_trigger()
	assert_eq(_run(logic, _ticks_for(3.0)), 1, "holding the trigger fires once")
	assert_eq(logic.ammo, SNIPER.magazine_size - 1)


func test_sniper_cannot_fire_until_the_bolt_has_cycled() -> void:
	var logic: WeaponLogic = _ready_weapon(SNIPER)
	var bolt_ticks: int = _ticks_for(SNIPER.bolt_cycle_time)
	_pull_trigger()
	_run(logic, 1)

	# Pull again one tick before the bolt is done: nothing.
	_run(logic, bolt_ticks - 2)
	_pull_trigger()
	assert_eq(_run(logic, 1), 0, "bolt still cycling")
	assert_eq(logic.state, WeaponLogic.State.FIRING)

	# Pull on the tick the bolt finishes: it fires.
	_pull_trigger()
	assert_eq(_run(logic, 1), 1, "fires as soon as the bolt has cycled")
	assert_eq(logic.ammo, SNIPER.magazine_size - 2)


func test_sprinting_blocks_firing() -> void:
	var logic: WeaponLogic = _ready_weapon(RIFLE)
	_input.sprinting = true
	_pull_trigger()
	assert_eq(_run(logic, 30), 0)
	assert_eq(logic.ammo, RIFLE.magazine_size)

	_input.sprinting = false
	assert_eq(_run(logic, 1), 1, "fires on the first tick after sprinting stops")


func test_emits_fired_once_per_shot() -> void:
	var logic: WeaponLogic = _ready_weapon(RIFLE)
	watch_signals(logic)
	_input.trigger_held = true
	var shots: int = _run(logic, 60)
	assert_signal_emit_count(logic, "fired", shots)


# --- Magazine and reload ---


func test_magazine_runs_dry_then_reloads_itself_with_the_empty_timing() -> void:
	var logic: WeaponLogic = _ready_weapon(RIFLE)
	watch_signals(logic)
	_input.trigger_held = true
	var shots: int = 0
	var ticks: int = 0
	while logic.state != WeaponLogic.State.RELOADING and ticks < 600:
		shots += logic.tick(TICK, _input)
		ticks += 1

	assert_eq(shots, RIFLE.magazine_size, "fired the whole magazine and no more")
	assert_eq(logic.ammo, 0)
	assert_true(logic.is_reload_empty(), "an empty magazine uses the empty reload")
	assert_signal_emitted_with_parameters(logic, "reload_started", [true, RIFLE.reload_empty_time])

	var reload_ticks: int = _ticks_for(RIFLE.reload_empty_time)
	_release_trigger()
	_run(logic, reload_ticks - 1)
	assert_eq(logic.ammo, 0, "no ammo until the reload completes")
	assert_eq(logic.state, WeaponLogic.State.RELOADING)
	_run(logic, 1)
	assert_eq(logic.ammo, RIFLE.magazine_size)
	assert_eq(logic.state, WeaponLogic.State.READY)
	assert_signal_emitted(logic, "reload_finished")


func test_tactical_reload_takes_the_tactical_time() -> void:
	var logic: WeaponLogic = _ready_weapon(RIFLE)
	_pull_trigger()
	_run(logic, 12)
	_release_trigger()
	_run(logic, 10)
	var ammo_before: int = logic.ammo
	assert_between(ammo_before, 1, RIFLE.magazine_size - 1)

	_input.reload_pressed = true
	_run(logic, 1)
	assert_eq(logic.state, WeaponLogic.State.RELOADING)
	assert_false(logic.is_reload_empty())

	var reload_ticks: int = _ticks_for(RIFLE.reload_tactical_time)
	_run(logic, reload_ticks - 1)
	assert_eq(logic.ammo, ammo_before, "count unchanged during the reload")
	assert_almost_eq(logic.get_reload_progress(), 1.0, 0.02)
	_run(logic, 1)
	assert_eq(logic.ammo, RIFLE.magazine_size)
	assert_eq(logic.state, WeaponLogic.State.READY)


func test_reload_with_a_full_magazine_does_nothing() -> void:
	var logic: WeaponLogic = _ready_weapon(RIFLE)
	_input.reload_pressed = true
	_run(logic, 5)
	assert_eq(logic.state, WeaponLogic.State.READY)


func test_cannot_fire_while_reloading() -> void:
	var logic: WeaponLogic = _ready_weapon(RIFLE)
	_pull_trigger()
	_run(logic, 1)
	_release_trigger()
	_run(logic, 10)
	_input.reload_pressed = true
	_run(logic, 1)

	_pull_trigger()
	assert_eq(_run(logic, 30), 0)
	assert_eq(logic.state, WeaponLogic.State.RELOADING)


func test_reload_pressed_during_the_bolt_cycle_starts_when_the_bolt_is_done() -> void:
	var logic: WeaponLogic = _ready_weapon(SNIPER)
	_pull_trigger()
	_run(logic, 1)
	_release_trigger()
	_input.reload_pressed = true
	_run(logic, 1)
	assert_eq(logic.state, WeaponLogic.State.FIRING, "bolt first")
	_run(logic, _ticks_for(SNIPER.bolt_cycle_time))
	assert_eq(logic.state, WeaponLogic.State.RELOADING, "then the queued reload")
	assert_false(logic.is_reload_empty())


func test_reload_cancelled_by_lowering_keeps_the_ammo_count() -> void:
	var logic: WeaponLogic = _ready_weapon(RIFLE)
	watch_signals(logic)
	_pull_trigger()
	_run(logic, 30)
	_release_trigger()
	_run(logic, 10)
	var ammo_before: int = logic.ammo

	_input.reload_pressed = true
	_run(logic, 1)
	_run(logic, _ticks_for(RIFLE.reload_tactical_time) / 2)
	assert_eq(logic.state, WeaponLogic.State.RELOADING, "halfway through")

	logic.start_lower()
	assert_signal_emitted(logic, "reload_cancelled")
	_run(logic, _ticks_for(RIFLE.lower_time))
	assert_eq(logic.state, WeaponLogic.State.HOLSTERED)
	assert_eq(logic.ammo, ammo_before, "cancelled reload added nothing")

	# Bring it back up: still the old count, and no reload resumes by itself.
	logic.start_raise()
	_run(logic, _ticks_for(RIFLE.raise_time))
	assert_eq(logic.state, WeaponLogic.State.READY)
	_run(logic, _ticks_for(RIFLE.reload_tactical_time) + 5)
	assert_eq(logic.ammo, ammo_before)
	assert_signal_not_emitted(logic, "reload_finished")

	# And a fresh reload still works and takes the full time again.
	_input.reload_pressed = true
	_run(logic, 1)
	_run(logic, _ticks_for(RIFLE.reload_tactical_time) - 1)
	assert_eq(logic.ammo, ammo_before)
	_run(logic, 1)
	assert_eq(logic.ammo, RIFLE.magazine_size)


func test_dry_fire_signal_on_an_empty_pull() -> void:
	var data: WeaponData = SNIPER.duplicate() as WeaponData
	data.magazine_size = 1
	var logic: WeaponLogic = _ready_weapon(data)
	watch_signals(logic)
	_pull_trigger()
	_run(logic, 1)
	_release_trigger()
	_run(logic, _ticks_for(data.bolt_cycle_time))
	assert_eq(logic.ammo, 0)

	_pull_trigger()
	_run(logic, 1)
	assert_signal_emitted(logic, "dry_fired")
	assert_eq(logic.state, WeaponLogic.State.RELOADING, "and the empty reload starts")
	assert_true(logic.is_reload_empty())


# --- Aiming ---


func test_ads_takes_exactly_ads_time_to_aim_in() -> void:
	for data: WeaponData in [RIFLE, SNIPER]:
		var logic: WeaponLogic = _ready_weapon(data)
		var ads_ticks: int = _ticks_for(data.ads_time)
		_input.aim_held = true
		_run(logic, ads_ticks - 1)
		assert_lt(logic.aim_progress, 1.0, "%s: not fully aimed one tick early" % data.display_name)
		assert_eq(logic.get_aim_state(), WeaponLogic.AimState.AIMING_IN)
		_run(logic, 1)
		assert_eq(logic.aim_progress, 1.0, "%s: fully aimed after ads_time" % data.display_name)
		assert_eq(logic.get_aim_state(), WeaponLogic.AimState.AIMED)


func test_ads_progress_is_linear() -> void:
	var logic: WeaponLogic = _ready_weapon(SNIPER)
	_input.aim_held = true
	_run(logic, _ticks_for(SNIPER.ads_time) / 2)
	assert_almost_eq(logic.aim_progress, 0.5, 0.001)


func test_ads_takes_ads_time_to_aim_out() -> void:
	var logic: WeaponLogic = _ready_weapon(RIFLE)
	var ads_ticks: int = _ticks_for(RIFLE.ads_time)
	_input.aim_held = true
	_run(logic, ads_ticks)
	_input.aim_held = false
	_run(logic, ads_ticks - 1)
	assert_gt(logic.aim_progress, 0.0)
	assert_eq(logic.get_aim_state(), WeaponLogic.AimState.AIMING_OUT)
	_run(logic, 1)
	assert_eq(logic.aim_progress, 0.0)
	assert_eq(logic.get_aim_state(), WeaponLogic.AimState.HIP)


func test_releasing_aim_halfway_reverses_from_where_it_was() -> void:
	var logic: WeaponLogic = _ready_weapon(SNIPER)
	var half: int = _ticks_for(SNIPER.ads_time) / 2
	_input.aim_held = true
	_run(logic, half)
	_input.aim_held = false
	_run(logic, half)
	assert_eq(logic.aim_progress, 0.0, "half in, half out")


func test_sprinting_blocks_and_drops_aim() -> void:
	var logic: WeaponLogic = _ready_weapon(RIFLE)
	_input.aim_held = true
	_input.sprinting = true
	_run(logic, 30)
	assert_eq(logic.aim_progress, 0.0, "cannot aim while sprinting")

	_input.sprinting = false
	_run(logic, _ticks_for(RIFLE.ads_time))
	assert_eq(logic.aim_progress, 1.0)
	_input.sprinting = true
	_run(logic, _ticks_for(RIFLE.ads_time))
	assert_eq(logic.aim_progress, 0.0, "starting to sprint drops the aim")


func test_reloading_drops_aim() -> void:
	var logic: WeaponLogic = _ready_weapon(RIFLE)
	_input.aim_held = true
	_pull_trigger()
	_run(logic, _ticks_for(RIFLE.ads_time) + 6)
	_release_trigger()
	assert_eq(logic.aim_progress, 1.0, "can aim while firing")
	_input.reload_pressed = true
	_run(logic, _ticks_for(RIFLE.ads_time) + 8)
	assert_eq(logic.state, WeaponLogic.State.RELOADING)
	assert_eq(logic.aim_progress, 0.0)


func test_previous_aim_progress_trails_by_one_tick() -> void:
	var logic: WeaponLogic = _ready_weapon(RIFLE)
	_input.aim_held = true
	_run(logic, 3)
	var before: float = logic.aim_progress
	_run(logic, 1)
	assert_eq(logic.previous_aim_progress, before)


# --- Raise and lower ---


func test_starts_holstered_with_a_full_magazine() -> void:
	var logic := WeaponLogic.new(RIFLE)
	assert_eq(logic.state, WeaponLogic.State.HOLSTERED)
	assert_eq(logic.ammo, RIFLE.magazine_size)
	_pull_trigger()
	assert_eq(_run(logic, 10), 0, "a holstered weapon cannot fire")


func test_raise_takes_raise_time_and_blocks_firing_until_done() -> void:
	var logic := WeaponLogic.new(SNIPER)
	watch_signals(logic)
	logic.start_raise()
	var raise_ticks: int = _ticks_for(SNIPER.raise_time)
	_input.aim_held = true
	_pull_trigger()
	assert_eq(_run(logic, raise_ticks - 1), 0)
	assert_eq(logic.state, WeaponLogic.State.RAISING)
	assert_eq(logic.aim_progress, 0.0, "cannot aim while raising")
	_run(logic, 1)
	assert_eq(logic.state, WeaponLogic.State.READY)
	assert_eq(logic.raise_progress, 1.0)
	assert_signal_emitted(logic, "raised")


func test_lower_takes_lower_time() -> void:
	var logic: WeaponLogic = _ready_weapon(RIFLE)
	watch_signals(logic)
	logic.start_lower()
	var lower_ticks: int = _ticks_for(RIFLE.lower_time)
	_run(logic, lower_ticks - 1)
	assert_eq(logic.state, WeaponLogic.State.LOWERING)
	_run(logic, 1)
	assert_eq(logic.state, WeaponLogic.State.HOLSTERED)
	assert_eq(logic.raise_progress, 0.0)
	assert_signal_emitted(logic, "lowered")


func test_lowering_drops_aim_and_blocks_fire() -> void:
	var logic: WeaponLogic = _ready_weapon(RIFLE)
	_input.aim_held = true
	_run(logic, _ticks_for(RIFLE.ads_time))
	logic.start_lower()
	_pull_trigger()
	assert_eq(_run(logic, _ticks_for(RIFLE.lower_time)), 0)
	assert_eq(logic.aim_progress, 0.0)


func test_raise_resumes_from_a_half_finished_lower() -> void:
	var logic: WeaponLogic = _ready_weapon(RIFLE)
	logic.start_lower()
	_run(logic, _ticks_for(RIFLE.lower_time) / 2)
	var halfway: float = logic.raise_progress
	assert_between(halfway, 0.4, 0.6)
	logic.start_raise()
	_run(logic, 1)
	assert_gt(logic.raise_progress, halfway, "comes back up from where it was")
