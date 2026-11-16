extends GutTest
## Damage falloff by distance in ProjectileSpec, and the damage a hit
## reports through the ProjectileSystem.

const RIFLE: WeaponData = preload("res://weapons/data/halberd_rifle.tres")
const SNIPER: WeaponData = preload("res://weapons/data/longwatch_sniper.tres")


func _spec(damage: float, start: float, end: float, min_fraction: float) -> ProjectileSpec:
	var spec := ProjectileSpec.new()
	spec.damage = damage
	spec.falloff_start_distance = start
	spec.falloff_end_distance = end
	spec.min_damage_fraction = min_fraction
	return spec


func test_full_damage_up_to_the_falloff_start() -> void:
	var spec: ProjectileSpec = _spec(40.0, 50.0, 150.0, 0.5)
	assert_eq(spec.damage_at_distance(0.0), 40.0)
	assert_eq(spec.damage_at_distance(50.0), 40.0)


func test_linear_between_start_and_end() -> void:
	var spec: ProjectileSpec = _spec(40.0, 50.0, 150.0, 0.5)
	assert_almost_eq(spec.damage_at_distance(100.0), 30.0, 0.0001, "halfway: 75%")
	assert_almost_eq(spec.damage_at_distance(75.0), 35.0, 0.0001)


func test_minimum_from_the_falloff_end_onwards() -> void:
	var spec: ProjectileSpec = _spec(40.0, 50.0, 150.0, 0.5)
	assert_almost_eq(spec.damage_at_distance(150.0), 20.0, 0.0001)
	assert_almost_eq(spec.damage_at_distance(1000.0), 20.0, 0.0001)


func test_falloff_never_increases_damage() -> void:
	var spec: ProjectileSpec = _spec(40.0, 50.0, 150.0, 0.5)
	var last: float = INF
	for metres: int in range(0, 400, 5):
		var value: float = spec.damage_at_distance(float(metres))
		assert_true(value <= last, "monotonic at %d m" % metres)
		last = value


func test_start_equal_to_end_is_a_step() -> void:
	var spec: ProjectileSpec = _spec(40.0, 100.0, 100.0, 0.5)
	assert_eq(spec.damage_at_distance(99.0), 40.0)
	assert_eq(spec.damage_at_distance(101.0), 20.0)


func test_weapon_values() -> void:
	# Rifle: 32 falling to 70% by 200 m. Sniper: 110 falling to 80% by 400 m.
	assert_eq(RIFLE.projectile.damage_at_distance(25.0), 32.0)
	assert_almost_eq(RIFLE.projectile.damage_at_distance(300.0), 22.4, 0.0001)
	assert_eq(SNIPER.projectile.damage_at_distance(100.0), 110.0)
	assert_almost_eq(SNIPER.projectile.damage_at_distance(300.0), 96.8, 0.0001)


func test_a_hit_reports_damage_after_falloff() -> void:
	var system := ProjectileSystem.new()
	add_child_autofree(system)
	system.set_physics_process(false)
	var hits: Array[ProjectileHit] = []
	system.projectile_hit.connect(func(hit: ProjectileHit) -> void: hits.append(hit))
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20.0, 20.0, 1.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	body.position = Vector3(0.0, 0.0, -100.5)
	add_child_autofree(body)
	await wait_physics_frames(2)

	var spec: ProjectileSpec = _spec(40.0, 50.0, 150.0, 0.5)
	var slot: int = system.fire(Vector3(0.0, 1.5, 0.0), Vector3.FORWARD, spec)
	for _tick: int in 20:
		system.advance(1.0 / 60.0)
	assert_eq(hits.size(), 1)
	if hits.size() == 1:
		assert_eq(hits[0].slot, slot)
		assert_almost_eq(hits[0].damage, spec.damage_at_distance(hits[0].travel_distance), 0.0001)
		assert_almost_eq(hits[0].damage, 30.0, 0.01, "about 75% at 100 m")
