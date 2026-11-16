extends GutTest
## The cosmetic weapon view: it shows the right model, zooms the camera when
## aiming, and never changes where shots land.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ACTIONS: Array[StringName] = [&"fire", &"aim", &"weapon_1", &"weapon_2"]

var _world: Node3D
var _player: PlayerController
var _weapons: WeaponController
var _view: WeaponView
var _camera: Camera3D
var _hits: Array[ProjectileHit] = []


func before_each() -> void:
	_hits.clear()
	_world = Node3D.new()
	add_child_autofree(_world)
	_add_slab(Vector3(400.0, 1.0, 400.0), Vector3(0.0, -0.5, 0.0))
	_add_slab(Vector3(40.0, 40.0, 1.0), Vector3(0.0, 0.0, -30.5))

	var projectiles := ProjectileSystem.new()
	_world.add_child(projectiles)
	projectiles.projectile_hit.connect(func(hit: ProjectileHit) -> void: _hits.append(hit))

	_player = PLAYER_SCENE.instantiate() as PlayerController
	_world.add_child(_player)
	_weapons = _player.get_node("Weapons") as WeaponController
	_view = _player.get_node("Head/CameraFeel/Camera/WeaponView") as WeaponView
	_camera = _player.get_node("Head/CameraFeel/Camera") as Camera3D
	await wait_physics_frames(5)


func after_each() -> void:
	for action: StringName in ACTIONS:
		Input.action_release(action)


func _add_slab(size: Vector3, centre: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	body.position = centre
	_world.add_child(body)


func _seconds(seconds: float) -> int:
	return roundi(seconds * float(Engine.physics_ticks_per_second))


func test_every_weapon_has_a_viewmodel_with_a_muzzle() -> void:
	for data: WeaponData in _weapons.loadout:
		assert_not_null(data.viewmodel_scene, "%s has a viewmodel scene" % data.display_name)
		var model := data.viewmodel_scene.instantiate() as Node3D
		assert_not_null(model.get_node_or_null("Muzzle"), "%s viewmodel has a Muzzle marker" % data.display_name)
		assert_gt(model.find_children("*", "MeshInstance3D", true, false).size(), 3)
		model.free()


func test_shows_the_current_weapons_model_only() -> void:
	var rifle_model: Node3D = _view.get_current_model()
	assert_not_null(rifle_model)
	assert_true(_view.is_model_shown())

	_weapons.request_switch(1)
	await wait_physics_frames(_seconds(1.2))
	var sniper_model: Node3D = _view.get_current_model()
	assert_ne(sniper_model, rifle_model)
	assert_true(sniper_model.is_inside_tree(), "sniper model is in the scene")
	assert_false(rifle_model.is_inside_tree(), "rifle model is out of the scene")


func test_aiming_zooms_the_camera_to_the_weapons_ads_fov_and_back() -> void:
	var rifle: WeaponData = _weapons.loadout[0]
	var hip_fov: float = _camera.fov
	assert_almost_eq(hip_fov, ViewSettings.fov_degrees, 0.5)

	Input.action_press("aim")
	await wait_physics_frames(_seconds(rifle.ads_time * 0.5))
	assert_between(_camera.fov, rifle.ads_fov_degrees + 0.5, hip_fov - 0.5, "partway through the zoom")
	await wait_physics_frames(_seconds(rifle.ads_time) + 6)
	assert_almost_eq(_camera.fov, rifle.ads_fov_degrees, 0.05)

	Input.action_release("aim")
	await wait_physics_frames(_seconds(rifle.ads_time) + 6)
	assert_almost_eq(_camera.fov, hip_fov, 0.5)


func test_scoped_weapon_hides_its_model_when_fully_aimed() -> void:
	_weapons.request_switch(1)
	await wait_physics_frames(_seconds(1.2))
	var sniper: WeaponData = _weapons.get_current_data()
	assert_true(sniper.scoped)
	assert_false(_view.is_scope_view_active())

	Input.action_press("aim")
	await wait_physics_frames(_seconds(sniper.ads_time) + 6)
	assert_true(_view.is_scope_view_active())
	assert_false(_view.is_model_shown(), "the scope overlay replaces the model")
	assert_almost_eq(_camera.fov, sniper.ads_fov_degrees, 0.05)

	Input.action_release("aim")
	await wait_physics_frames(_seconds(sniper.ads_time) + 6)
	assert_true(_view.is_model_shown())


## Fires a one-second burst from a fixed pose and seed and returns where
## each round landed.
func _burst(seed: int) -> Array[Vector3]:
	_hits.clear()
	_player.teleport(Vector3.ZERO)
	await wait_physics_frames(_seconds(0.5))
	_weapons.reseed(seed)
	var logic: WeaponLogic = _weapons.get_current_logic()
	logic.ammo = logic.data.magazine_size
	Input.action_press("fire")
	await wait_physics_frames(_seconds(1.0))
	Input.action_release("fire")
	await wait_physics_frames(6)
	var points: Array[Vector3] = []
	for hit: ProjectileHit in _hits:
		points.append(hit.position)
	return points


func test_viewmodel_kick_never_changes_where_shots_land() -> void:
	var saw_kick: bool = false
	_hits.clear()
	Input.action_press("fire")
	for _tick: int in _seconds(0.5):
		await wait_physics_frames(1)
		if _view.get_kick() > 0.05:
			saw_kick = true
	Input.action_release("fire")
	assert_true(saw_kick, "the viewmodel visibly kicked")

	# Recoil moves the aim, but only through gameplay state: the same burst
	# lands in the same places with the weapon view removed entirely.
	var with_view: Array[Vector3] = await _burst(1234)
	_view.free()
	var without_view: Array[Vector3] = await _burst(1234)

	assert_gt(with_view.size(), 8)
	assert_eq(without_view.size(), with_view.size())
	if without_view.size() == with_view.size():
		for i: int in with_view.size():
			assert_almost_eq(without_view[i], with_view[i], Vector3.ONE * 0.0001, "round %d lands in the same place" % i)
