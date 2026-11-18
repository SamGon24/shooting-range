extends GutTest
## Corpses are solid to bullets: a round stops on a dead dummy's parts and
## shoves them, but a corpse takes no damage and never scores.

const EYE: Vector3 = Vector3(0.0, 1.2, 0.0)

var _world: Node3D
var _projectiles: ProjectileSystem
var _feedback: RangeFeedback
var _dummy: TargetDummy
var _wall: StaticBody3D
var _hits: Array[ProjectileHit] = []
var _spec: ProjectileSpec


func before_each() -> void:
	_hits.clear()
	_world = Node3D.new()
	add_child_autofree(_world)
	_projectiles = ProjectileSystem.new()
	_world.add_child(_projectiles)
	_projectiles.projectile_hit.connect(func(hit: ProjectileHit) -> void: _hits.append(hit))
	_world.add_child(TargetHits.new())
	_feedback = RangeFeedback.new()
	_world.add_child(_feedback)
	_wall = StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(10.0, 10.0, 0.5)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	_wall.add_child(collider)
	_wall.position = Vector3(0.0, 2.0, -20.0)
	_world.add_child(_wall)
	_dummy = TargetDummy.new()
	_dummy.position = Vector3(0.0, 0.0, -8.0)
	_world.add_child(_dummy)
	_spec = ProjectileSpec.new()
	_spec.muzzle_velocity = 600.0
	_spec.gravity_scale = 0.0
	_spec.mass_grams = 10.9
	_spec.damage = 400.0
	await wait_physics_frames(3)


func _fire_at_torso() -> void:
	_projectiles.fire(EYE, Vector3.FORWARD, _spec)
	await wait_physics_frames(8)


func test_a_round_stops_on_the_corpse_and_pushes_it() -> void:
	await _fire_at_torso()
	assert_eq(_hits.size(), 1)
	assert_true(_dummy.state.dead, "the first round killed it")
	_hits.clear()
	var torso: RigidBody3D = _dummy.ragdoll.parts[1]
	var before: Vector3 = torso.linear_velocity
	var spec := ProjectileSpec.new()
	spec.muzzle_velocity = 900.0
	spec.gravity_scale = 0.0
	spec.mass_grams = 50.0
	spec.damage = 50.0
	_projectiles.fire(Vector3(0.0, torso.global_position.y, 0.0), Vector3.FORWARD, spec)
	await wait_physics_frames(8)
	assert_eq(_hits.size(), 1)
	assert_true(_hits[0].collider is RagdollPart, "stopped on a corpse part, not the wall")
	assert_true(_dummy.ragdoll.parts.has(_hits[0].collider))
	assert_lt((_hits[0].collider as RigidBody3D).linear_velocity.z, before.z - 0.2, "shoved downrange")


func test_a_corpse_takes_no_damage_and_never_scores() -> void:
	await _fire_at_torso()
	var health: float = _dummy.state.health
	var armor: float = _dummy.state.armor
	var damaged: Array[bool] = []
	_dummy.damaged.connect(func(_hit: ProjectileHit, _zone: TargetSettings.Zone, _amount: float) -> void: damaged.append(true))
	var stats_before: Array[int] = [_feedback.stats.shots, _feedback.stats.hits, _feedback.stats.headshots]
	_hits.clear()
	_projectiles.fire(EYE, Vector3.FORWARD, _spec)
	await wait_physics_frames(8)
	assert_true(_hits[0].collider is RagdollPart)
	assert_eq(_dummy.state.health, health)
	assert_eq(_dummy.state.armor, armor)
	assert_true(damaged.is_empty(), "no damage signal")
	assert_eq(_feedback.stats.shots, stats_before[0] + 1, "the shot is counted")
	assert_eq(_feedback.stats.hits, stats_before[1], "but a corpse hit is a miss")
	assert_eq(_feedback.stats.headshots, stats_before[2])


func test_rounds_pass_through_once_the_dummy_has_reset() -> void:
	await _fire_at_torso()
	_dummy.advance(3.0)
	assert_false(_dummy.state.dead)
	_hits.clear()
	_dummy.set_physics_process(false)
	for part: RigidBody3D in _dummy.ragdoll.parts:
		assert_eq(part.collision_layer, 0, "parked parts are off every layer")
	_projectiles.fire(Vector3(0.0, 4.0, 0.0), Vector3.FORWARD, _spec)
	await wait_physics_frames(8)
	assert_eq(_hits.size(), 1)
	assert_eq(_hits[0].collider, _wall, "above the dummy the round reaches the wall")


func test_a_hit_on_an_inactive_part_does_nothing() -> void:
	var part: RagdollPart = _dummy.ragdoll.parts[1]
	var hit := ProjectileHit.new()
	hit.spec = _spec
	hit.velocity = Vector3(0.0, 0.0, -600.0)
	hit.position = part.global_position
	part.receive_hit(hit)
	assert_eq(part.linear_velocity, Vector3.ZERO)
