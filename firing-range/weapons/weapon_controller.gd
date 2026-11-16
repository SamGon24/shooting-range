class_name WeaponController
extends Node
## The player's weapons: turns input into `WeaponInput`, runs the active
## weapon's `WeaponLogic` each physics tick, handles switching, and fires
## through the `ProjectileSystem`.
##
## Shots leave from the player's gameplay eye along the gameplay aim
## direction. The viewmodel, camera effects and sounds listen to the signals
## below and never feed anything back.

signal weapon_changed(data: WeaponData)
signal ammo_changed(ammo: int, magazine_size: int)
signal shot_fired(data: WeaponData)
signal dry_fired
signal reload_started(is_empty: bool, duration: float)
signal reload_finished
signal reload_cancelled

const GROUP: StringName = &"weapon_controller"

## Weapons carried, in slot order (slot 1, slot 2, ...).
@export var loadout: Array[WeaponData] = []
@export var player: PlayerController

## Where shots go. Found through the `ProjectileSystem` group if left unset.
var projectile_system: ProjectileSystem

var _logics: Array[WeaponLogic] = []
var _current: int = -1
## Slot the player asked to switch to, or -1.
var _pending: int = -1
var _input: WeaponInput = WeaponInput.new()
var _last_ammo: int = -1
var _warned_no_system: bool = false
## Fire and reload presses seen since the last physics tick.
var _fire_latched: bool = false
var _reload_latched: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	if player == null:
		push_error("WeaponController: `player` must be assigned.")
		set_physics_process(false)
		return
	for data: WeaponData in loadout:
		var logic := WeaponLogic.new(data)
		logic.fired.connect(_on_logic_fired.bind(logic))
		logic.dry_fired.connect(_on_logic_dry_fired.bind(logic))
		logic.reload_started.connect(_on_logic_reload_started.bind(logic))
		logic.reload_finished.connect(_on_logic_reload_finished.bind(logic))
		logic.reload_cancelled.connect(_on_logic_reload_cancelled.bind(logic))
		_logics.append(logic)
	if not _logics.is_empty():
		_current = 0
		_logics[0].equip_instantly()
		_announce_weapon.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	# Presses are caught as events and applied on the next physics tick. A
	# mouse wheel "press" lasts a single frame, and a quick click can start
	# and end between two ticks; polling in the tick would miss both.
	if event.is_action_pressed("weapon_next"):
		request_switch_relative(1)
	elif event.is_action_pressed("weapon_prev"):
		request_switch_relative(-1)
	elif event.is_action_pressed("fire"):
		_fire_latched = true
	elif event.is_action_pressed("reload"):
		_reload_latched = true


func _physics_process(delta: float) -> void:
	if _current < 0:
		return
	if Input.is_action_just_pressed("weapon_1"):
		request_switch(0)
	elif Input.is_action_just_pressed("weapon_2"):
		request_switch(1)

	_update_switch()

	var logic: WeaponLogic = _logics[_current]
	var controls_live: bool = _controls_live()
	# Edges come from the latches (real input events) or from polling (input
	# injected with Input.action_press, as tests and debug tools do).
	var fire_pressed: bool = _fire_latched or Input.is_action_just_pressed("fire")
	var reload_pressed: bool = _reload_latched or Input.is_action_just_pressed("reload")
	_fire_latched = false
	_reload_latched = false
	_input.trigger_pressed = controls_live and fire_pressed
	_input.trigger_held = controls_live and (fire_pressed or Input.is_action_pressed("fire"))
	_input.aim_held = controls_live and Input.is_action_pressed("aim")
	_input.reload_pressed = controls_live and reload_pressed
	_input.sprinting = player.is_sprinting

	var shots: int = logic.tick(delta, _input)
	for _shot: int in shots:
		_launch_projectile(logic.data)

	player.look_sensitivity_scale = lerpf(1.0, logic.data.ads_sensitivity_scale, logic.aim_progress)

	if logic.ammo != _last_ammo:
		_last_ammo = logic.ammo
		ammo_changed.emit(logic.ammo, logic.data.magazine_size)


