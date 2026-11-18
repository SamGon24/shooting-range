extends GutTest
## The Longwatch sights can be zeroed for 100, 200 or 300 m with the zero
## key. The choice moves only the aim, is recalculated once per change and
## belongs to the weapon.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ACTIONS: Array[StringName] = [&"fire", &"aim", &"zero_cycle", &"weapon_1", &"weapon_2"]
const TICK: float = 1.0 / 60.0

var _world: Node3D
var _player: PlayerController
var _weapons: WeaponController
var _projectiles: ProjectileSystem
var _hits: Array[ProjectileHit] = []
var _rifle: WeaponData
var _sniper: WeaponData


func before_each() -> void:
	_hits.clear()
	_world = Node3D.new()
	add_child_autofree(_world)
	_add_slab(Vector3(800.0, 1.0, 800.0), Vector3(0.0, -0.5, 0.0))
	_projectiles = ProjectileSystem.new()
	_world.add_child(_projectiles)
	_projectiles.projectile_hit.connect(func(hit: ProjectileHit) -> void: _hits.append(hit))
	_player = PLAYER_SCENE.instantiate() as PlayerController
	(_player.get_node("Weapons") as WeaponController).loadout_definition = preload("res://tests/fixtures/mvp_loadout.tres")
	_world.add_child(_player)
	_weapons = _player.get_node("Weapons") as WeaponController
	_rifle = _weapons.loadout[0]
	_sniper = _weapons.loadout[1]
	_weapons.reseed(7)
	await wait_physics_frames(5)


func after_each() -> void:
	for action: StringName in ACTIONS:
		Input.action_release(action)


func _add_slab(size: Vector3, centre: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	body.position = centre
	_world.add_child(body)
	return body


func _equip_sniper() -> void:
	_weapons.request_switch(1)
	await wait_physics_frames(80)


func _expected_angle(distance: float) -> float:
	return SightZeroing.solve(_sniper.projectile, distance, _sniper.sight_height_m, 9.81, _projectiles.air_density, TICK)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await wait_physics_frames(2)
	Input.action_release(action)
	await wait_physics_frames(2)


func test_only_the_sniper_offers_zero_options() -> void:
	assert_eq(_sniper.zero_options, PackedFloat32Array([100.0, 200.0, 300.0]))
	assert_true(_sniper.zero_options.has(_sniper.zero_distance_m), "starts on its own default")
	for name: String in ["halberd_rifle", "rill_smg", "foundry_lmg", "breakwater_shotgun", "wayline_pistol", "cairn_launcher", "latch_knife", "palisade_shield"]:
		assert_true((load("res://weapons/data/%s.tres" % name) as WeaponData).zero_options.is_empty(), name)


func test_the_key_cycles_100_200_300_and_wraps_with_the_matching_angle() -> void:
	await _equip_sniper()
	assert_eq(_weapons.get_zero_distance(), 100.0)
	assert_almost_eq(_weapons.get_zero_angle(), _expected_angle(100.0), 0.000001)
	var seen: Array[float] = []
	var changes: Array[float] = []
	_weapons.zero_changed.connect(func(distance: float) -> void: changes.append(distance))
	for press: int in 4:
		await _tap(&"zero_cycle")
		seen.append(_weapons.get_zero_distance())
		assert_almost_eq(_weapons.get_zero_angle(), _expected_angle(_weapons.get_zero_distance()), 0.000001)
	assert_eq(seen, [200.0, 300.0, 100.0, 200.0] as Array[float])
	assert_eq(changes, [200.0, 300.0, 100.0, 200.0] as Array[float])
	assert_gt(_expected_angle(300.0), _expected_angle(200.0))
	assert_gt(_expected_angle(200.0), _expected_angle(100.0))


func test_real_rounds_hit_the_point_of_aim_at_the_selected_zero() -> void:
	await _equip_sniper()
	var eye: Vector3 = _player.get_eye_position()
	var wall: StaticBody3D = _add_slab(Vector3(20.0, 20.0, 1.0), Vector3(eye.x, eye.y, eye.z - 200.5))
	var heights: Dictionary = {}
	for distance: float in [100.0, 200.0]:
		_weapons.request_zero(distance)
		_hits.clear()
		_projectiles.fire(eye - Vector3.UP * _sniper.sight_height_m, (Vector3.FORWARD).rotated(Vector3.RIGHT, _weapons.get_zero_angle()), _sniper.projectile)
		await wait_physics_frames(60)
		assert_eq(_hits.size(), 1, "zero %d" % int(distance))
		heights[distance] = _hits[0].position.y - eye.y
	assert_almost_eq(heights[200.0], 0.0, 0.03, "on the aim point at 200 m with the 200 m zero")
	assert_lt(heights[100.0], heights[200.0] - 0.04, "a 100 m zero lands about 7 cm lower at 200 m")
	wall.free()


func test_each_weapon_keeps_its_own_choice_through_switching_and_attachments() -> void:
	await _equip_sniper()
	await _tap(&"zero_cycle")
	assert_eq(_weapons.get_zero_distance(), 200.0)
	assert_true(_weapons.request_attachment(WeaponTypes.Slot.STOCK, load("res://weapons/attachments/data/brace.tres") as AttachmentData))
	await wait_physics_frames(10)
	assert_eq(_weapons.get_zero_distance(), 200.0, "rebuilding the stats keeps the zero")
	assert_almost_eq(_weapons.get_zero_angle(), _expected_angle(200.0), 0.000001)
	_weapons.request_switch(0)
	await wait_physics_frames(80)
	assert_eq(_weapons.get_zero_distance(), 100.0, "the rifle keeps its fixed zero")
	assert_false(_weapons.cycle_zero(), "no options, nothing to cycle")
	await _tap(&"zero_cycle")
	assert_eq(_weapons.get_zero_distance(), 100.0)
	_weapons.request_switch(1)
	await wait_physics_frames(80)
	assert_eq(_weapons.get_zero_distance(), 200.0, "the sniper remembers its zero")


func test_only_listed_distances_are_accepted() -> void:
	await _equip_sniper()
	var angle: float = _weapons.get_zero_angle()
	assert_false(_weapons.request_zero(150.0))
	assert_false(_weapons.request_zero(0.0))
	assert_eq(_weapons.get_zero_distance(), 100.0)
	assert_eq(_weapons.get_zero_angle(), angle)
	assert_true(_weapons.request_zero(300.0))
	assert_eq(_weapons.get_zero_distance(), 300.0)


func test_the_hud_shows_the_zero_only_for_adjustable_weapons() -> void:
	var hud := (preload("res://ui/hud.tscn")).instantiate() as Hud
	_world.add_child(hud)
	await wait_physics_frames(4)
	assert_eq(hud.get_weapon_name_text(), _rifle.display_name)
	assert_eq(hud.get_zero_text(), "")
	await _equip_sniper()
	assert_eq(hud.get_weapon_name_text(), _sniper.display_name, "the name label is unchanged")
	assert_eq(hud.get_zero_text(), "ZERO 100 m  [Z]")
	await _tap(&"zero_cycle")
	assert_eq(hud.get_zero_text(), "ZERO 200 m  [Z]")
	_weapons.request_switch(0)
	await wait_physics_frames(80)
	assert_eq(hud.get_zero_text(), "")
