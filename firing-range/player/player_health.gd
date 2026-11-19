class_name PlayerHealth
extends Node3D
## Player hit zones, vitals, plate insertion, death and respawn.
##
## Damage arrives through the same `receive_hit(ProjectileHit)` interface as
## the dummies, with the hit's `source` intact. Runs after the player moves
## and before projectiles sweep, so zones are where the body is this tick.

signal damaged(hit: ProjectileHit, zone: TargetSettings.Zone, amount: float, incoming: Vector3, applied: bool)
signal died(hit: ProjectileHit, zone: TargetSettings.Zone)
signal respawned
signal plate_insert_started
signal plate_applied
signal plate_insert_cancelled

const GROUP: StringName = &"player_health"
const Zone = TargetSettings.Zone
## Head box size at any stance; the rest of the body shares the remaining
## height (legs take this fraction of it, the torso the rest).
const HEAD_SIZE: Vector3 = Vector3(0.26, 0.28, 0.26)
const LEG_FRACTION: float = 0.59
const TORSO_SIZE: Vector2 = Vector2(0.44, 0.26)
const ARM_SIZE: Vector2 = Vector2(0.13, 0.16)
const ARM_OFFSET: float = 0.29
const LEG_SIZE: Vector2 = Vector2(0.17, 0.20)
const LEG_OFFSET: float = 0.11

@export var settings: PlayerHealthSettings = preload("res://player/data/player_health_default.tres")
@export var player: PlayerController
@export var weapons: WeaponController
## When true, `invulnerable` mirrors the range's "Range invulnerability"
## setting. Game modes turn this off and set `invulnerable` themselves.
@export var follow_range_setting: bool = true

## Hits are still reported (direction indicator, rumble) but change nothing.
var invulnerable: bool = true
var vitals: PlayerVitals
var zones: Array[PlayerHitZone] = []
var last_plate_breaks: int = 0
var last_death_zone: Zone = Zone.TORSO
var last_death_source: DamageSource.Kind = DamageSource.Kind.BALLISTIC
var spawn_position: Vector3
var spawn_yaw: float = 0.0
## True from the plate button until the plate goes in or is cancelled,
## including the time the weapon takes to go away.
var plating: bool = false

var _rig: Node3D
var _layout_height: float = -1.0
var _plate_latched: bool = false
var _fire_latched: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	process_physics_priority = 10
	vitals = PlayerVitals.new(settings)
	_rig = Node3D.new()
	_rig.name = "HitZones"
	add_child(_rig)
	for kind: Zone in [Zone.HEAD, Zone.TORSO, Zone.LIMB, Zone.LIMB, Zone.LIMB, Zone.LIMB]:
		_add_zone(kind)
	if follow_range_setting:
		ViewSettings.changed.connect(_follow_setting)
		_follow_setting()
	damaged.connect(func(_h: ProjectileHit, _z: Zone, _a: float, _i: Vector3, _applied: bool) -> void: GameInput.vibrate("damage"))
	_capture_spawn.call_deferred()
	update_zones()


func _capture_spawn() -> void:
	if player != null:
		spawn_position = player.global_position
		spawn_yaw = player.yaw


func _follow_setting() -> void:
	if follow_range_setting:
		invulnerable = ViewSettings.range_invulnerable


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("apply_plate"):
		_plate_latched = true
	elif event.is_action_pressed("fire"):
		_fire_latched = true


func _physics_process(delta: float) -> void:
	var plate_pressed: bool = _plate_latched or Input.is_action_just_pressed("apply_plate")
	var fire_pressed: bool = _fire_latched or Input.is_action_just_pressed("fire")
	_plate_latched = false
	_fire_latched = false
	update_zones()
	if vitals.advance(delta):
		_respawn()
		return
	if vitals.dead:
		return
	_tick_plating(delta, plate_pressed, fire_pressed, Input.is_action_pressed("apply_plate"))


# --- Damage interface ---


func receive_hit(hit: ProjectileHit, zone: Zone) -> void:
	if vitals.dead:
		return
	var amount: float = hit.damage * _multiplier(zone, hit.spec)
	var incoming: Vector3 = DamageDirection.incoming(hit, player.get_eye_position() if player != null else global_position)
	var applied: bool = not invulnerable and amount > 0.0
	var plates_before: int = vitals.remaining_plates()
	if applied:
		vitals.apply_damage(amount)
	last_plate_breaks = plates_before - vitals.remaining_plates()
	damaged.emit(hit, zone, amount, incoming, applied)
	if vitals.dead:
		_die(hit, zone)


