extends GutTest
## Impact effects and generated sounds: pooled, bounded, and non-silent.

var _effects: ImpactEffects
var _wall: StaticBody3D


func before_each() -> void:
	_effects = ImpactEffects.new()
	_effects.mark_capacity = 8
	add_child_autofree(_effects)
	_wall = StaticBody3D.new()
	add_child_autofree(_wall)
	await wait_physics_frames(1)


func _hit(point: Vector3, normal: Vector3, collider: Object) -> ProjectileHit:
	var hit := ProjectileHit.new()
	hit.position = point
	hit.normal = normal
	hit.collider = collider
	return hit


func _peak(stream: AudioStreamWAV) -> int:
	var peak: int = 0
	for index: int in stream.data.size() / 2:
		peak = maxi(peak, absi(stream.data.decode_s16(index * 2)))
	return peak


# --- Impacts ---


func test_impacts_do_not_create_nodes() -> void:
	var nodes_before: int = get_tree().get_node_count()
	for shot: int in 50:
		_effects.show_impact(_hit(Vector3(float(shot), 0.0, 0.0), Vector3.UP, _wall))
	assert_eq(get_tree().get_node_count(), nodes_before, "sparks, marks and sounds are all pooled")


func test_marks_fill_up_to_capacity_then_reuse_the_oldest() -> void:
	for shot: int in 5:
		_effects.show_impact(_hit(Vector3(float(shot), 0.0, 0.0), Vector3.UP, _wall))
	assert_eq(_effects.get_mark_count(), 5)

	for shot: int in range(5, 11):
		_effects.show_impact(_hit(Vector3(float(shot), 0.0, 0.0), Vector3.UP, _wall))
	assert_eq(_effects.get_mark_count(), 8, "never more than the capacity")
	# Shots 8, 9 and 10 wrapped around onto slots 0, 1 and 2.
	assert_almost_eq(_effects.get_mark_transform(0).origin.x, 8.0, 0.001)
	assert_almost_eq(_effects.get_mark_transform(2).origin.x, 10.0, 0.001)
	assert_almost_eq(_effects.get_mark_transform(3).origin.x, 3.0, 0.001, "slot 3 still holds shot 3")


func test_mark_lies_on_the_surface_facing_out() -> void:
	for normal: Vector3 in [Vector3.UP, Vector3(0.0, 0.0, 1.0), Vector3(1.0, 0.0, 0.0), Vector3.DOWN]:
		_effects.show_impact(_hit(Vector3(2.0, 3.0, 4.0), normal, _wall))
		var mark: Transform3D = _effects.get_mark_transform(_effects.get_mark_count() - 1)
		var facing: Vector3 = mark.basis.z.normalized()
		assert_almost_eq(facing, normal, Vector3.ONE * 0.001, "quad faces along the normal %s" % normal)
		var lift: float = (mark.origin - Vector3(2.0, 3.0, 4.0)).dot(normal)
		assert_almost_eq(lift, _effects.mark_surface_offset, 0.0001, "just off the surface")
		assert_between(mark.basis.x.length(), _effects.mark_size * 0.79, _effects.mark_size * 1.21)


func test_no_mark_on_a_moving_body() -> void:
	var mover := RigidBody3D.new()
	add_child_autofree(mover)
	_effects.show_impact(_hit(Vector3.ZERO, Vector3.UP, mover))
	assert_eq(_effects.get_mark_count(), 0, "marks only stick to static geometry")


func test_listens_to_the_projectile_system() -> void:
	var system := ProjectileSystem.new()
	add_child_autofree(system)
	var effects := ImpactEffects.new()
	add_child_autofree(effects)
	await wait_physics_frames(2)
	system.projectile_hit.emit(_hit(Vector3.ZERO, Vector3.UP, _wall))
	assert_eq(effects.get_mark_count(), 1)


# --- Generated sounds ---


func test_gunshot_has_the_requested_length_and_is_not_silent() -> void:
	var stream: AudioStreamWAV = SfxFactory.gunshot(120.0, 0.2)
	assert_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS)
	assert_almost_eq(stream.get_length(), 0.2, 0.001)
	assert_gt(_peak(stream), 8000, "audible")


func test_sounds_are_cached_and_deterministic() -> void:
	assert_same(SfxFactory.gunshot(70.0, 0.45), SfxFactory.gunshot(70.0, 0.45))
	assert_same(SfxFactory.impact(), SfxFactory.impact())
	assert_ne(SfxFactory.gunshot(70.0, 0.45).data, SfxFactory.gunshot(120.0, 0.2).data, "each weapon sounds different")


func test_click_and_impact_are_short_and_audible() -> void:
	for stream: AudioStreamWAV in [SfxFactory.click(1100.0, 0.05), SfxFactory.impact()]:
		assert_lt(stream.get_length(), 0.15)
		assert_gt(_peak(stream), 3000)