# --- Public API ---


## Asks to switch to a loadout slot (0-based). The current weapon lowers
## first, then the new one raises.
func request_switch(slot: int) -> void:
	if slot < 0 or slot >= _logics.size():
		return
	if slot == _current and _pending == -1:
		return
	_pending = slot


## Switches to the next (+1) or previous (-1) weapon, wrapping around.
func request_switch_relative(step: int) -> void:
	if _logics.size() < 2:
		return
	var from: int = _pending if _pending != -1 else _current
	request_switch(posmod(from + step, _logics.size()))


func get_current_slot() -> int:
	return _current


func get_current_data() -> WeaponData:
	return _logics[_current].data if _current >= 0 else null


func get_current_logic() -> WeaponLogic:
	return _logics[_current] if _current >= 0 else null


## The logic for a loadout slot, e.g. to read a holstered weapon's ammo.
func get_logic(slot: int) -> WeaponLogic:
	return _logics[slot] if slot >= 0 and slot < _logics.size() else null


## Aim progress (0 hip, 1 aimed) blended between the last two physics ticks,
## for smooth visuals at any frame rate.
func get_aim_blend(fraction: float = 1.0) -> float:
	var logic: WeaponLogic = get_current_logic()
	if logic == null:
		return 0.0
	return lerpf(logic.previous_aim_progress, logic.aim_progress, fraction)


## Raise progress (0 put away, 1 up) blended between the last two ticks.
func get_raise_blend(fraction: float = 1.0) -> float:
	var logic: WeaponLogic = get_current_logic()
	if logic == null:
		return 0.0
	return lerpf(logic.previous_raise_progress, logic.raise_progress, fraction)


# --- Internals ---


## Weapon input is ignored until the mouse is captured, so the click that
## grabs the mouse does not also fire a shot.
func _controls_live() -> bool:
	if not player.mouse_look_enabled:
		return true
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _update_switch() -> void:
	if _pending == -1:
		return
	var logic: WeaponLogic = _logics[_current]
	if _pending == _current:
		# Switched back before the weapon was fully away: bring it up again.
		logic.start_raise()
		_pending = -1
		return
	if logic.state == WeaponLogic.State.HOLSTERED:
		_current = _pending
		_pending = -1
		_logics[_current].start_raise()
		_announce_weapon()
	else:
		logic.start_lower()


func _announce_weapon() -> void:
	var logic: WeaponLogic = _logics[_current]
	_last_ammo = logic.ammo
	weapon_changed.emit(logic.data)
	ammo_changed.emit(logic.ammo, logic.data.magazine_size)


func _launch_projectile(data: WeaponData) -> void:
	if projectile_system == null:
		projectile_system = get_tree().get_first_node_in_group(ProjectileSystem.GROUP) as ProjectileSystem
	if projectile_system == null:
		if not _warned_no_system:
			_warned_no_system = true
			push_warning("WeaponController: no ProjectileSystem in the scene; shots go nowhere.")
		return
	var direction: Vector3 = -player.get_aim_basis().z
	projectile_system.fire(player.get_eye_position(), direction, data.projectile)


func _on_logic_fired(logic: WeaponLogic) -> void:
	shot_fired.emit(logic.data)


func _on_logic_dry_fired(_logic: WeaponLogic) -> void:
	dry_fired.emit()


func _on_logic_reload_started(is_empty: bool, duration: float, _logic: WeaponLogic) -> void:
	reload_started.emit(is_empty, duration)


func _on_logic_reload_finished(_logic: WeaponLogic) -> void:
	reload_finished.emit()


func _on_logic_reload_cancelled(_logic: WeaponLogic) -> void:
	reload_cancelled.emit()