func _multiplier(zone: Zone, spec: ProjectileSpec) -> float:
	if spec == null:
		return settings.head_multiplier if zone == Zone.HEAD else (settings.limb_multiplier if zone == Zone.LIMB else settings.torso_multiplier)
	return settings.multiplier(zone, spec)


func is_dead() -> bool:
	return vitals.dead


## Seconds left on the death screen, or 0 while alive.
func respawn_time_left() -> float:
	return maxf(settings.reset_seconds - vitals.down_time, 0.0) if vitals.dead else 0.0


func get_torso_zone() -> PlayerHitZone:
	return zones[1]


# --- Plates ---


## Starts a plate insert, as the plate button does.
func request_plate() -> bool:
	if plating or vitals.dead or not vitals.can_insert_plate():
		return false
	plating = true
	if weapons != null:
		weapons.set_stowed(true)
	plate_insert_started.emit()
	return true


func cancel_plate() -> void:
	if not plating:
		return
	plating = false
	vitals.cancel_insert()
	if weapons != null and not vitals.dead:
		weapons.set_stowed(false)
	plate_insert_cancelled.emit()


## 0..1 while a plate is going in, 0 otherwise (including while the weapon
## is still being put away). Cosmetic views read this.
func plate_progress() -> float:
	return vitals.insert_progress()


func _tick_plating(delta: float, plate_pressed: bool, fire_pressed: bool, plate_held: bool) -> void:
	if plate_pressed and not plating:
		request_plate()
	if not plating:
		return
	if fire_pressed:
		cancel_plate()
		return
	if weapons != null and not weapons.is_stowed():
		return
	if not vitals.inserting and not vitals.begin_insert():
		_finish_plating()
		return
	if vitals.advance_insert(delta):
		plate_applied.emit()
		# Holding the button chains the next plate without raising the weapon.
		if not (plate_held and vitals.can_insert_plate()):
			_finish_plating()


func _finish_plating() -> void:
	plating = false
	vitals.cancel_insert()
	if weapons != null:
		weapons.set_stowed(false)


# --- Death and respawn ---


func _die(hit: ProjectileHit, zone: Zone) -> void:
	last_death_zone = zone
	last_death_source = hit.source
	if plating:
		plating = false
		vitals.cancel_insert()
		plate_insert_cancelled.emit()
	_set_hittable(false)
	if weapons != null:
		weapons.set_stowed(true)
	if player != null:
		player.input_enabled = false
	died.emit(hit, zone)


func _respawn() -> void:
	if player != null:
		player.teleport(spawn_position, spawn_yaw)
		player.input_enabled = true
	if weapons != null:
		weapons.reset_for_respawn()
	_set_hittable(true)
	update_zones()
	respawned.emit()


func _set_hittable(enabled: bool) -> void:
	for zone: PlayerHitZone in zones:
		zone.collision_layer = PlayerHitZone.LAYER if enabled else 0


# --- Zone layout ---


## Places the zones for the player's current height and facing.
func update_zones() -> void:
	if player == null:
		return
	_rig.rotation = Vector3(0.0, player.yaw, 0.0)
	var height: float = player.get_height()
	if is_equal_approx(height, _layout_height):
		return
	_layout_height = height
	var body: float = maxf(height - HEAD_SIZE.y, 0.2)
	var legs: float = body * LEG_FRACTION
	var torso: float = body - legs
	_place(zones[0], HEAD_SIZE, Vector3(0.0, height - HEAD_SIZE.y * 0.5, 0.0))
	_place(zones[1], Vector3(TORSO_SIZE.x, torso, TORSO_SIZE.y), Vector3(0.0, legs + torso * 0.5, 0.0))
	for index: int in 2:
		var side: float = -1.0 if index == 0 else 1.0
		_place(zones[2 + index], Vector3(ARM_SIZE.x, torso, ARM_SIZE.y), Vector3(side * ARM_OFFSET, legs + torso * 0.5, 0.0))
		_place(zones[4 + index], Vector3(LEG_SIZE.x, legs, LEG_SIZE.y), Vector3(side * LEG_OFFSET, legs * 0.5, 0.0))


func _place(zone: PlayerHitZone, size: Vector3, centre: Vector3) -> void:
	((zone.get_child(0) as CollisionShape3D).shape as BoxShape3D).size = size
	zone.position = centre


func _add_zone(kind: Zone) -> void:
	var body := PlayerHitZone.new()
	body.name = ["Head", "Torso", "Limb"][kind]
	body.zone = kind
	body.health = self
	body.collision_layer = PlayerHitZone.LAYER
	body.collision_mask = 0
	body.sync_to_physics = false
	var collider := CollisionShape3D.new()
	collider.shape = BoxShape3D.new()
	body.add_child(collider)
	_rig.add_child(body, true)
	zones.append(body)
