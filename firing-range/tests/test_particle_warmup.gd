extends GutTest
## First-draw warm-up: a throwaway twin shares the real emitter's material,
## is negligible in size and frees itself, and the real effects stay
## untouched when there is no renderer.


func _emitter(world_space: bool) -> CPUParticles3D:
	var material := StandardMaterial3D.new()
	var mesh := BoxMesh.new()
	mesh.material = material
	var emitter := CPUParticles3D.new()
	emitter.mesh = mesh
	emitter.amount = 10
	emitter.lifetime = 0.2
	emitter.one_shot = true
	emitter.emitting = false
	emitter.local_coords = not world_space
	emitter.scale_amount_min = 0.5
	emitter.scale_amount_max = 0.9
	var parent := Node3D.new()
	add_child_autofree(parent)
	parent.add_child(emitter)
	return emitter


func test_it_is_not_needed_without_a_renderer_or_with_the_debug_switch() -> void:
	assert_eq(DisplayServer.get_name(), "headless", "the suite runs headless")
	assert_false(ParticleWarmup.is_needed())
	assert_null(ParticleWarmup.warm(_emitter(true), Vector3.ZERO), "does nothing when not needed")


func test_the_twin_shares_the_material_is_tiny_and_leaves_the_real_emitter_alone() -> void:
	var emitter: CPUParticles3D = _emitter(true)
	var twin: CPUParticles3D = ParticleWarmup.warm(emitter, Vector3(1.0, 2.0, 3.0), true)
	assert_not_null(twin)
	assert_eq(twin.mesh, emitter.mesh, "same mesh and so the same material")
	assert_eq(twin.mesh.material, emitter.mesh.material)
	assert_almost_eq(twin.scale_amount_max, ParticleWarmup.TINY_SCALE, 0.000001)
	assert_eq(twin.amount, 1)
	assert_true(twin.emitting)
	assert_eq(twin.global_position, Vector3(1.0, 2.0, 3.0), "world-space twin goes where it is told")
	assert_eq(emitter.amount, 10)
	assert_almost_eq(emitter.scale_amount_max, 0.9, 0.0001)
	assert_false(emitter.emitting, "the real emitter is never started")


func test_a_local_space_twin_rides_with_its_parent_and_the_twin_frees_itself() -> void:
	var emitter: CPUParticles3D = _emitter(false)
	var parent: Node = emitter.get_parent()
	var twin: CPUParticles3D = ParticleWarmup.warm(emitter, Vector3(9.0, 9.0, 9.0), true)
	assert_eq(twin.get_parent(), parent)
	assert_eq(twin.position, emitter.position, "not moved: it shares the emitter's place")
	await get_tree().create_timer(emitter.lifetime + 0.5).timeout
	assert_false(is_instance_valid(twin), "the twin is freed")
	assert_eq(parent.get_child_count(), 1)


func test_headless_effect_nodes_are_not_touched_by_the_warm_up() -> void:
	var smoke := MuzzleSmoke.new()
	add_child_autofree(smoke)
	var impacts := ImpactEffects.new()
	add_child_autofree(impacts)
	await wait_physics_frames(10)
	for emitter: CPUParticles3D in smoke.get_emitters():
		assert_false(emitter.emitting)
		assert_eq(emitter.get_parent(), smoke)
	assert_eq(smoke.get_child_count(), smoke.emitters)
	assert_eq(impacts.get_mark_count(), 0)
