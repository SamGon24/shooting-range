extends GutTest

const RANGE_SCENE: PackedScene = preload("res://range/range.tscn")


func test_required_distances_armor_and_both_speeds_at_both_rails() -> void:
	var scene := RANGE_SCENE.instantiate() as RangeBuilder
	add_child_autofree(scene)
	await wait_physics_frames(2)
	var targets: Node = scene.get_node("Targets")
	for distance: int in [25, 50, 100, 200, 300]:
		var dummy := targets.get_node("Dummy%dm" % distance) as TargetDummy
		assert_eq(dummy.position.z, -float(distance))
		assert_eq(dummy.zones.size(), 6)
		assert_between(dummy.state.armor, 0.0, 150.0)
	for distance: int in [50, 100]:
		for label: String in ["Walk", "Sprint"]:
			var rail := targets.get_node("Rail%d%s" % [distance, label]) as TargetRail
			assert_eq(rail.position.z, -float(distance))
			assert_eq(rail.speed, 1.5 if label == "Walk" else 6.0)
			assert_true(rail.get_child(0) is TargetDummy)
	for distance: int in [100, 200, 300]:
		var plate := targets.get_node("Steel%dm" % distance) as SteelPlate
		assert_eq(plate.position.z, -float(distance))
		assert_not_null(plate.hinge)
