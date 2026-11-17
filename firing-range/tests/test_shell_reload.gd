extends GutTest

const DT: float = 1.0 / 60.0
var _data: WeaponData
var _logic: WeaponLogic
var _input: WeaponInput


func before_each() -> void:
	_data = WeaponData.new()
	_data.fire_mode = FireModeData.new()
	_data.fire_mode.kind = FireModeData.Kind.PUMP_ACTION
	_data.reload_policy = ReloadData.new()
	_data.reload_policy.kind = ReloadData.Kind.SHELL
	_data.reload_policy.shell_start_time = 0.05
	_data.reload_policy.shell_end_time = 0.05
	_data.magazine_size = 6
	_data.rounds_per_minute = 75.0
	_data.bolt_cycle_time = 0.8
	_data.reload_tactical_time = 0.1
	_data.reload_empty_time = 0.2
	_logic = WeaponLogic.new(_data)
	_logic.equip_instantly()
	_input = WeaponInput.new()


func _ticks(count: int) -> int:
	var shots: int = 0
	for tick: int in count:
		shots += _logic.tick(DT, _input)
	return shots


func _reload(ammo: int) -> void:
	_logic.ammo = ammo
	_input.reload_pressed = true
	_logic.tick(DT, _input)
	_input.reload_pressed = false


func test_rounds_credit_only_at_insert_boundaries_and_finish_at_capacity() -> void:
	_reload(4)
	assert_eq(_logic.reload_phase, WeaponLogic.ReloadPhase.START)
	_ticks(3)
	assert_eq(_logic.reload_phase, WeaponLogic.ReloadPhase.INSERT)
	_ticks(5)
	assert_eq(_logic.ammo, 4)
	_ticks(1)
	assert_eq(_logic.ammo, 5)
	_ticks(6)
	assert_eq(_logic.ammo, 6)
	assert_true(_logic.is_reloading())
	_ticks(3)
	assert_eq(_logic.state, WeaponLogic.State.READY)
	assert_eq(_logic.reload_phase, WeaponLogic.ReloadPhase.NONE)


func test_fire_interrupt_discards_partial_shell_closes_then_fires_once() -> void:
	_reload(1)
	_ticks(6)
	_input.trigger_pressed = true
	_input.trigger_held = true
	assert_eq(_logic.tick(DT, _input), 0)
	_input.trigger_pressed = false
	assert_eq(_logic.reload_phase, WeaponLogic.ReloadPhase.FINISH)
	assert_eq(_logic.ammo, 1)
	assert_eq(_ticks(2), 1)
	assert_eq(_logic.ammo, 0)
	# A held pump trigger cannot fire another round after the cycle.
	_input.trigger_held = false
	_logic.ammo = 2
	_input.trigger_held = true
	assert_eq(_ticks(60), 0)
	_input.trigger_pressed = true
	assert_eq(_logic.tick(DT, _input), 1)


func test_empty_interrupt_waits_for_first_complete_shell_before_firing() -> void:
	_reload(0)
	_input.trigger_pressed = true
	_input.trigger_held = true
	_logic.tick(DT, _input)
	_input.trigger_pressed = false
	assert_eq(_ticks(13), 0, "start plus empty insertion is not yet complete")
	assert_eq(_logic.ammo, 0)
	assert_eq(_ticks(4), 1, "close finishes, then exactly one queued shot")
	assert_eq(_logic.ammo, 0)
	assert_eq(_logic.state, WeaponLogic.State.FIRING)


func test_holstering_keeps_completed_shells_and_drops_pending_fire() -> void:
	_reload(1)
	_ticks(10)
	assert_eq(_logic.ammo, 2)
	_logic.start_lower()
	_ticks(60)
	assert_eq(_logic.state, WeaponLogic.State.HOLSTERED)
	assert_eq(_logic.ammo, 2)
	_logic.start_raise()
	_ticks(60)
	assert_eq(_logic.ammo, 2)
	assert_eq(_logic.state, WeaponLogic.State.READY)


func test_large_step_matches_small_steps_for_full_shell_reload() -> void:
	_reload(0)
	_logic.tick(0.8, _input)
	assert_eq(_logic.ammo, 6)
	assert_eq(_logic.state, WeaponLogic.State.READY)
	var other := WeaponLogic.new(_data)
	other.equip_instantly()
	other.ammo = 0
	_input.reload_pressed = true
	other.tick(DT, _input)
	_input.reload_pressed = false
	for tick: int in 48:
		other.tick(DT, _input)
	assert_eq(other.ammo, _logic.ammo)
	assert_eq(other.state, _logic.state)


func test_sprint_prevents_interrupt_shot_and_has_authored_recovery() -> void:
	_data.sprint_to_fire_time = 0.1
	_input.sprinting = true
	_input.trigger_held = true
	_input.trigger_pressed = true
	assert_eq(_ticks(5), 0)
	_input.sprinting = false
	assert_eq(_ticks(5), 0)
	assert_eq(_ticks(1), 1)


func test_pump_cycle_cannot_be_bypassed_by_reload_interrupt() -> void:
	_input.trigger_pressed = true
	_input.trigger_held = true
	assert_eq(_logic.tick(DT, _input), 1)
	_input.reload_pressed = true
	assert_eq(_ticks(20), 0)
	_input.trigger_held = false
	_input.trigger_pressed = false
	_input.reload_pressed = false
	assert_false(_logic.is_reloading())
	_ticks(28)
	_logic.tick(DT, _input)
	assert_true(_logic.is_reloading())
