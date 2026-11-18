extends GutTest

const HYBRID: AttachmentData = preload("res://weapons/attachments/data/hybrid_35x.tres")

func test_zoom_is_tangent_correct_at_every_player_fov() -> void:
	for reference: float in [50.0,65.0,100.0]:
		var fov: float = OpticMath.fov_for_zoom(reference, 3.5)
		assert_almost_eq(tan(deg_to_rad(reference)*0.5) / tan(deg_to_rad(fov)*0.5), 3.5, 0.000001)
		assert_almost_eq(OpticMath.sensitivity_for_zoom(3.5), 1.0/3.5, 0.000001)
		var lens: float = OpticMath.lens_fov(reference, 3.5, 300.0/720.0)
		assert_almost_eq(tan(deg_to_rad(lens)*0.5) / (300.0/720.0), tan(deg_to_rad(fov)*0.5), 0.000001)

func test_hybrid_is_compatible_only_with_rifles_smgs_and_lmgs() -> void:
	for weapon_class: int in WeaponTypes.Class.values():
		assert_eq(HYBRID.accepts(weapon_class as WeaponTypes.Class), weapon_class in [WeaponTypes.Class.RIFLE,WeaponTypes.Class.SMG,WeaponTypes.Class.LMG])
	var rifle: WeaponData = load("res://weapons/data/halberd_rifle.tres")
	var build := WeaponBuild.new(rifle)
	assert_true(build.set_attachment(WeaponTypes.Slot.OPTIC, HYBRID))
	assert_false(build.get_stats().scoped)
	assert_eq(build.get_stats().optic_kind, 5)
	assert_eq(build.get_stats().optic_magnification, 3.5)
	assert_almost_eq(build.get_stats().ads_fov_degrees, OpticMath.fov_for_zoom(65,3.5), 0.000001)
	var invalid := HYBRID.duplicate() as AttachmentData
	invalid.optic_magnification = 0.0
	assert_false(build.can_attach(WeaponTypes.Slot.OPTIC, invalid))
	invalid.optic_magnification = NAN
	assert_false(build.can_attach(WeaponTypes.Slot.OPTIC, invalid))

func test_both_lenses_keep_periphery_unzoomed_and_blackout_off_under_recoil() -> void:
	var old_ads: float = ViewSettings.ads_sensitivity_multiplier
	ViewSettings.ads_sensitivity_multiplier = 1.0
	var world := Node3D.new()
	add_child_autofree(world)
	world.add_child(ProjectileSystem.new())
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerController
	world.add_child(player)
	var controller := player.get_node("Weapons") as WeaponController
	var hud := (load("res://ui/hud.tscn") as PackedScene).instantiate() as Hud
	world.add_child(hud)
	var four: AttachmentData = load("res://weapons/attachments/data/scope_4x.tres")
	for optic: AttachmentData in [HYBRID, four]:
		Input.action_release("aim")
		assert_true(controller.request_attachment(WeaponTypes.Slot.OPTIC, optic))
		await wait_physics_frames(4)
		Input.action_press("aim")
		await wait_physics_frames(60)
		assert_false(hud.is_scope_visible(), "No blackout for " + optic.display_name)
		assert_true(hud.hybrid.visible)
		assert_true(hud.hybrid.lens_active)
		assert_eq(hud.hybrid.find_children("*", "SubViewport", true, false).size(), 0)
		var camera: Camera3D = player.get_viewport().get_camera_3d()
		assert_almost_eq(camera.fov, ViewSettings.fov_degrees, 0.0001)
		assert_almost_eq(hud.hybrid.sample_zoom, OpticMath.screen_lens_zoom(camera.fov, OpticMath.target_fov(controller.get_current_data(), ViewSettings.fov_degrees)), 0.0001)
		if optic == HYBRID:
			assert_almost_eq(player.look_sensitivity_scale, 1.0/3.5, 0.00001)
		else:
			assert_almost_eq(player.look_sensitivity_scale, controller.get_current_data().ads_sensitivity_scale, 0.00001)
		var center: Vector2 = hud.hybrid.get_global_rect().get_center()
		var original_basis: Basis = camera.global_basis
		player.add_recoil(0.1, 0.04)
		await wait_physics_frames(2)
		assert_eq(hud.hybrid.get_global_rect().get_center(), center)
		assert_false(camera.global_basis.is_equal_approx(original_basis))
		Input.action_press("fire")
		await wait_physics_frames(5)
		Input.action_release("fire")
		assert_false(hud.is_scope_visible())
		await wait_physics_frames(10)
	Input.action_release("aim")
	ViewSettings.ads_sensitivity_multiplier = old_ads

func test_screen_lens_projection_and_visibility_without_a_second_camera() -> void:
	for reference: float in [50.0,65.0,100.0]:
		var target: float = OpticMath.fov_for_zoom(reference,3.5)
		assert_almost_eq(OpticMath.screen_lens_zoom(reference,target),3.5,0.000001)
	assert_almost_eq(OpticMath.screen_lens_zoom(65,18.098708656),4.0,0.000001)
	var world := Node3D.new()
	add_child_autofree(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	var overlay := HybridOptic.new()
	world.add_child(overlay)
	var build := WeaponBuild.new(load("res://weapons/data/halberd_rifle.tres") as WeaponData)
	build.set_attachment(WeaponTypes.Slot.OPTIC, HYBRID)
	overlay.update_view(build.get_stats(),1.0,camera)
	assert_true(overlay.visible)
	var copy := overlay.get_node("ScopeWorldCopy") as BackBufferCopy
	assert_eq(copy.copy_mode, BackBufferCopy.COPY_MODE_RECT)
	assert_almost_eq(copy.rect.get_center().x, overlay.size.x * 0.5, 0.001)
	assert_almost_eq(copy.rect.size.x, overlay.size.y * HybridOptic.LENS_HEIGHT_FRACTION / overlay.sample_zoom + 4.0, 0.001)
	assert_lt(copy.rect.size.x, overlay.lens.size.x)
	assert_eq(overlay.find_children("*", "SubViewport", true, false).size(),0)
	overlay.update_view(build.get_stats(),0.0,camera)
	assert_false(overlay.visible)
	assert_false(overlay.lens_active)
	var sniper: WeaponData = load("res://weapons/data/longwatch_sniper.tres")
	assert_false(HybridOptic.supports(sniper), "8x keeps its existing presentation")
