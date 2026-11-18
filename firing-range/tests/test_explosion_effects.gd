extends GutTest

var _world: Node3D
var _system: ProjectileSystem
var _explosions: ExplosionSystem
var _effects: ExplosionEffects


func before_each() -> void:
	_world = Node3D.new()
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child_autofree(_world)
	_system = ProjectileSystem.new()
	_world.add_child(_system)
	_system.set_physics_process(false)
	_explosions = ExplosionSystem.new()
	_world.add_child(_explosions)
	_effects = ExplosionEffects.new()
	_world.add_child(_effects)
	await wait_process_frames(2)
	_effects.set_process(false)


func test_only_explosive_projectiles_draw_bodies_and_expiry_clears_them() -> void:
	var bullet := ProjectileSpec.new()
	bullet.gravity_scale = 0.0
	_system.fire(Vector3(0, 30, 0), Vector3.FORWARD, bullet)
	_effects._process(0.01)
	assert_eq(_effects.get_rocket_count(), 0)
	assert_false(_effects.is_processing())
	var rocket := bullet.duplicate() as ProjectileSpec
	rocket.explosion = ExplosionData.new()
	rocket.max_lifetime = 0.1
	_system.fire(Vector3(0, 30, 0), Vector3.FORWARD, rocket)
	assert_true(_effects.is_processing())
	_effects._process(0.01)
	assert_eq(_effects.get_rocket_count(), 1)
	_system.advance(0.1)
	_effects._process(0.01)
	assert_eq(_effects.get_rocket_count(), 0)
	assert_false(_effects.is_processing())


func test_many_blasts_reuse_bounded_visual_and_sound_pools_without_gameplay_events() -> void:
	watch_signals(_system)
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for index: int in _effects.flash_capacity * 3:
		_explosions.exploded.emit(Vector3(index, 30, 0), ExplosionData.new())
	_effects._process(0.01)
	assert_eq(_effects.get_flash_count(), _effects.flash_capacity)
	assert_eq(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), nodes)
	assert_signal_not_emitted(_system, "shot_started")
	assert_signal_not_emitted(_system, "projectile_hit")
	_effects._process(_effects.flash_lifetime)
	assert_eq(_effects.get_flash_count(), 0)
	assert_false(_effects.is_processing())


func test_expansion_and_audio_stop_while_range_is_paused() -> void:
	_explosions.exploded.emit(Vector3(0, 30, 0), ExplosionData.new())
	await wait_process_frames(1)
	var age: float = _effects._ages[0]
	get_tree().paused = true
	await wait_process_frames(3)
	var paused_age: float = _effects._ages[0]
	get_tree().paused = false
	assert_eq(paused_age, age)
	await wait_process_frames(2)
	assert_gt(_effects._ages[0], paused_age)
