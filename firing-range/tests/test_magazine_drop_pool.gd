extends GutTest
## Pooled physics magazines: bounded, recycled oldest-first, sized from the
## copied meshes, timed out in gameplay time, and invisible to every hit
## query.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const EXTENDED_MAG: PackedScene = preload("res://weapons/attachments/parts/extended_mag.tscn")

var _world: Node3D
var _pool: MagazineDropPool
var _part: MeshInstance3D
var _mount: Marker3D


func before_each() -> void:
	get_tree().paused = false
	_world = Node3D.new()
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child_autofree(_world)
	_add_box(Vector3(40.0, 1.0, 40.0), Vector3(0.0, -0.5, 0.0))
	_pool = MagazineDropPool.new()
	_pool.capacity = 3
	_pool.lifetime_s = 1.0
	_world.add_child(_pool)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.13, 0.055)
	_part = MeshInstance3D.new()
	_part.mesh = mesh
	_part.position = Vector3(0.0, 1.5, 0.0)
	_world.add_child(_part)
	_mount = Marker3D.new()
	_mount.position = Vector3(0.0, 1.565, 0.0)
	_world.add_child(_mount)


func after_each() -> void:
	get_tree().paused = false


func _add_box(size: Vector3, centre: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	body.position = centre
	_world.add_child(body)
	return body


func test_bounded_and_recycles_the_oldest_without_new_nodes() -> void:
	var children: int = _pool.get_child_count()
	var used: Array[RigidBody3D] = []
	for drop: int in 5:
		used.append(_pool.release(_part, null, Vector3.ZERO))
	assert_eq(_pool.active_count(), 3)
	assert_eq(_pool.get_child_count(), children)
	assert_eq(used[3], used[0], "fourth release reuses the oldest")
	assert_eq(used[4], used[1])
	assert_eq(_pool.get_bodies().size(), 3)


func test_copies_the_part_and_its_attachment_and_fits_the_collider() -> void:
	var extended := EXTENDED_MAG.instantiate() as Node3D
	_mount.add_child(extended)
	var body: RigidBody3D = _pool.release(_part, _mount, Vector3.ZERO)
	var meshes: int = 0
	for child: Node in body.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			meshes += 1
	assert_eq(meshes, 2, "native magazine plus the extended body")
	var size: Vector3 = _pool.get_collision_size(body)
	assert_almost_eq(size.x, 0.04, 0.0001, "widest of the two")
	assert_gt(size.y, 0.13, "covers both pieces")
	assert_almost_eq(body.global_position.distance_to(_part.global_position), 0.0, 0.0001)
	var bare: RigidBody3D = _pool.release(_part, null, Vector3.ZERO)
	assert_almost_eq(_pool.get_collision_size(bare).y, 0.13, 0.0001)


func test_falls_inherits_velocity_and_settles_on_the_ground() -> void:
	var body: RigidBody3D = _pool.release(_part, null, Vector3(2.0, 0.0, 0.0))
	assert_almost_eq(body.linear_velocity.x, 2.0, 0.0001)
	assert_lt(body.linear_velocity.y, 0.0, "pushed downward")
	await wait_physics_frames(50)
	assert_lt(body.global_position.y, 0.2, "on the floor")
	assert_gt(body.global_position.y, -0.05, "not through it")
	assert_gt(body.global_position.x, 0.2, "carried along")


func test_expires_after_its_lifetime_in_gameplay_time() -> void:
	var body: RigidBody3D = _pool.release(_part, null, Vector3.ZERO)
	await wait_physics_frames(30)
	get_tree().paused = true
	await get_tree().create_timer(1.2, true).timeout
	get_tree().paused = false
	assert_true(_pool.is_active(body), "paused time does not count")
	await wait_physics_frames(35)
	assert_false(_pool.is_active(body))
	assert_true(body.freeze)
	assert_eq(body.collision_layer, 0)
	assert_false(body.visible)
	assert_eq(_pool.active_count(), 0)


func test_projectiles_and_blasts_never_see_a_dropped_magazine() -> void:
	var projectiles := ProjectileSystem.new()
	_world.add_child(projectiles)
	var wall: StaticBody3D = _add_box(Vector3(4.0, 4.0, 0.5), Vector3(0.0, 1.0, -6.0))
	_part.position = Vector3(0.0, 1.0, -3.0)
	var body: RigidBody3D = _pool.release(_part, null, Vector3.ZERO)
	body.gravity_scale = 0.0
	body.linear_velocity = Vector3.ZERO
	assert_eq(body.collision_layer & projectiles.collision_mask, 0)
	assert_eq(body.collision_layer & (1 | 4 | 8), 0, "outside the melee and blast masks")
	var hits: Array[ProjectileHit] = []
	projectiles.projectile_hit.connect(func(hit: ProjectileHit) -> void: hits.append(hit))
	var spec := ProjectileSpec.new()
	spec.muzzle_velocity = 300.0
	spec.gravity_scale = 0.0
	projectiles.fire(Vector3(0.0, 1.0, 0.0), Vector3.FORWARD, spec)
	await wait_physics_frames(5)
	assert_eq(hits.size(), 1)
	assert_eq(hits[0].collider, wall, "the round passes the magazine and hits the wall")


func test_real_reloads_drop_one_magazine_each() -> void:
	var player := PLAYER_SCENE.instantiate() as PlayerController
	_world.add_child(player)
	await wait_physics_frames(5)
	var view := player.get_node("Head/CameraFeel/Camera/WeaponView") as WeaponView
	var weapons := player.get_node("Weapons") as WeaponController
	var pool: MagazineDropPool = view.get_drop_pool()
	assert_not_null(pool)
	assert_eq(pool.get_parent(), _world, "beside the player, outside the camera rig")
	var rifle: WeaponData = weapons.get_current_data()
	var released: Array[Node3D] = []
	view.get_animator().copy_released.connect(func(part: Node3D, _follower: Node3D) -> void: released.append(part))
	weapons.get_current_logic().ammo = 4
	Input.action_press(&"reload")
	await wait_physics_frames(1)
	Input.action_release(&"reload")
	await wait_physics_frames(ceili(rifle.reload_tactical_time * 60.0) + 3)
	assert_eq(pool.active_count(), 1, "a tactical reload drops its magazine")
	weapons.get_current_logic().ammo = 0
	Input.action_press(&"reload")
	await wait_physics_frames(1)
	Input.action_release(&"reload")
	await wait_physics_frames(ceili(rifle.reload_empty_time * 60.0) + 3)
	assert_eq(released.size(), 2, "an empty reload drops one too")
	# Together the two reloads outlast the default lifetime, so the first
	# magazine may already be put away.
	assert_between(pool.active_count(), 1, 2)
	assert_lte(pool.active_count(), pool.capacity)
