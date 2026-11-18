class_name WeaponController
extends Node
## The player's weapons: turns input into `WeaponInput`, runs the active
## weapon's `WeaponLogic` each physics tick, handles switching, and fires
## through the `ProjectileSystem`.
##
## Shots leave a fixed sight-height below the gameplay eye, along the
## gameplay aim plus the equipped weapon's numerical zero angle. The viewmodel, camera effects and sounds listen to the signals
## below and never feed anything back.

signal weapon_changed(data: WeaponData)
signal ammo_changed(ammo: int, magazine_size: int)
signal shot_fired(data: WeaponData)
signal dry_fired
signal reload_started(is_empty: bool, duration: float)
signal reload_finished
signal reload_cancelled
signal shell_inserted(ammo: int)
## The player picked a different sight zero for the current weapon.
signal zero_changed(distance_m: float)

const GROUP: StringName = &"weapon_controller"

## Weapons carried, in slot order (slot 1, slot 2, ...).
@export var loadout: Array[WeaponData] = []
## Optional startup snapshot supplied before entering the tree.
var initial_builds: Array[WeaponBuild] = []
@export var loadout_definition: WeaponLoadout
@export var primary_catalog: WeaponCatalog
@export var secondary_catalog: WeaponCatalog
var _inventory: Dictionary[WeaponData, WeaponRuntime] = {}
var _replacement: WeaponData
var _replacement_slot: int = -1
var _builds: Array[WeaponBuild] = []
var _pending_attachments: Dictionary[WeaponData, Dictionary] = {}
@export var player: PlayerController

## Seed for recoil randomness. 0 picks a random seed; tests and captures
## set one to make bursts repeatable.
@export var random_seed: int = 0

## Where shots go. Found through the `ProjectileSystem` group if left unset.
var projectile_system: ProjectileSystem

var _logics: Array[WeaponLogic] = []
var _recoils: Array[RecoilLogic] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _current: int = -1
var _zero_angle: float = 0.0
## Slot the player asked to switch to, or -1.
var _pending: int = -1
var _input: WeaponInput = WeaponInput.new()
var _last_ammo: int = -1
var _warned_no_system: bool = false
## Fire and reload presses seen since the last physics tick.
var _fire_latched: bool = false
var _reload_latched: bool = false
var _zero_latched: bool = false
var _melee: MeleeSystem
var _guard: WeaponGuard


func _ready() -> void:
	shot_fired.connect(func(_data: WeaponData) -> void: GameInput.vibrate("fire"))
	reload_started.connect(func(_empty: bool, _duration: float) -> void: GameInput.vibrate("reload"))
	add_to_group(GROUP)
	if player == null:
		push_error("WeaponController: `player` must be assigned.")
		set_physics_process(false)
		return
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	_melee = MeleeSystem.new()
	add_child(_melee)
	_guard = WeaponGuard.new()
	add_child(_guard)
	var definitions: Array[WeaponData] = get_definitions()
	for definition: WeaponData in get_available_definitions():
		var runtime := WeaponRuntime.new(definition, _rng)
		for prepared: WeaponBuild in initial_builds:
			if prepared.base == definition:
				for attachment: AttachmentData in prepared.get_attachments():
					runtime.build.set_attachment(attachment.slot, attachment)
				runtime.logic.data = runtime.build.get_stats()
				runtime.logic.ammo = runtime.logic.data.magazine_size
				runtime.recoil.data = runtime.logic.data
		_inventory[definition] = runtime
		var logic: WeaponLogic = runtime.logic
		logic.fired.connect(_on_logic_fired.bind(logic))
		logic.dry_fired.connect(_on_logic_dry_fired.bind(logic))
		logic.reload_started.connect(_on_logic_reload_started.bind(logic))
		logic.reload_finished.connect(_on_logic_reload_finished.bind(logic))
		logic.reload_cancelled.connect(_on_logic_reload_cancelled.bind(logic))
		logic.shell_inserted.connect(_on_logic_shell_inserted)
	loadout.clear()
	for definition: WeaponData in definitions:
		var runtime: WeaponRuntime = _inventory[definition]
		_builds.append(runtime.build)
		_logics.append(runtime.logic)
		_recoils.append(runtime.recoil)
		loadout.append(runtime.logic.data)
	if not _logics.is_empty():
		_current = 0
		_logics[0].equip_instantly()
		_announce_weapon.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	# Presses are caught as events and applied on the next physics tick. A
	# mouse wheel "press" lasts a single frame, and a quick click can start
	# and end between two ticks; polling in the tick would miss both.
	if event.is_action_pressed("weapon_swap"):
		request_switch_relative(1)
	elif event.is_action_pressed("melee"):
		if get_current_data() != null and get_current_data().delivery.kind == DeliveryData.Kind.MELEE:
			_fire_latched = true
	elif event.is_action_pressed("weapon_next"):
		request_switch_relative(1)
	elif event.is_action_pressed("weapon_prev"):
		request_switch_relative(-1)
	elif event.is_action_pressed("fire"):
		_fire_latched = true
	elif event.is_action_pressed("reload"):
		_reload_latched = true
	elif event.is_action_pressed("zero_cycle") and not event.is_echo():
		_zero_latched = true


