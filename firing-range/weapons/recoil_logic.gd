class_name RecoilLogic
extends RefCounted
## Recoil and spread for one weapon: which kick each shot in a burst gets,
## how much of the view kick may recover this tick, and the cone each shot
## leaves in (hip or aimed spread plus bloom from recent shots). No nodes,
## so it is testable to the tick. `WeaponController` applies the results to
## the player's view and the projectile direction.
##
## Kicks are in degrees: x is yaw (positive to the right), y is pitch
## (positive up).

var data: WeaponData
## Index into the pattern for the next shot. Starts at 0 and returns to 0
## after `data.recoil_reset_time` without a shot.
var shot_index: int = 0
## Seconds since the last shot. Starts large, as if the weapon had settled.
var time_since_shot: float = 1000.0
## Extra cone from recent shots, degrees.
var bloom: float = 0.0

var _rng: RandomNumberGenerator


func _init(weapon_data: WeaponData, rng: RandomNumberGenerator) -> void:
	data = weapon_data
	_rng = rng


## Clears pattern position and bloom, as after a respawn.
func reset() -> void:
	shot_index = 0
	bloom = 0.0
	time_since_shot = 1000.0


## Advances time by one tick. Call before this tick's shots.
func tick(delta: float) -> void:
	time_since_shot += delta
	if time_since_shot >= data.recoil_reset_time - WeaponLogic.TIME_EPSILON:
		shot_index = 0
	if time_since_shot >= data.recoil_recovery_delay - WeaponLogic.TIME_EPSILON:
		bloom = maxf(bloom - data.bloom_recovery_rate * delta, 0.0)


## Registers a shot and returns its kick in degrees, scaled by how far the
## weapon is aimed (0 hip, 1 aimed).
func on_shot(aim_progress: float) -> Vector2:
	var kick: Vector2 = pattern_kick(shot_index)
	var random: Vector2 = data.recoil_random_degrees
	kick += Vector2(_rng.randf_range(-random.x, random.x), _rng.randf_range(-random.y, random.y))
	kick *= lerpf(1.0, data.aimed_recoil_scale, clampf(aim_progress, 0.0, 1.0))
	shot_index += 1
	time_since_shot = 0.0
	bloom = minf(bloom + data.spread_per_shot_degrees, data.max_bloom_degrees)
	return kick


## Cone half-angle for the next shot, degrees: hip or aimed spread blended
## by `aim_progress`, plus bloom.
func spread_degrees(aim_progress: float) -> float:
	var base: float = lerpf(data.hip_spread_degrees, data.aimed_spread_degrees, clampf(aim_progress, 0.0, 1.0))
	return base + bloom


## A random direction inside a cone of `spread` degrees around `direction`,
## spread evenly over the cone's cross-section. Returns `direction`
## unchanged (normalised) when the cone is 0.
func deviate(direction: Vector3, spread: float) -> Vector3:
	return ConeSpread.sample(direction, spread, _rng)


## The pattern's kick for shot `index` (0-based), without the random part.
## Past the end of the pattern the last `recoil_loop_length` entries repeat.
func pattern_kick(index: int) -> Vector2:
	var pattern: PackedVector2Array = data.recoil_pattern
	if pattern.is_empty():
		return Vector2.ZERO
	if index < pattern.size():
		return pattern[index]
	var loop: int = clampi(data.recoil_loop_length, 1, pattern.size())
	var loop_start: int = pattern.size() - loop
	return pattern[loop_start + (index - loop_start) % loop]


## Degrees of view kick that may recover this tick: none until
## `recoil_recovery_delay` has passed since the last shot.
func recovery_allowance(delta: float) -> float:
	if time_since_shot < data.recoil_recovery_delay - WeaponLogic.TIME_EPSILON:
		return 0.0
	return data.recoil_recovery_rate * delta


## Splits a look movement against a recoil offset (both in the same angle
## units and sign). Movement opposite to the offset cancels it first, so
## recoil the player has already pulled down is never recovered again.
## Returns (new offset, movement left over for the base look angle). The
## view moves by exactly `look_delta` either way.
static func absorb(offset: float, look_delta: float) -> Vector2:
	if offset > 0.0 and look_delta < 0.0:
		var taken: float = minf(offset, -look_delta)
		return Vector2(offset - taken, look_delta + taken)
	if offset < 0.0 and look_delta > 0.0:
		var taken: float = minf(-offset, look_delta)
		return Vector2(offset + taken, look_delta - taken)
	return Vector2(offset, look_delta)
