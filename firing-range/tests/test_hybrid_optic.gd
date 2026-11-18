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

func test_live_hybrid_keeps_blackout_off_and_reticle_centered_under_recoil() -> void:
	var old_lens: bool = ViewSettings.hybrid_lens
	var old_ads: float = ViewSettings.ads_sensitivity_multiplier
	ViewSettings.hybrid_lens = false
	ViewSettings.ads_sensitivity_multiplier = 1.0
	var world := Node3D.new()
	add_child_autofree(world)
	world.add_child(ProjectileSystem.new())
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerController
	world.add_child(player)
	var controller := player.get_node("Weapons") as WeaponController
	var hud := (load("res://ui/hud.tscn") as PackedScene).instantiate() as Hud
	world.add_child(hud)
	assert_true(controller.request_attachment(WeaponTypes.Slot.OPTIC, HYBRID))
	Input.action_press("aim")
	await wait_physics_frames(60)
	assert_false(hud.is_scope_visible())
	assert_true(hud.hybrid.visible)
	assert_null(hud.hybrid.viewport, "Mode A allocates no second renderer")
	assert_almost_eq(player.look_sensitivity_scale, 1.0/3.5, 0.00001)
	var center: Vector2 = hud.hybrid.get_global_rect().get_center()
	var original_basis: Basis = player.get_viewport().get_camera_3d().global_basis
	player.add_recoil(0.1, 0.04)
	await wait_physics_frames(2)
	assert_eq(hud.hybrid.get_global_rect().get_center(), center)
	assert_false(player.get_viewport().get_camera_3d().global_basis.is_equal_approx(original_basis))
	assert_false(hud.is_scope_visible())
	Input.action_press("fire")
	await wait_physics_frames(5)
	Input.action_release("fire")
	var camera: Camera3D = player.get_viewport().get_camera_3d()
	assert_almost_eq(camera.fov, OpticMath.fov_for_zoom(ViewSettings.fov_degrees,3.5),0.0001)
	Input.action_release("aim")
	ViewSettings.hybrid_lens = old_lens
	ViewSettings.ads_sensitivity_multiplier = old_ads

func test_lens_follows_rendered_camera_and_stops_rendering_when_hidden() -> void:
	var old: bool = ViewSettings.hybrid_lens
	ViewSettings.hybrid_lens = true
	var world := Node3D.new()
	add_child_autofree(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.transform = Transform3D(Basis.from_euler(Vector3(0.1,0.3,0)),Vector3(3,5,2))
	var overlay := HybridOptic.new()
	world.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	overlay.size = Vector2(1280,720)
	var build := WeaponBuild.new(load("res://weapons/data/halberd_rifle.tres") as WeaponData)
	build.set_attachment(WeaponTypes.Slot.OPTIC, HYBRID)
	overlay.update_view(build.get_stats(),1.0,camera)
	if not HybridOptic.LENS_MODE_AVAILABLE:
		assert_false(HybridOptic.uses_lens(), "Saved lens preference falls back to Mode A")
		assert_true(overlay.visible)
		assert_false(overlay.lens_active)
		assert_null(overlay.viewport)
		ViewSettings.hybrid_lens = old
		return
	assert_true(overlay.lens_active)
	assert_eq(overlay.lens_camera.global_transform,camera.global_transform)
	assert_eq(overlay.viewport.size, Vector2i(256,256))
	assert_eq(overlay.viewport.world_3d,camera.get_world_3d())
	assert_eq(overlay.viewport.render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	camera.rotate_x(0.2)
	overlay.update_view(build.get_stats(),1.0,camera)
	assert_eq(overlay.lens_camera.global_transform,camera.global_transform)
	overlay.update_view(build.get_stats(),0.0,camera)
	assert_false(overlay.visible)
	assert_eq(overlay.viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	ViewSettings.hybrid_lens = old
