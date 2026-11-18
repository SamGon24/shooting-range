extends GutTest
## Pooled casings and muzzle smoke: bounded, recycled, timed in gameplay
## time, invisible to every hit query, and driven by each weapon's data.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const WEAPONS: Array[String] = [
	"halberd_rifle", "rill_smg", "foundry_lmg", "breakwater_shotgun", "longwatch_sniper",
	"wayline_pistol", "cairn_launcher", "latch_knife", "palisade_shield",
]
const BRASS: Color = Color(0.8, 0.62, 0.25)

var _world: Node3D
var _pool: CasingPool
var _smoke: MuzzleSmoke


func before_each() -> void:
	get_tree().paused = false
	_world = Node3D.new()
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child_autofree(_world)
	var floor_body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(40.0, 1.0, 40.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	floor_body.add_child(collider)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	_world.add_child(floor_body)
	_pool = CasingPool.new()
	_pool.capacity = 3
	_pool.lifetime_s = 1.0
	_world.add_child(_pool)
	_smoke = MuzzleSmoke.new()
	_smoke.emitters = 3
	_world.add_child(_smoke)


func after_each() -> void:
	get_tree().paused = false
	for action: StringName in [&"fire", &"reload", &"weapon_1", &"weapon_2"]:
		Input.action_release(action)


func _data(name: String) -> WeaponData:
	return load("res://weapons/data/%s.tres" % name) as WeaponData


func _port(at: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY, at)


# --- Weapon data ----------------------------------------------------------------


func test_every_gun_has_smoke_and_a_casing_except_where_none_belongs() -> void:
	for name: String in WEAPONS:
		var data: WeaponData = _data(name)
		var melee: bool = data.delivery != null and data.delivery.kind == DeliveryData.Kind.MELEE
		if melee:
			assert_eq(data.muzzle_smoke_particles, 0, name)
			assert_eq(data.casing_size, Vector3.ZERO, name)
			continue
		assert_gt(data.muzzle_smoke_particles, 0, "%s smokes" % name)
		if name == "cairn_launcher":
			assert_eq(data.casing_size, Vector3.ZERO, "a rocket tube ejects nothing")
			continue
		assert_gt(data.casing_size.z, data.casing_size.x, "%s casing is longer than thick" % name)
		assert_gt(data.casing_size.x, 0.0)
		if data.casing_eject_delay_s > 0.0:
			assert_lt(data.casing_eject_delay_s, data.shot_interval(), "%s throws before its next shot" % name)
	for manual: String in ["longwatch_sniper", "breakwater_shotgun"]:
		assert_gt(_data(manual).casing_eject_delay_s, 0.0, "%s throws when its action opens" % manual)
	for auto: String in ["halberd_rifle", "rill_smg", "foundry_lmg", "wayline_pistol"]:
		assert_eq(_data(auto).casing_eject_delay_s, 0.0, auto)


# --- Casing pool -----------------------------------------------------------------


func test_casings_are_bounded_recycled_oldest_first_and_allocate_nothing() -> void:
	var children: int = _pool.get_child_count()
	var nodes: int = get_tree().get_node_count()
	var used: Array[RigidBody3D] = []
	for shot: int in 5:
		used.append(_pool.eject(_port(Vector3(0.0, 1.0, 0.0)), Vector3(0.012, 0.012, 0.045), BRASS, Vector3.ZERO))
	assert_eq(_pool.active_count(), 3)
	assert_eq(_pool.get_child_count(), children)
	assert_eq(get_tree().get_node_count(), nodes)
	assert_eq(used[3], used[0])
	assert_eq(used[4], used[1])


func test_a_casing_takes_the_weapons_size_mass_and_port_direction() -> void:
	var rifle: RigidBody3D = _pool.eject(_port(Vector3(0.0, 1.0, 0.0)), Vector3(0.012, 0.012, 0.045), BRASS, Vector3.ZERO)
	assert_eq(_pool.get_casing_size(rifle), Vector3(0.012, 0.012, 0.045))
	assert_almost_eq(rifle.mass, 0.27 * 0.045, 0.0001)
	var shell: RigidBody3D = _pool.eject(_port(Vector3(0.0, 1.0, 0.0)), Vector3(0.02, 0.02, 0.07), Color(0.65, 0.12, 0.1), Vector3.ZERO)
	assert_gt(shell.mass, rifle.mass, "a shotgun shell is heavier")
	assert_gt(rifle.linear_velocity.x, 1.0, "thrown out of the +X side")
	assert_gt(rifle.linear_velocity.y, 0.5, "and upward")
	var moving := _pool.eject(_port(Vector3(0.0, 1.0, 0.0)), Vector3(0.012, 0.012, 0.045), BRASS, Vector3(0.0, 0.0, -5.0))
	# Port back and up.cross(outward) are collinear: both scatter draws
	# contribute to Z. Their sum is bounded by twice the per-draw range.
	assert_almost_eq(moving.linear_velocity.z, -5.0, 2.0 * _pool.eject_scatter + 0.001, "keeps the shooter's velocity plus both scatter terms")


func test_a_casing_falls_lands_and_is_put_away_in_gameplay_time() -> void:
	var body: RigidBody3D = _pool.eject(_port(Vector3(0.0, 1.0, 0.0)), Vector3(0.012, 0.012, 0.045), BRASS, Vector3.ZERO)
	await wait_physics_frames(40)
	assert_lt(body.global_position.y, 0.1, "on the floor")
	assert_gt(body.global_position.y, -0.05, "not through it")
	get_tree().paused = true
	await get_tree().create_timer(1.3, true).timeout
	get_tree().paused = false
	assert_true(_pool.is_active(body), "menu time does not age it")
	await wait_physics_frames(30)
	assert_false(_pool.is_active(body))
	assert_true(body.freeze)
	assert_eq(body.collision_layer, 0)
	assert_false(body.visible)


func test_projectiles_melee_and_blasts_never_see_a_casing() -> void:
	var body: RigidBody3D = _pool.eject(_port(Vector3(0.0, 1.0, 0.0)), Vector3(0.02, 0.02, 0.07), BRASS, Vector3.ZERO)
	var projectiles := ProjectileSystem.new()
	_world.add_child(projectiles)
	assert_eq(body.collision_layer & projectiles.collision_mask, 0)
	assert_eq(body.collision_layer & (1 | 4 | 8), 0, "outside every gameplay mask")
	assert_eq(body.collision_mask, 1, "scans only the world")


# --- Smoke -----------------------------------------------------------------------


func test_smoke_reuses_the_oldest_emitter_and_allocates_nothing() -> void:
	var nodes: int = get_tree().get_node_count()
	var used: Array[CPUParticles3D] = []
	for shot: int in 5:
		used.append(_smoke.puff(Vector3(0.0, 1.5, -1.0), Vector3.FORWARD, 4))
	assert_eq(get_tree().get_node_count(), nodes)
	assert_eq(used[3], used[0])
	assert_eq(used[4], used[1])
	assert_eq(used[0].amount, 4)
	assert_eq(used[0].global_position, Vector3(0.0, 1.5, -1.0))
	assert_true(used[0].emitting)
	assert_false(used[0].local_coords, "puffs stay where they were made")
	assert_null(_smoke.puff(Vector3.ZERO, Vector3.FORWARD, 0), "zero particles puffs nothing")
	assert_eq(_smoke.puff(Vector3.ZERO, Vector3.FORWARD, 99).amount, _smoke.max_particles_per_puff)


func test_smoke_quads_keep_their_particle_scale() -> void:
	# Without billboard_keep_scale every puff draws at the mesh's full 1 m
	# size and fills the screen (seen in a Movie Maker capture).
	var material := _smoke.get_emitters()[0].mesh.material as StandardMaterial3D
	assert_true(material.billboard_keep_scale)
	assert_eq(material.billboard_mode, BaseMaterial3D.BILLBOARD_PARTICLES)
	assert_lt(_smoke.puff_size, 0.5)


# --- Live weapon view --------------------------------------------------------------


func _player() -> Array:
	var player := PLAYER_SCENE.instantiate() as PlayerController
	(player.get_node("Weapons") as WeaponController).loadout_definition = preload("res://tests/fixtures/mvp_loadout.tres")
	_world.add_child(player)
	await wait_physics_frames(5)
	return [player, player.get_node("Weapons"), player.get_node("Head/CameraFeel/Camera/WeaponView")]


func _fire_once(weapons: WeaponController) -> void:
	Input.action_press(&"fire")
	await wait_physics_frames(2)
	Input.action_release(&"fire")
	await wait_physics_frames(1)


func test_each_rifle_shot_puffs_smoke_at_the_muzzle_and_ejects_one_casing() -> void:
	var made: Array = await _player()
	var weapons := made[1] as WeaponController
	var view := made[2] as WeaponView
	var casings: CasingPool = view.get_casing_pool()
	var smoke: MuzzleSmoke = view.get_muzzle_smoke()
	assert_not_null(casings)
	assert_not_null(smoke)
	assert_eq(casings.get_parent(), _world, "beside the player, outside the camera rig")
	assert_eq(smoke.get_parent(), _world)
	var emitting_before: int = smoke.get_emitters().filter(func(e: CPUParticles3D) -> bool: return e.emitting).size()
	await _fire_once(weapons)
	assert_eq(casings.active_count(), 1)
	var emitting: Array = smoke.get_emitters().filter(func(e: CPUParticles3D) -> bool: return e.emitting)
	assert_eq(emitting.size(), emitting_before + 1)
	var rifle: WeaponData = weapons.get_current_data()
	assert_eq((emitting[0] as CPUParticles3D).amount, rifle.muzzle_smoke_particles)
	var muzzle: Node3D = view.get_current_model().get_node("Muzzle")
	assert_lt((emitting[0] as CPUParticles3D).global_position.distance_to(muzzle.global_position), 0.2, "at the barrel")
	assert_eq(casings.get_casing_size(casings.get_bodies()[0]), rifle.casing_size)


func test_a_bolt_action_throws_its_casing_when_the_bolt_opens() -> void:
	var made: Array = await _player()
	var weapons := made[1] as WeaponController
	var view := made[2] as WeaponView
	weapons.request_switch(1)
	await wait_physics_frames(80)
	var sniper: WeaponData = weapons.get_current_data()
	assert_eq(sniper.weapon_class, WeaponTypes.Class.SNIPER)
	var casings: CasingPool = view.get_casing_pool()
	await _fire_once(weapons)
	assert_eq(casings.active_count(), 0, "not on the shot itself")
	await wait_physics_frames(ceili(sniper.casing_eject_delay_s * 60.0) + 4)
	assert_eq(casings.active_count(), 1, "thrown as the bolt opens")
	await wait_physics_frames(ceili(sniper.shot_interval() * 60.0))
	assert_eq(casings.active_count(), 1, "one casing per shot")


func test_a_casing_still_leaves_while_the_bolt_weapon_is_being_lowered() -> void:
	var made: Array = await _player()
	var weapons := made[1] as WeaponController
	var view := made[2] as WeaponView
	weapons.request_switch(1)
	await wait_physics_frames(80)
	var sniper: WeaponData = weapons.get_current_data()
	assert_lt(sniper.casing_eject_delay_s, sniper.lower_time, "the bolt opens before the weapon is away")
	await _fire_once(weapons)
	weapons.request_switch(0)
	await wait_physics_frames(80)
	assert_eq(view.get_casing_pool().active_count(), 1)


func test_firing_with_pools_leaves_the_shot_itself_untouched() -> void:
	var made: Array = await _player()
	var weapons := made[1] as WeaponController
	var projectiles := ProjectileSystem.new()
	_world.add_child(projectiles)
	var shots: Array[int] = []
	weapons.shot_fired.connect(func(_data: WeaponData) -> void: shots.append(1))
	var fired: Array[Vector3] = []
	projectiles.projectile_fired.connect(func(_slot: int, _origin: Vector3, velocity: Vector3, _spec: ProjectileSpec) -> void: fired.append(velocity))
	await _fire_once(weapons)
	assert_eq(shots.size(), 1)
	assert_eq(fired.size(), 1, "exactly one round, however many casings and puffs")
