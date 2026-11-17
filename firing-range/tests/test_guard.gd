extends GutTest

var _world: Node3D
var _system: ProjectileSystem
var _guard: WeaponGuard
var _dummy: TargetDummy
var _feedback: RangeFeedback
var _hits: Array[ProjectileHit] = []


func before_each() -> void:
	_hits.clear()
	_world = Node3D.new()
	add_child_autofree(_world)
	_system = ProjectileSystem.new()
	_world.add_child(_system)
	_system.set_physics_process(false)
	_world.add_child(TargetHits.new())
	_feedback = RangeFeedback.new()
	_world.add_child(_feedback)
	_guard = WeaponGuard.new()
	_world.add_child(_guard)
	_guard.configure(GuardData.new())
	_guard.update_pose(Vector3(0, 1.63, 0), Basis.IDENTITY, true)
	_dummy = TargetDummy.new()
	_dummy.armor_plates = 0
	_dummy.position.z = 0.5
	_world.add_child(_dummy)
	_system.projectile_hit.connect(func(hit: ProjectileHit) -> void: _hits.append(hit))
	await wait_physics_frames(2)


func _shoot(x: float = 0.0, scoring: bool = true) -> void:
	var spec := ProjectileSpec.new()
	spec.damage = 32.0
	spec.muzzle_velocity = 200.0
	spec.gravity_scale = 0.0
	spec.stats_eligible = scoring
	_system.fire(Vector3(x, 1.63, -10), Vector3.BACK, spec)
	_system.advance(0.1)


func test_shield_stops_the_real_projectile_sweep_before_the_target() -> void:
	_shoot()
	assert_eq(_hits.size(), 1)
	assert_eq(_hits[0].collider, _guard)
	assert_eq(_dummy.state.health, 100.0)
	assert_eq(_system.get_active_count(), 0)
	assert_eq(_feedback.stats.hits, 0)


func test_lowered_guard_has_no_ghost_collision() -> void:
	_guard.update_pose(Vector3(0, 1.63, 0), Basis.IDENTITY, false)
	_shoot()
	assert_true(_hits[0].collider is TargetHitZone)
	assert_eq(_dummy.state.health, 52.0)


func test_shield_covers_its_front_and_turns_with_gameplay_aim() -> void:
	_guard.update_pose(Vector3(0, 1.63, 0), Basis(Vector3.UP, PI * 0.5), true)
	await wait_physics_frames(2)
	_shoot()
	assert_true(_hits[0].collider is TargetHitZone, "turning the shield exposes the old front")
	assert_eq(_dummy.state.health, 52.0)


func test_a_round_outside_the_shield_edge_can_reach_a_target() -> void:
	_dummy.position.x = 0.6
	await wait_physics_frames(2)
	_shoot(0.6)
	assert_eq(_dummy.state.health, 52.0)


func test_training_rounds_use_physics_without_polluting_player_stats() -> void:
	_guard.update_pose(Vector3(0, 1.63, 0), Basis.IDENTITY, false)
	_shoot(0.0, false)
	assert_eq(_dummy.state.health, 52.0)
	assert_eq(_feedback.stats.shots, 0)
	assert_eq(_feedback.stats.hits, 0)
	assert_eq(_system.get_active_shot_count(), 0)


func test_pose_updates_reuse_the_one_collider_and_match_authored_offset() -> void:
	var count: int = get_tree().get_node_count()
	var eye := Vector3(3, 2, -8)
	var aim := Basis(Vector3.UP, 0.6)
	for tick: int in 100:
		_guard.update_pose(eye, aim, true)
	assert_almost_eq(_guard.global_position, eye + aim * _guard.definition.eye_offset_m, Vector3.ONE * 0.000001)
	assert_eq(get_tree().get_node_count(), count)


func test_equipment_scales_walk_crouch_sprint_and_existing_horizontal_momentum() -> void:
	var floor_body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(250, 1, 250)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	floor_body.add_child(collider)
	floor_body.position.y = -0.5
	_world.add_child(floor_body)
	var player := load("res://player/player.tscn").instantiate() as PlayerController
	player.position.x = 20.0
	_world.add_child(player)
	await wait_physics_frames(3)
	var weapons := player.get_node("Weapons") as WeaponController
	weapons.get_current_data().movement_speed_scale = 0.8
	Input.action_press("move_forward")
	await wait_physics_frames(60)
	assert_almost_eq(player.get_horizontal_speed(), 3.6, 0.01)
	Input.action_press("crouch")
	await wait_physics_frames(60)
	assert_almost_eq(player.get_horizontal_speed(), 1.76, 0.01)
	Input.action_release("crouch")
	Input.action_press("sprint")
	await wait_physics_frames(60)
	assert_almost_eq(player.get_horizontal_speed(), 5.6, 0.01)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	player.weapon_speed_scale = 1.0
	player.velocity = Vector3(9, 2, 0)
	player.weapon_speed_scale = 0.8
	assert_almost_eq(player.velocity, Vector3(7.2, 2, 0), Vector3.ONE * 0.0001)
	player.weapon_speed_scale = 1.0
	assert_almost_eq(player.velocity, Vector3(7.2, 2, 0), Vector3.ONE * 0.0001)


func after_each() -> void:
	for action: StringName in [&"move_forward", &"crouch", &"sprint"]:
		Input.action_release(action)
