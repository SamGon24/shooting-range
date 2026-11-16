extends GutTest
## Real swept projectiles and Jolt zones; no synthetic damage path.

var _system: ProjectileSystem
var _dummy: TargetDummy
var _hits: Array[ProjectileHit] = []


func before_each() -> void:
	_hits.clear()
	_system = ProjectileSystem.new()
	add_child_autofree(_system)
	_system.set_physics_process(false)
	_system.projectile_hit.connect(func(hit: ProjectileHit) -> void: _hits.append(hit))
	add_child_autofree(TargetHits.new())
	_dummy = TargetDummy.new()
	_dummy.position.z = -100.0
	add_child_autofree(_dummy)
	_dummy.set_physics_process(false)
	await wait_physics_frames(2)


func _fire(weapon_path: String, x: float, y: float) -> void:
	var weapon := load(weapon_path) as WeaponData
	_system.fire(Vector3(x, y, 0.0), Vector3.FORWARD, weapon.projectile)
	for tick: int in 12:
		_system.advance(1.0 / 60.0)


func test_sniper_headshot_at_100_m_kills_unarmored_dummy() -> void:
	_fire("res://weapons/data/longwatch_sniper.tres", 0.0, 1.72)
	assert_eq(_hits.size(), 1)
	assert_true(_dummy.state.dead)
	assert_eq(_dummy.state.health, 0.0)
	if _hits.size() == 1:
		assert_eq((_hits[0].collider as TargetHitZone).zone, TargetHitZone.Zone.HEAD)
		assert_almost_eq(_hits[0].travel_distance, 100.0, 0.2)


func test_rifle_body_shot_at_100_m_does_not_kill() -> void:
	_fire("res://weapons/data/halberd_rifle.tres", 0.0, 1.25)
	assert_eq(_hits.size(), 1)
	assert_false(_dummy.state.dead)
	assert_almost_eq(_dummy.state.health, 71.2, 0.02)


func test_rifle_hits_each_limb_with_limb_multiplier() -> void:
	for aim: Vector2 in [Vector2(-0.35, 1.25), Vector2(0.35, 1.25), Vector2(-0.14, 0.55), Vector2(0.14, 0.55)]:
		_dummy.state.reset()
		_hits.clear()
		_fire("res://weapons/data/halberd_rifle.tres", aim.x, aim.y)
		assert_eq(_hits.size(), 1)
		assert_almost_eq(_dummy.state.health, 100.0 - 28.8 * 0.8, 0.02)


func test_rail_carried_zones_are_hit_at_their_moved_position() -> void:
	var rail := TargetRail.new()
	add_child_autofree(rail)
	rail.set_physics_process(false)
	_dummy.reparent(rail)
	rail.advance(0.5)
	await wait_physics_frames(2)
	_fire("res://weapons/data/halberd_rifle.tres", 0.75, 1.25)
	assert_eq(_hits.size(), 1)
	assert_almost_eq(_dummy.state.health, 71.2, 0.02)
