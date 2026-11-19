extends GutTest
## The player scene taking real hostile projectiles and blasts through the
## shared damage interface, then dying and respawning.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const TICK: float = 1.0 / 60.0

var _world: Node3D
var _player: PlayerController
var _health: PlayerHealth
var _weapons: WeaponController
var _system: ProjectileSystem
var _explosions: ExplosionSystem
var _spec: ProjectileSpec
var _damage: Array[Dictionary] = []


func before_each() -> void:
	_damage.clear()
	_world = Node3D.new()
	add_child_autofree(_world)
	var floor_body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200.0, 1.0, 200.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	floor_body.add_child(collider)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	_world.add_child(floor_body)
	_system = ProjectileSystem.new()
	_world.add_child(_system)
	_system.set_physics_process(false)
	_explosions = ExplosionSystem.new()
	_world.add_child(_explosions)
	_world.add_child(TargetHits.new())
	_player = PLAYER_SCENE.instantiate() as PlayerController
	(_player.get_node("Weapons") as WeaponController).loadout_definition = preload("res://tests/fixtures/mvp_loadout.tres")
	_world.add_child(_player)
	_health = _player.get_node("Health") as PlayerHealth
	_health.follow_range_setting = false
	_health.invulnerable = false
	_weapons = _player.get_node("Weapons") as WeaponController
	_health.damaged.connect(func(hit: ProjectileHit, zone: TargetSettings.Zone, amount: float, incoming: Vector3, applied: bool) -> void:
		_damage.append({"hit": hit, "zone": zone, "amount": amount, "incoming": incoming, "applied": applied}))
	_spec = (load("res://weapons/data/halberd_rifle.tres") as WeaponData).projectile.duplicate() as ProjectileSpec
	_spec.stats_eligible = false
	await wait_physics_frames(3)


func after_each() -> void:
	Input.action_release(&"fire")
	Input.action_release(&"apply_plate")


## Fires a hostile round from `offset` (relative to the point) at a world point.
func _shoot_at(point: Vector3, offset: Vector3, mask: int = ProjectileSystem.HOSTILE_MASK) -> void:
	_system.fire(point + offset, -offset, _spec, mask)
	for _tick: int in 10:
		_system.advance(TICK)


func _feet() -> Vector3:
	return _player.global_position


# --- Hit zones ---


func test_hostile_rounds_hit_head_torso_and_limbs_with_multipliers() -> void:
	var cases: Array = [
		[Vector3(0.0, 1.66, 0.0), TargetSettings.Zone.HEAD, 1.5],
		[Vector3(0.0, 1.2, 0.0), TargetSettings.Zone.TORSO, 1.0],
		[Vector3(0.11, 0.4, 0.0), TargetSettings.Zone.LIMB, 0.8],
		[Vector3(-0.29, 1.2, 0.0), TargetSettings.Zone.LIMB, 0.8],
	]
	_health.invulnerable = true
	for entry: Array in cases:
		_damage.clear()
		_shoot_at(_feet() + (entry[0] as Vector3), Vector3(0.0, 0.0, -30.0))
		assert_eq(_damage.size(), 1, "one hit at %s" % entry[0])
		assert_eq(_damage[0]["zone"], entry[1])
		var hit: ProjectileHit = _damage[0]["hit"]
		assert_eq(hit.source, DamageSource.Kind.BALLISTIC, "the source field reaches the player")
		assert_almost_eq(float(_damage[0]["amount"]), hit.damage * float(entry[2]), 0.001)


func test_headshot_breaks_armor_first() -> void:
	_shoot_at(_feet() + Vector3(0.0, 1.66, 0.0), Vector3(0.0, 0.0, -30.0))
	var amount: float = _damage[0]["amount"]
	assert_true(_damage[0]["applied"])
	assert_almost_eq(_health.vitals.armor, 150.0 - amount, 0.001, "armor takes the headshot")
	assert_eq(_health.vitals.health, 100.0)


func test_players_own_default_mask_never_reaches_the_zones() -> void:
	_shoot_at(_feet() + Vector3(0.0, 1.2, 0.0), Vector3(0.0, 0.0, -30.0), -1)
	assert_eq(_damage.size(), 0)


func test_zones_shrink_when_crouched() -> void:
	var standing: float = _health.zones[0].global_position.y
	Input.action_press(&"crouch")
	await wait_physics_frames(60)
	Input.action_release(&"crouch")
	assert_lt(_health.zones[0].global_position.y, standing - 0.5, "head zone drops with the crouch")
	_damage.clear()
	_health.invulnerable = true
	_shoot_at(_feet() + Vector3(0.0, 1.66, 0.0), Vector3(0.0, 0.0, -30.0))
	assert_eq(_damage.size(), 0, "a standing-height headshot passes over a crouched player")