func _physics_process(delta: float) -> void:
	if _current < 0:
		return
	if Input.is_action_just_pressed("weapon_1"):
		request_switch(0)
	elif Input.is_action_just_pressed("weapon_2"):
		request_switch(1)

	_update_switch()
	_apply_pending_attachments()
	if _zero_latched or Input.is_action_just_pressed("zero_cycle"):
		_zero_latched = false
		if _controls_live():
			cycle_zero()

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
	_input.aim_held = controls_live and GameInput.held("aim", ViewSettings.toggle_ads)
	_input.reload_pressed = controls_live and reload_pressed
	_input.sprinting = player.is_sprinting

	var recoil: RecoilLogic = _recoils[_current]
	recoil.tick(delta)
	var shots: int = logic.tick(delta, _input)
	for _shot: int in shots:
		# The bullet leaves inside the current cone around the aim, before
		# this shot's kick moves it.
		var aim_basis: Basis = player.get_aim_basis()
		var aim: Vector3 = (-aim_basis.z).rotated(aim_basis.x, _zero_angle)
		_launch_projectile(logic.data, recoil.deviate(aim, recoil.spread_degrees(logic.aim_progress)))
		var kick: Vector2 = recoil.on_shot(logic.aim_progress)
		player.add_recoil(deg_to_rad(kick.y), -deg_to_rad(kick.x))
	player.recover_recoil(deg_to_rad(recoil.recovery_allowance(delta)))

	player.look_sensitivity_scale = lerpf(1.0, logic.data.ads_sensitivity_scale * ViewSettings.ads_sensitivity_multiplier, logic.aim_progress)
	_update_held_effects()

	if logic.ammo != _last_ammo:
		_last_ammo = logic.ammo
		ammo_changed.emit(logic.ammo, logic.data.magazine_size)


# --- Public API ---


## Asks to switch to a loadout slot (0-based). The current weapon lowers
## first, then the new one raises.
func request_switch(slot: int) -> void:
	if slot < 0 or slot >= _logics.size():
		return
	_replacement = null
	_replacement_slot = -1
	if slot == _current and _pending == -1 and _logics[_current].state != WeaponLogic.State.LOWERING:
		return
	_pending = slot


## Switches to the next (+1) or previous (-1) weapon, wrapping around.
func request_switch_relative(step: int) -> void:
	if _logics.size() < 2:
		return
	var from: int = _pending if _pending != -1 else _current
	request_switch(posmod(from + step, _logics.size()))


## Cached upward bore angle in radians, calibrated on equip for level aim.
func get_zero_angle() -> float:
	return _zero_angle


## The distance the current weapon's sights are zeroed for, metres.
func get_zero_distance() -> float:
	var data: WeaponData = get_current_data()
	var runtime: WeaponRuntime = _inventory.get(data.definition())
	if runtime != null and runtime.selected_zero_m > 0.0:
		return runtime.selected_zero_m
	return data.zero_distance_m


## Steps the current weapon to its next zero option, wrapping around. False
## when the weapon has fewer than two options. The zero is recalculated once
## here, never per frame, and only rounds fired afterwards use it.
func cycle_zero() -> bool:
	var options: PackedFloat32Array = get_current_data().zero_options
	if options.size() < 2:
		return false
	var current: float = get_zero_distance()
	var index: int = 0
	for candidate: int in options.size():
		if absf(options[candidate] - current) < absf(options[index] - current):
			index = candidate
	return request_zero(options[(index + 1) % options.size()])


