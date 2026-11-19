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
	var two: AttachmentData = load("res://weapons/attachments/data/scope_2x.tres")
	for optic: AttachmentData in [two, HYBRID, four]:
		Input.action_release("aim")
		assert_true(controller.request_attachment(WeaponTypes.Slot.OPTIC, optic))
		await wait_physics_frames(4)
		Input.action_press("aim")
		await wait_physics_frames(60)
		assert_false(hud.is_scope_visible(), "No blackout for " + optic.display_name)
		assert_true(hud.hybrid.visible)
		assert_true(hud.hybrid.lens_active)
		var view := player.get_node("Head/CameraFeel/Camera/WeaponView") as WeaponView
		assert_true(view.is_model_shown())
		assert_eq((view.get_current_model().get_node("Receiver") as MeshInstance3D).layers, WeaponView.VIEWMODEL_LAYER)
		assert_eq(hud.hybrid.find_children("*", "SubViewport", true, false).size(), 1)
		assert_gte(float(hud.hybrid.render_size), hud.hybrid.size.y * HybridOptic.LENS_HEIGHT_FRACTION)
		assert_eq(hud.hybrid.lens_camera.cull_mask & WeaponView.VIEWMODEL_LAYER, 0)
		var camera: Camera3D = player.get_viewport().get_camera_3d()
		assert_almost_eq(camera.fov, ViewSettings.fov_degrees, 0.0001)
		assert_almost_eq(hud.hybrid.sample_zoom, OpticMath.screen_lens_zoom(camera.fov, OpticMath.target_fov(controller.get_current_data(), ViewSettings.fov_degrees)), 0.0001)
		if optic == HYBRID:
			assert_almost_eq(player.look_sensitivity_scale, 1.0/3.5, 0.00001)
		else:
			assert_almost_eq(player.look_sensitivity_scale, controller.get_current_data().ads_sensitivity_scale, 0.00001)
		var anchor_before: Transform3D = view.get_optic_pose()["world"]
		var original_basis: Basis = camera.global_basis
		player.add_recoil(0.1, 0.04)
		await wait_physics_frames(2)
		assert_true(view.get_optic_pose().has("world"))
		assert_ne(anchor_before.origin, Vector3.ZERO)
		assert_false(camera.global_basis.is_equal_approx(original_basis))
		Input.action_press("fire")
		await wait_physics_frames(5)
		Input.action_release("fire")
		assert_false(hud.is_scope_visible())
		await wait_physics_frames(10)
	Input.action_release("aim")
	ViewSettings.ads_sensitivity_multiplier = old_ads

