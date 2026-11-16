extends GutTest

const TICK: float = 1.0 / 60.0
const DENSITY: float = ProjectileMath.SEA_LEVEL_AIR_DENSITY


## Independent integration at 240 Hz, intersecting the sight-distance plane.
func _reference(spec: ProjectileSpec, distance: float, height: float, angle: float) -> float:
	var p := Vector3(0, -height, 0)
	var v: Vector3 = Vector3.FORWARD.rotated(Vector3.RIGHT, angle) * spec.muzzle_velocity
	for tick: int in 2400:
		var step: PackedVector3Array = ProjectileMath.step_drag(p, v, Vector3.DOWN * 9.81 * spec.gravity_scale, spec.drag_factor(DENSITY), 1.0 / 240.0)
		if -step[0].z >= distance:
			return p.lerp(step[0], (-distance - p.z) / (step[0].z - p.z)).y
		p = step[0]
		v = step[1]
	return NAN


func test_numerical_zero_matches_independent_integrator_with_and_without_drag() -> void:
	for drag: float in [0.0, 0.3]:
		var spec := ProjectileSpec.new()
		spec.drag_coefficient = drag
		for height: float in [0.0, 0.02, 0.073]:
			var angle: float = SightZeroing.solve(spec, 100.0, height, 9.81, DENSITY, TICK)
			assert_gt(angle, 0.0)
			assert_almost_eq(_reference(spec, 100.0, height, angle), 0.0, 0.001)


func test_low_sights_cross_twice_and_have_midrange_rise_and_far_drop() -> void:
	var spec := ProjectileSpec.new()
	spec.drag_coefficient = 0.3
	var height: float = 0.02
	var angle: float = SightZeroing.solve(spec, 100.0, height, 9.81, DENSITY, TICK)
	assert_lt(_reference(spec, 1.0, height, angle), 0.0)
	assert_gt(_reference(spec, 50.0, height, angle), 0.0)
	assert_almost_eq(_reference(spec, 100.0, height, angle), 0.0, 0.001)
	assert_lt(_reference(spec, 300.0, height, angle), 0.0)


func test_full_trigonometry_at_large_angles() -> void:
	var spec := ProjectileSpec.new()
	spec.muzzle_velocity = 50.0
	spec.max_lifetime = 10.0
	var angle: float = SightZeroing.solve(spec, 180.0, 0.07, 9.81, DENSITY, TICK)
	assert_gt(rad_to_deg(angle), 20.0)
	assert_almost_eq(_reference(spec, 180.0, 0.07, angle), 0.0, 0.002)


func test_disabled_and_unreachable_zeros() -> void:
	var spec := ProjectileSpec.new()
	assert_eq(SightZeroing.solve(spec, 0.0, 0.05, 9.81, DENSITY, TICK), 0.0)
	spec.max_lifetime = 0.01
	assert_true(is_nan(SightZeroing.solve(spec, 100.0, 0.05, 9.81, DENSITY, TICK)))
