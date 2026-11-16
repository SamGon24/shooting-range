extends GutTest

var _settings: TargetSettings
var _state: TargetHealth


func before_each() -> void:
	_settings = load("res://targets/data/dummy_default.tres") as TargetSettings
	_state = TargetHealth.new(_settings, 3)


func test_armor_before_health_and_carry_over() -> void:
	_state.apply_damage(40.0)
	assert_eq(_state.armor, 110.0)
	assert_eq(_state.health, 100.0)
	assert_eq(_state.remaining_plates(), 3)
	_state.apply_damage(125.0)
	assert_eq(_state.armor, 0.0)
	assert_eq(_state.health, 85.0)


func test_exact_break_on_last_plate_preserves_health() -> void:
	_state.apply_damage(100.0)
	assert_eq(_state.remaining_plates(), 1)
	_state.apply_damage(50.0)
	assert_eq(_state.armor, 0.0)
	assert_eq(_state.health, 100.0)
	assert_eq(_state.remaining_plates(), 0)
	_state.apply_damage(10.0)
	assert_eq(_state.health, 90.0)


func test_plate_counts_zero_through_three_and_clamped() -> void:
	for count: int in range(5):
		var state := TargetHealth.new(_settings, count)
		assert_eq(state.armor, float(mini(count, 3)) * 50.0)


func test_zone_multipliers_for_both_weapon_resources() -> void:
	for path: String in ["res://weapons/data/halberd_rifle.tres", "res://weapons/data/longwatch_sniper.tres"]:
		var weapon := load(path) as WeaponData
		var head: float = 2.0 if weapon.projectile.weapon_class == ProjectileSpec.WeaponClass.SNIPER else 1.5
		assert_eq(_settings.multiplier(TargetHitZone.Zone.HEAD, weapon.projectile), head)
		assert_eq(_settings.multiplier(TargetHitZone.Zone.TORSO, weapon.projectile), 1.0)
		assert_eq(_settings.multiplier(TargetHitZone.Zone.LIMB, weapon.projectile), 0.8)


func test_pop_down_and_exact_three_second_reset() -> void:
	var dummy := TargetDummy.new()
	dummy.armor_plates = 3
	add_child_autofree(dummy)
	dummy.set_physics_process(false)
	watch_signals(dummy)
	var hit := ProjectileHit.new()
	hit.spec = ProjectileSpec.new()
	hit.damage = 300.0
	dummy.receive_hit(hit, TargetHitZone.Zone.TORSO)
	assert_signal_emitted(dummy, "killed")
	assert_true(dummy.state.dead)
	for zone: TargetHitZone in dummy.zones:
		assert_eq(zone.collision_layer, 0)
	dummy.advance(0.15)
	assert_almost_eq((dummy.get_child(0) as Node3D).rotation.x, -PI / 2.0, 0.001)
	for tick: int in 170:
		dummy.advance(1.0 / 60.0)
	assert_true(dummy.state.dead, "still down before three seconds")
	dummy.advance(1.0 / 60.0)
	assert_false(dummy.state.dead)
	assert_eq(dummy.state.health, 100.0)
	assert_eq(dummy.state.armor, 150.0)
	assert_signal_emitted(dummy, "restored")
	for zone: TargetHitZone in dummy.zones:
		assert_eq(zone.collision_layer, 1)


func test_dead_target_ignores_damage_and_negative_damage_cannot_heal() -> void:
	_state.apply_damage(-10.0)
	assert_eq(_state.armor, 150.0)
	_state.apply_damage(300.0)
	_state.apply_damage(50.0)
	assert_eq(_state.health, 0.0)
	assert_true(_state.dead)