func test_invulnerable_reports_the_hit_but_changes_nothing() -> void:
	_health.invulnerable = true
	_shoot_at(_feet() + Vector3(0.0, 1.2, 0.0), Vector3(0.0, 0.0, -30.0))
	assert_eq(_damage.size(), 1)
	assert_false(_damage[0]["applied"])
	assert_eq(_health.vitals.armor, 150.0)
	assert_eq(_health.vitals.health, 100.0)


func test_range_setting_drives_invulnerability_by_default() -> void:
	var before: bool = ViewSettings.range_invulnerable
	var other := PLAYER_SCENE.instantiate() as PlayerController
	other.position = Vector3(20.0, 0.0, 0.0)
	_world.add_child(other)
	var health := other.get_node("Health") as PlayerHealth
	ViewSettings.range_invulnerable = true
	assert_true(health.invulnerable)
	ViewSettings.range_invulnerable = false
	assert_false(health.invulnerable)
	ViewSettings.range_invulnerable = before


func test_damage_direction_comes_from_the_shooter() -> void:
	_health.invulnerable = true
	_shoot_at(_feet() + Vector3(0.0, 1.2, 0.0), Vector3(30.0, 0.0, 0.0))
	var angle: float = DamageDirection.screen_angle(_damage[0]["incoming"], _player.yaw)
	assert_almost_eq(angle, PI * 0.5, 0.01, "shooter on the right")


func test_splash_hits_the_torso_armor_first_with_falloff() -> void:
	var rocket := ProjectileSpec.new()
	rocket.muzzle_velocity = 120.0
	rocket.gravity_scale = 0.0
	rocket.damage = 0.0
	rocket.source = DamageSource.Kind.SPLASH
	rocket.explosion = ExplosionData.new()
	rocket.explosion.damage = 80.0
	rocket.explosion.arming_distance_m = 0.0
	var wall := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.0, 4.0, 0.2)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	wall.add_child(collider)
	wall.position = _feet() + Vector3(0.0, 1.0, -3.1)
	_world.add_child(wall)
	await wait_physics_frames(2)
	var blast := Vector3(0.0, 1.0, -3.0)
	var hit := ProjectileHit.new()
	hit.spec = rocket
	hit.position = _feet() + blast
	hit.normal = Vector3.BACK
	hit.travel_distance = 20.0
	_explosions.detonate(hit)
	assert_eq(_damage.size(), 1)
	assert_eq(_damage[0]["zone"], TargetSettings.Zone.TORSO)
	assert_eq((_damage[0]["hit"] as ProjectileHit).source, DamageSource.Kind.SPLASH)
	var expected: float = rocket.explosion.damage_at_distance(hit.position.distance_to(_health.get_torso_zone().global_position))
	assert_almost_eq(float(_damage[0]["amount"]), expected, 0.001)
	assert_lt(expected, 80.0, "falls off with distance")
	assert_almost_eq(_health.vitals.armor, 150.0 - expected, 0.001)
	assert_eq(_health.vitals.health, 100.0)
	assert_almost_eq(DamageDirection.screen_angle(_damage[0]["incoming"], _player.yaw), 0.0, 0.01, "blast in front")


func test_hostile_probe_round_reaches_the_player_from_its_bearing() -> void:
	var probe := HostileProbe.new()
	_world.add_child(probe)
	await wait_physics_frames(2)
	_health.invulnerable = true
	# From behind; a side shot would take the arm first.
	assert_gt(probe.fire_once(PI), -1)
	for _tick: int in 10:
		_system.advance(TICK)
	assert_eq(_damage.size(), 1)
	assert_eq(_damage[0]["zone"], TargetSettings.Zone.TORSO)
	assert_false((_damage[0]["hit"] as ProjectileHit).spec.stats_eligible, "never counts in range stats")
	assert_almost_eq(absf(DamageDirection.screen_angle(_damage[0]["incoming"], _player.yaw)), PI, 0.01, "from behind")


# --- Death and respawn ---


func _kill() -> void:
	_health.vitals.armor = 0.0
	var hit := ProjectileHit.new()
	hit.spec = _spec
	hit.damage = 500.0
	hit.velocity = Vector3(0, 0, 400)
	_health.receive_hit(hit, TargetSettings.Zone.TORSO)


func test_death_disables_input_zones_and_weapon() -> void:
	watch_signals(_health)
	_kill()
	assert_signal_emitted(_health, "died")
	assert_true(_health.is_dead())
	assert_false(_player.input_enabled)
	for zone: PlayerHitZone in _health.zones:
		assert_eq(zone.collision_layer, 0)
	await wait_physics_frames(60)
	assert_true(_weapons.is_stowed(), "the weapon goes away on death")