## Selects a specific zero. Only the weapon's own options are accepted.
func request_zero(distance_m: float) -> bool:
	var data: WeaponData = get_current_data()
	var runtime: WeaponRuntime = _inventory.get(data.definition())
	if runtime == null or not data.zero_options.has(distance_m):
		return false
	runtime.selected_zero_m = distance_m
	_calibrate_zero()
	zero_changed.emit(distance_m)
	return true


func get_current_slot() -> int:
	return _current


func get_current_data() -> WeaponData:
	return _logics[_current].data if _current >= 0 else null


func get_current_logic() -> WeaponLogic:
	return _logics[_current] if _current >= 0 else null


## Restarts recoil randomness from `seed`, so a burst can be repeated exactly.
func reseed(seed: int) -> void:
	_rng.seed = seed


func get_current_recoil() -> RecoilLogic:
	return _recoils[_current] if _current >= 0 else null


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
	if _replacement != null:
		var old: WeaponLogic = _logics[_current]
		if old.state != WeaponLogic.State.HOLSTERED:
			old.start_lower()
			return
		var runtime: WeaponRuntime = _inventory[_replacement]
		_builds[_replacement_slot] = runtime.build
		_logics[_replacement_slot] = runtime.logic
		_recoils[_replacement_slot] = runtime.recoil
		loadout[_replacement_slot] = runtime.logic.data
		_current = _replacement_slot
		_replacement = null
		_replacement_slot = -1
		runtime.logic.start_raise()
		_announce_weapon()
		return
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
	_calibrate_zero()
	var logic: WeaponLogic = _logics[_current]
	_guard.configure(logic.data.guard)
	_update_held_effects()
	_last_ammo = logic.ammo
	weapon_changed.emit(logic.data)
	ammo_changed.emit(logic.ammo, logic.data.magazine_size)


func _calibrate_zero() -> void:
	if projectile_system == null:
		projectile_system = get_tree().get_first_node_in_group(ProjectileSystem.GROUP) as ProjectileSystem
	var density: float = projectile_system.air_density if projectile_system != null else ProjectileMath.SEA_LEVEL_AIR_DENSITY
	var data: WeaponData = get_current_data()
	if data.delivery != null and data.delivery.kind == DeliveryData.Kind.MELEE:
		_zero_angle = 0.0
		return
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	_zero_angle = SightZeroing.solve(data.projectile, get_zero_distance(), data.sight_height_m, gravity, density, 1.0 / float(Engine.physics_ticks_per_second))
	if is_nan(_zero_angle):
		_zero_angle = 0.0
		push_warning("WeaponController: sight zero is unreachable; using the uncalibrated bore.")


func _launch_projectile(data: WeaponData, direction: Vector3) -> void:
	if projectile_system == null:
		projectile_system = get_tree().get_first_node_in_group(ProjectileSystem.GROUP) as ProjectileSystem
	if projectile_system == null:
		if not _warned_no_system:
			_warned_no_system = true
			push_warning("WeaponController: no ProjectileSystem in the scene; shots go nowhere.")
		return
	var origin: Vector3 = player.get_eye_position() - player.get_aim_basis().y * data.sight_height_m
	if data.delivery != null and data.delivery.kind == DeliveryData.Kind.MELEE:
		data.delivery.launch(projectile_system, origin, direction, data.projectile, _rng, _melee, [_guard.get_rid()])
	elif data.delivery != null:
		data.delivery.launch(projectile_system, origin, direction, data.projectile, _rng)
	else:
		projectile_system.fire(origin, direction, data.projectile)


func _update_held_effects() -> void:
	var logic: WeaponLogic = get_current_logic()
	player.weapon_speed_scale = logic.data.movement_speed_scale if logic.state != WeaponLogic.State.HOLSTERED else 1.0
	if logic.data.guard != null:
		_guard.update_pose(player.get_eye_position(), player.get_aim_basis(), logic.state in [WeaponLogic.State.READY, WeaponLogic.State.FIRING])


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


func _on_logic_shell_inserted(ammo: int) -> void:
	shell_inserted.emit(ammo)


## Menu activation must not carry a buffered click into resumed gameplay.
func clear_input_latches() -> void:
	_fire_latched = false
	_reload_latched = false


func get_definitions() -> Array[WeaponData]:
	if not _logics.is_empty():
		var active: Array[WeaponData] = []
		for data: WeaponData in loadout:
			active.append(data.definition())
		return active
	if initial_builds.size() == 2:
		return [initial_builds[0].base, initial_builds[1].base]
	if loadout_definition != null:
		return loadout_definition.weapons()
	var definitions: Array[WeaponData] = []
	for data: WeaponData in loadout:
		definitions.append(data.definition())
	return definitions


