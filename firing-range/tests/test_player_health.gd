extends GutTest
## Node-free player vitals and damage-direction maths, stepped at 60 Hz.

const TICK: float = 1.0 / 60.0

var _settings: PlayerHealthSettings
var _vitals: PlayerVitals


func before_each() -> void:
	_settings = load("res://player/data/player_health_default.tres") as PlayerHealthSettings
	_vitals = PlayerVitals.new(_settings)


func _ticks(seconds: float) -> int:
	return roundi(seconds * 60.0)


func _step(ticks: int) -> void:
	for _tick: int in ticks:
		_vitals.advance(TICK)


# --- Armor order ---


func test_spawns_with_full_health_three_plates_and_spares() -> void:
	assert_eq(_vitals.health, 100.0)
	assert_eq(_vitals.armor, 150.0)
	assert_eq(_vitals.remaining_plates(), 3)
	assert_eq(_vitals.spare_plates, _settings.spare_plates)


func test_armor_absorbs_before_health_and_carries_over() -> void:
	_vitals.apply_damage(40.0)
	assert_eq(_vitals.armor, 110.0)
	assert_eq(_vitals.health, 100.0)
	_vitals.apply_damage(125.0)
	assert_eq(_vitals.armor, 0.0, "the last 15 points spill through the broken plates")
	assert_eq(_vitals.health, 85.0)


func test_health_only_once_armor_is_gone_then_death() -> void:
	_vitals.apply_damage(150.0)
	assert_eq(_vitals.health, 100.0, "exactly breaking every plate leaves health intact")
	_vitals.apply_damage(99.0)
	assert_false(_vitals.dead)
	_vitals.apply_damage(1.0)
	assert_true(_vitals.dead)
	_vitals.apply_damage(50.0)
	assert_eq(_vitals.health, 0.0, "no damage while dead")


func test_zone_multipliers_match_the_dummy_rules() -> void:
	var dummy := load("res://targets/data/dummy_default.tres") as TargetSettings
	for path: String in ["res://weapons/data/halberd_rifle.tres", "res://weapons/data/longwatch_sniper.tres"]:
		var spec: ProjectileSpec = (load(path) as WeaponData).projectile
		for zone: TargetSettings.Zone in [TargetSettings.Zone.HEAD, TargetSettings.Zone.TORSO, TargetSettings.Zone.LIMB]:
			assert_eq(_settings.multiplier(zone, spec), dummy.multiplier(zone, spec))


# --- Regeneration timing ---


func test_regeneration_waits_for_the_delay_then_runs_at_the_rate() -> void:
	_vitals.armor = 0.0
	_vitals.apply_damage(60.0)
	assert_eq(_vitals.health, 40.0)
	_step(_ticks(_settings.regen_delay_seconds))
	assert_almost_eq(_vitals.health, 40.0, 0.001, "nothing up to the delay")
	_step(1)
	assert_almost_eq(_vitals.health, 40.0 + _settings.regen_per_second * TICK, 0.001, "first tick past the delay")
	_step(_ticks(1.0) - 1)
	assert_almost_eq(_vitals.health, 40.0 + _settings.regen_per_second, 0.01, "one second of regeneration")
	_step(_ticks(10.0))
	assert_eq(_vitals.health, _settings.max_health, "capped at max health")
	assert_eq(_vitals.armor, 0.0, "armor never regenerates")


func test_new_damage_restarts_the_regeneration_delay() -> void:
	_vitals.armor = 0.0
	_vitals.apply_damage(50.0)
	_step(_ticks(_settings.regen_delay_seconds) - 10)
	_vitals.apply_damage(10.0)
	_step(_ticks(_settings.regen_delay_seconds))
	assert_almost_eq(_vitals.health, 40.0, 0.001)
	_step(1)
	assert_gt(_vitals.health, 40.4)


func test_regeneration_is_tick_rate_independent() -> void:
	var fine := PlayerVitals.new(_settings)
	var coarse := PlayerVitals.new(_settings)
	for vitals: PlayerVitals in [fine, coarse]:
		vitals.armor = 0.0
		vitals.apply_damage(80.0)
	for _tick: int in 600:
		fine.advance(1.0 / 120.0)
	for _tick: int in 150:
		coarse.advance(1.0 / 30.0)
	assert_almost_eq(fine.health, 45.0, 0.01, "one second past the delay at 120 Hz")
	assert_almost_eq(coarse.health, 45.0, 0.01, "and at 30 Hz")


# --- Plates ---


func test_insert_fills_the_lowest_damaged_plate_and_uses_a_spare() -> void:
	_vitals.apply_damage(80.0)
	assert_eq(_vitals.armor, 70.0)
	assert_eq(_vitals.remaining_plates(), 2)
	assert_true(_vitals.insert_plate())
	assert_eq(_vitals.armor, 100.0, "the cracked second plate is replaced")
	assert_eq(_vitals.spare_plates, _settings.spare_plates - 1)
	assert_true(_vitals.insert_plate())
	assert_eq(_vitals.armor, 150.0)
	assert_false(_vitals.insert_plate(), "a full vest takes no more")
	assert_eq(_vitals.spare_plates, _settings.spare_plates - 2)


