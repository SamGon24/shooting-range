extends GutTest


func test_sight_heights_are_measured_from_reference_viewmodel_geometry() -> void:
	var rifle := load("res://weapons/data/halberd_rifle.tres") as WeaponData
	var rifle_model := rifle.viewmodel_scene.instantiate() as Node3D
	autofree(rifle_model)
	var front := rifle_model.get_node("FrontSightPost") as MeshInstance3D
	var muzzle := rifle_model.get_node("Muzzle") as Marker3D
	var tip: float = front.position.y + front.mesh.get_aabb().end.y
	assert_almost_eq(rifle.sight_height_m, tip - muzzle.position.y, 0.000001)
	assert_eq(rifle.zero_distance_m, 100.0)

	var sniper := load("res://weapons/data/longwatch_sniper.tres") as WeaponData
	var sniper_model := sniper.viewmodel_scene.instantiate() as Node3D
	autofree(sniper_model)
	var scope := sniper_model.get_node("Scope") as MeshInstance3D
	muzzle = sniper_model.get_node("Muzzle") as Marker3D
	assert_almost_eq(sniper.sight_height_m, scope.position.y - muzzle.position.y, 0.000001)
	assert_eq(sniper.zero_distance_m, 100.0)