func test_respawn_resets_state_position_and_weapons() -> void:
	var spawn: Vector3 = _health.spawn_position
	_weapons.get_current_logic().ammo = 3
	_weapons.get_logic(1).ammo = 0
	_player.teleport(spawn + Vector3(5.0, 0.0, -8.0), 1.0)
	_health.vitals.spare_plates = 0
	watch_signals(_health)
	_kill()
	var ticks: int = roundi(_health.settings.reset_seconds * 60.0)
	await wait_physics_frames(ticks - 5)
	assert_true(_health.is_dead(), "still on the death screen")
	assert_gt(_health.respawn_time_left(), 0.0)
	await wait_physics_frames(10)
	assert_signal_emitted(_health, "respawned")
	assert_false(_health.is_dead())
	assert_eq(_health.vitals.health, 100.0)
	assert_eq(_health.vitals.armor, 150.0)
	assert_eq(_health.vitals.spare_plates, _health.settings.spare_plates)
	assert_true(_player.input_enabled)
	assert_almost_eq(_player.global_position.x, spawn.x, 0.01)
	assert_almost_eq(_player.global_position.z, spawn.z, 0.01)
	assert_almost_eq(_player.yaw, _health.spawn_yaw, 0.0001)
	assert_eq(_weapons.get_current_logic().ammo, _weapons.get_current_data().magazine_size)
	assert_eq(_weapons.get_logic(1).ammo, _weapons.get_logic(1).data.magazine_size)
	assert_eq(_weapons.get_current_logic().state, WeaponLogic.State.READY)
	for zone: PlayerHitZone in _health.zones:
		assert_eq(zone.collision_layer, PlayerHitZone.LAYER)


# --- Plates ---


func test_plate_button_holsters_inserts_and_raises() -> void:
	_health.vitals.armor = 20.0
	watch_signals(_health)
	Input.action_press(&"apply_plate")
	await wait_physics_frames(1)
	Input.action_release(&"apply_plate")
	assert_true(_health.plating)
	var lower: int = ceili(_weapons.get_current_data().lower_time * 60.0)
	var insert: int = roundi(_health.settings.plate_insert_seconds * 60.0)
	await wait_physics_frames(lower + insert + 4)
	assert_signal_emitted(_health, "plate_applied")
	assert_eq(_health.vitals.armor, 50.0)
	assert_false(_health.plating)
	await wait_physics_frames(ceili(_weapons.get_current_data().raise_time * 60.0) + 2)
	assert_eq(_weapons.get_current_logic().state, WeaponLogic.State.READY, "weapon comes back up")


func test_fire_cancels_plating_without_using_a_plate() -> void:
	_health.vitals.armor = 0.0
	var spares: int = _health.vitals.spare_plates
	_health.request_plate()
	await wait_physics_frames(ceili(_weapons.get_current_data().lower_time * 60.0) + 10)
	assert_gt(_health.plate_progress(), 0.0)
	Input.action_press(&"fire")
	await wait_physics_frames(1)
	Input.action_release(&"fire")
	assert_false(_health.plating)
	assert_eq(_health.vitals.armor, 0.0)
	assert_eq(_health.vitals.spare_plates, spares)


func test_preload_setting_empties_the_vest_now_and_at_respawn() -> void:
	var before: bool = ViewSettings.preload_plates
	var other := PLAYER_SCENE.instantiate() as PlayerController
	other.position = Vector3(20.0, 0.0, 0.0)
	ViewSettings.preload_plates = false
	_world.add_child(other)
	var health := other.get_node("Health") as PlayerHealth
	assert_eq(health.vitals.armor, 0.0, "spawns with an empty vest")
	assert_eq(health.vitals.spare_plates, health.settings.spare_plates)
	assert_true(health.request_plate(), "plates can be inserted by hand")
	health.cancel_plate()
	ViewSettings.preload_plates = true
	assert_eq(health.vitals.armor, 150.0, "turning it back on refills the vest at once")
	ViewSettings.preload_plates = false
	assert_eq(health.vitals.armor, 0.0)
	health.vitals.apply_damage(500.0)
	await wait_physics_frames(roundi(health.settings.reset_seconds * 60.0) + 3)
	assert_false(health.is_dead())
	assert_eq(health.vitals.armor, 0.0, "respawn keeps the vest empty")
	ViewSettings.preload_plates = before


func test_unrelated_setting_changes_leave_the_vest_alone() -> void:
	var before: float = ViewSettings.fov_degrees
	_health.follow_range_setting = true
	_health.vitals.apply_damage(60.0)
	ViewSettings.fov_degrees = 80.0
	assert_eq(_health.vitals.armor, 90.0)
	ViewSettings.fov_degrees = before
	_health.follow_range_setting = false


func test_no_plating_with_a_full_vest() -> void:
	assert_false(_health.request_plate())
	assert_false(_health.plating)