func test_no_insert_without_spares() -> void:
	_vitals.armor = 0.0
	_vitals.spare_plates = 0
	assert_false(_vitals.can_insert_plate())
	assert_false(_vitals.begin_insert())


func test_insert_timing_matches_the_resource() -> void:
	_vitals.armor = 0.0
	assert_true(_vitals.begin_insert())
	var ticks: int = _ticks(_settings.plate_insert_seconds)
	for _tick: int in ticks - 1:
		assert_false(_vitals.advance_insert(TICK))
	assert_almost_eq(_vitals.insert_progress(), float(ticks - 1) / float(ticks), 0.001)
	assert_true(_vitals.advance_insert(TICK), "lands on the authored tick")
	assert_eq(_vitals.armor, 50.0)
	assert_false(_vitals.inserting)


func test_cancelled_insert_uses_no_plate() -> void:
	_vitals.armor = 0.0
	_vitals.begin_insert()
	for _tick: int in 30:
		_vitals.advance_insert(TICK)
	_vitals.cancel_insert()
	assert_eq(_vitals.armor, 0.0)
	assert_eq(_vitals.spare_plates, _settings.spare_plates)
	assert_eq(_vitals.insert_progress(), 0.0)


# --- Death and respawn state ---


func test_respawn_clock_and_full_state_reset() -> void:
	_vitals.apply_damage(400.0)
	_vitals.spare_plates = 1
	assert_true(_vitals.dead)
	var restored: int = -1
	var ticks: int = _ticks(_settings.reset_seconds)
	for tick: int in ticks + 5:
		if _vitals.advance(TICK) and restored < 0:
			restored = tick + 1
	assert_eq(restored, ticks, "respawns on the authored tick")
	assert_false(_vitals.dead)
	assert_eq(_vitals.health, _settings.max_health)
	assert_eq(_vitals.armor, 150.0)
	assert_eq(_vitals.spare_plates, _settings.spare_plates)
	assert_almost_eq(_vitals.since_damage, 5.0 * TICK, 0.0001, "regeneration clock restarted at respawn")


func test_no_regeneration_while_dead() -> void:
	_vitals.apply_damage(400.0)
	_step(_ticks(_settings.reset_seconds) - 1)
	assert_eq(_vitals.health, 0.0)


func test_empty_vest_start_on_spawn_and_respawn() -> void:
	_vitals.start_plates = 0
	_vitals.reset()
	assert_eq(_vitals.armor, 0.0, "no preloaded plates")
	assert_eq(_vitals.spare_plates, _settings.spare_plates, "spares still carried")
	assert_true(_vitals.can_insert_plate())
	_vitals.insert_plate()
	assert_eq(_vitals.armor, 50.0)
	_vitals.apply_damage(400.0)
	_step(_ticks(_settings.reset_seconds))
	assert_false(_vitals.dead)
	assert_eq(_vitals.armor, 0.0, "respawns with an empty vest too")
	assert_eq(_vitals.spare_plates, _settings.spare_plates)


# --- Damage direction maths ---


func _from(attacker_offset: Vector3, yaw: float) -> float:
	# A bullet fired from `attacker_offset` (relative to the victim) travels
	# the opposite way.
	return DamageDirection.screen_angle(-attacker_offset, yaw)


func test_direction_relative_to_facing() -> void:
	assert_almost_eq(_from(Vector3(0, 0, -10), 0.0), 0.0, 0.0001, "attacker ahead (-Z)")
	assert_almost_eq(_from(Vector3(10, 0, 0), 0.0), PI * 0.5, 0.0001, "attacker to the right (+X)")
	assert_almost_eq(_from(Vector3(-10, 0, 0), 0.0), -PI * 0.5, 0.0001, "attacker to the left")
	assert_almost_eq(absf(_from(Vector3(0, 0, 10), 0.0)), PI, 0.0001, "attacker behind")


func test_direction_follows_the_view_yaw() -> void:
	# Turning left by 90 degrees puts an attacker at -Z on the right.
	assert_almost_eq(_from(Vector3(0, 0, -10), PI * 0.5), PI * 0.5, 0.0001)
	assert_almost_eq(_from(Vector3(-10, 0, 0), PI * 0.5), 0.0, 0.0001)
	assert_almost_eq(_from(Vector3(5, 0, -5), 0.0), PI * 0.25, 0.0001, "front-right diagonal")


func test_direction_ignores_height_and_rejects_vertical() -> void:
	assert_almost_eq(_from(Vector3(10, 30, 0), 0.0), PI * 0.5, 0.0001)
	assert_true(is_nan(DamageDirection.screen_angle(Vector3.DOWN, 0.0)))


func test_incoming_prefers_source_position_then_velocity() -> void:
	var hit := ProjectileHit.new()
	hit.velocity = Vector3(0, 0, 400)
	assert_eq(DamageDirection.incoming(hit, Vector3.ZERO), Vector3(0, 0, 400))
	hit.source_position = Vector3(3, 0, 0)
	assert_eq(DamageDirection.incoming(hit, Vector3.ZERO), Vector3(-3, 0, 0), "blast centre wins")
	var swing := ProjectileHit.new()
	swing.impulse_override = Vector3(1, 0, 0)
	assert_eq(DamageDirection.incoming(swing, Vector3.ZERO), Vector3(1, 0, 0))