## Presentation caches every offered gun once, without carrying more slots.
func get_available_definitions() -> Array[WeaponData]:
	var definitions: Array[WeaponData] = get_definitions()
	if primary_catalog != null:
		for definition: WeaponData in primary_catalog.primaries:
			if definition != null and not definitions.has(definition):
				definitions.append(definition)
	if secondary_catalog != null:
		for definition: WeaponData in secondary_catalog.secondaries:
			if definition != null and not definitions.has(definition):
				definitions.append(definition)
	return definitions


func get_primary_choices() -> Array[WeaponData]:
	var choices: Array[WeaponData] = []
	var other: WeaponData = loadout[1].definition() if loadout.size() > 1 else null
	var offered: Array[WeaponData] = primary_catalog.primaries if primary_catalog != null else get_available_definitions()
	for definition: WeaponData in offered:
		if definition != null and definition.role == WeaponTypes.Role.PRIMARY and definition.weapon_class <= WeaponTypes.Class.SHOTGUN and definition != other and not choices.has(definition):
			choices.append(definition)
	return choices


func get_primary_selection() -> WeaponData:
	return _replacement if _replacement_slot == 0 else (loadout[0].definition() if not loadout.is_empty() else null)


func request_primary(definition: WeaponData) -> bool:
	return _request_replacement(definition, 0, get_primary_choices())


func get_secondary_choices() -> Array[WeaponData]:
	var choices: Array[WeaponData] = []
	var offered: Array[WeaponData] = secondary_catalog.secondaries if secondary_catalog != null else get_available_definitions()
	for definition: WeaponData in offered:
		if definition != null and definition.role == WeaponTypes.Role.SECONDARY and definition.weapon_class >= WeaponTypes.Class.PISTOL and not choices.has(definition):
			choices.append(definition)
	return choices


func get_secondary_selection() -> WeaponData:
	return _replacement if _replacement_slot == 1 else (loadout[1].definition() if loadout.size() > 1 else null)


func request_secondary(definition: WeaponData) -> bool:
	return _request_replacement(definition, 1, get_secondary_choices())


func _request_replacement(definition: WeaponData, slot: int, choices: Array[WeaponData]) -> bool:
	if slot >= loadout.size() or not _inventory.has(definition) or not choices.has(definition):
		return false
	if definition == loadout[slot].definition():
		request_switch(slot)
		return true
	_replacement = definition
	_replacement_slot = slot
	_pending = -1
	return true


func get_build(slot: int) -> WeaponBuild:
	return _builds[slot] if slot >= 0 and slot < _builds.size() else null


func get_requested_attachment(slot: WeaponTypes.Slot) -> AttachmentData:
	if _current < 0:
		return null
	var definition: WeaponData = get_current_data().definition()
	if _pending_attachments.has(definition) and _pending_attachments[definition].has(slot):
		return _pending_attachments[definition][slot]
	return _builds[_current].get_attachment(slot)


func request_attachment(slot: WeaponTypes.Slot, attachment: AttachmentData) -> bool:
	if _current < 0 or not _builds[_current].can_attach(slot, attachment):
		return false
	if get_requested_attachment(slot) == attachment:
		return true
	var definition: WeaponData = get_current_data().definition()
	if not _pending_attachments.has(definition):
		_pending_attachments[definition] = {}
	_pending_attachments[definition][slot] = attachment
	return true


func _apply_pending_attachments() -> void:
	var definition: WeaponData = get_current_data().definition()
	if not _pending_attachments.has(definition):
		return
	var logic: WeaponLogic = _logics[_current]
	if logic.state not in [WeaponLogic.State.READY, WeaponLogic.State.FIRING] or logic.get_time_to_next_shot() > WeaponLogic.TIME_EPSILON:
		return
	var build: WeaponBuild = _builds[_current]
	for slot: int in _pending_attachments[definition]:
		build.set_attachment(slot as WeaponTypes.Slot, _pending_attachments[definition][slot])
	_pending_attachments.erase(definition)
	var computed: WeaponData = build.get_stats()
	if computed == logic.data:
		return
	logic.data = computed
	logic.ammo = mini(logic.ammo, computed.magazine_size)
	_recoils[_current].data = computed
	_recoils[_current].bloom = minf(_recoils[_current].bloom, computed.max_bloom_degrees)
	loadout[_current] = computed
	_announce_weapon()