func test_native_lens_resolution_projection_and_render_lifecycle() -> void:
	for reference: float in [50.0,65.0,100.0]:
		var target: float = OpticMath.fov_for_zoom(reference,3.5)
		assert_almost_eq(OpticMath.screen_lens_zoom(reference,target),3.5,0.000001)
	assert_almost_eq(OpticMath.screen_lens_zoom(65,18.098708656),4.0,0.000001)
	var world := Node3D.new()
	add_child_autofree(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.transform = Transform3D(Basis.from_euler(Vector3(0.1,0.3,0)), Vector3(3,5,2))
	var overlay := HybridOptic.new()
	world.add_child(overlay)
	var build := WeaponBuild.new(load("res://weapons/data/halberd_rifle.tres") as WeaponData)
	build.set_attachment(WeaponTypes.Slot.OPTIC, HYBRID)
	overlay.update_view(build.get_stats(),1.0,camera,_aligned_pose(camera))
	assert_true(overlay.visible)
	assert_gte(float(overlay.render_size), overlay.size.y * HybridOptic.LENS_HEIGHT_FRACTION)
	assert_eq(overlay.viewport.world_3d, camera.get_world_3d())
	assert_true(overlay.lens_camera.global_transform.is_equal_approx(camera.global_transform))
	assert_almost_eq(tan(deg_to_rad(overlay.lens_camera.fov)*0.5) / HybridOptic.LENS_HEIGHT_FRACTION, tan(deg_to_rad(OpticMath.target_fov(build.get_stats(), ViewSettings.fov_degrees))*0.5),0.00001)
	assert_eq(overlay.viewport.render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	camera.rotate_x(0.2)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	overlay.size = Vector2(1920,1080)
	overlay.update_view(build.get_stats(),1.0,camera,_aligned_pose(camera))
	assert_true(overlay.lens_camera.global_transform.is_equal_approx(camera.global_transform))
	assert_gte(overlay.render_size,562)
	overlay.update_view(build.get_stats(),0.0,camera,{})
	assert_false(overlay.visible)
	assert_false(overlay.lens_active)
	assert_eq(overlay.viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	var sniper: WeaponData = load("res://weapons/data/longwatch_sniper.tres")
	assert_false(HybridOptic.supports(sniper), "8x keeps its existing presentation")


func _aligned_pose(camera: Camera3D) -> Dictionary:
	var world: Transform3D = camera.global_transform * Transform3D(Basis.IDENTITY,Vector3(0,0,-0.35))
	return {"world":world,"rest":world,"radius":0.026}

func test_optic_tracks_weapon_translation_roll_and_lowering_without_steering_aim() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	var overlay := HybridOptic.new()
	world.add_child(overlay)
	var build := WeaponBuild.new(load("res://weapons/data/halberd_rifle.tres") as WeaponData)
	build.set_attachment(WeaponTypes.Slot.OPTIC,HYBRID)
	var pose: Dictionary = _aligned_pose(camera)
	overlay.update_view(build.get_stats(),1.0,camera,pose)
	var centered: Vector2 = overlay.carrier.position
	var render_before: int = overlay.render_size
	var shifted: Transform3D = pose["world"]
	shifted.origin.x += 0.03
	shifted.basis = shifted.basis.rotated(Vector3.FORWARD,0.3)
	pose["world"] = shifted
	overlay.update_view(build.get_stats(),1.0,camera,pose)
	assert_gt(overlay.carrier.position.x,centered.x)
	assert_gt(absf(overlay.carrier.transform.x.y),0.01)
	assert_gte(overlay.render_size,render_before)
	var big: float = overlay.carrier.transform.x.length()
	shifted.origin = Vector3(0.16,-0.12,-0.42)
	pose["world"] = shifted
	overlay.update_view(build.get_stats(),0.0,camera,pose)
	assert_true(overlay.visible,"Housing stays with the weapon at the hip")
	assert_gt(overlay.carrier.position.x,centered.x)
	assert_gt(overlay.carrier.position.y,centered.y)
	assert_lt(overlay.carrier.transform.x.length(),big)
	assert_false(overlay.lens_active,"Off-axis glass stops the extra render")
	assert_eq(overlay.viewport.render_target_update_mode,SubViewport.UPDATE_DISABLED)
	shifted.origin = Vector3(0,0,-0.35)
	shifted.basis = Basis(Vector3.UP,PI*0.5)
	pose["world"] = shifted
	overlay.update_view(build.get_stats(),1.0,camera,pose)
	assert_false(overlay.visible,"Edge-on glass leaves the real model visible without a singular overlay")
	assert_false(overlay.lens_active)
	assert_eq(camera.transform,Transform3D.IDENTITY,"Presentation cannot steer gameplay camera")

func test_reload_animator_moves_optic_with_weapon_without_changing_gameplay_aim() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	world.add_child(ProjectileSystem.new())
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerController
	world.add_child(player)
	player.set_physics_process(false)
	var controller := player.get_node("Weapons") as WeaponController
	var view := player.get_node("Head/CameraFeel/Camera/WeaponView") as WeaponView
	var hud := (load("res://ui/hud.tscn") as PackedScene).instantiate() as Hud
	world.add_child(hud)
	controller.request_attachment(WeaponTypes.Slot.OPTIC,HYBRID)
	await wait_physics_frames(4)
	Input.action_press("aim")
	await wait_physics_frames(60)
	var initial: Transform2D = hud.hybrid.carrier.transform
	var aim_before: Basis = player.get_aim_basis()
	controller.get_current_logic().ammo -= 1
	Input.action_press("reload")
	await wait_physics_frames(1)
	Input.action_release("reload")
	assert_true(controller.get_current_logic().is_reloading())
	var travel: float = 0.0
	var roll: float = 0.0
	for sample: int in 16:
		await wait_physics_frames(2)
		travel = maxf(travel,hud.hybrid.carrier.position.distance_to(initial.origin))
		roll = maxf(roll,absf(hud.hybrid.carrier.transform.get_rotation()-initial.get_rotation()))
	assert_gt(travel,2.0,"Reload motion carries the optic away from its aimed position")
	assert_gt(roll,0.02,"Reload roll rotates the optic housing and reticle")
	assert_true(view.is_model_shown())
	assert_true(player.get_aim_basis().is_equal_approx(aim_before),"Cosmetic reload cannot steer bullets")
	Input.action_release("aim")
