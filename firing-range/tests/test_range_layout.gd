extends GutTest
## Checks the generated greybox range: distance markers where they claim to
## be, solid ground under the lanes, and a sensible player spawn.

const RANGE_SCENE: PackedScene = preload("res://range/range.tscn")
const EXPECTED_DISTANCES: Array[int] = [25, 50, 100, 200, 300]

var _range: RangeBuilder


func before_each() -> void:
	_range = RANGE_SCENE.instantiate() as RangeBuilder
	add_child_autofree(_range)
	await wait_physics_frames(5)


func _markers_by_distance() -> Dictionary[int, Node3D]:
	var result: Dictionary[int, Node3D] = {}
	for node: Node in get_tree().get_nodes_in_group(RangeBuilder.MARKER_GROUP):
		if _range.is_ancestor_of(node):
			result[int(node.get_meta(&"distance_m"))] = node as Node3D
	return result


func _ray_down(x: float, z: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, 50.0, z), Vector3(x, -50.0, z))
	query.collision_mask = RangeBuilder.WORLD_LAYER
	return _range.get_world_3d().direct_space_state.intersect_ray(query)


func test_has_a_marker_at_every_required_distance() -> void:
	var markers: Dictionary[int, Node3D] = _markers_by_distance()
	assert_eq(markers.size(), EXPECTED_DISTANCES.size())
	for distance: int in EXPECTED_DISTANCES:
		assert_true(markers.has(distance), "marker for %d m" % distance)


func test_markers_sit_at_their_distance_from_the_firing_line() -> void:
	var markers: Dictionary[int, Node3D] = _markers_by_distance()
	for distance: int in EXPECTED_DISTANCES:
		if not markers.has(distance):
			continue
		var marker: Node3D = markers[distance]
		assert_almost_eq(marker.global_position.z, -float(distance), 0.001, "%d m marker is at z = -%d" % [distance, distance])
		assert_almost_eq(marker.global_position.x, 0.0, 0.001)


func test_each_marker_has_a_readable_sign_on_both_sides() -> void:
	var markers: Dictionary[int, Node3D] = _markers_by_distance()
	for distance: int in EXPECTED_DISTANCES:
		if not markers.has(distance):
			continue
		var labels: Array[Node] = markers[distance].find_children("*", "Label3D", true, false)
		assert_eq(labels.size(), 2, "%d m has a sign on each side" % distance)
		for node: Node in labels:
			var label := node as Label3D
			assert_eq(label.text, str(distance))
			assert_gt(absf(label.global_position.x), _range.get_lanes_width() * 0.5, "sign is outside the lanes")


func test_ground_is_solid_at_y_zero_along_the_whole_range() -> void:
	for z: float in [2.0, -10.0, -100.0, -200.0, -300.0]:
		var hit: Dictionary = _ray_down(0.5, z)
		assert_false(hit.is_empty(), "ground under z = %.0f" % z)
		if not hit.is_empty():
			var point: Vector3 = hit["position"]
			assert_almost_eq(point.y, 0.0, 0.001, "ground height at z = %.0f" % z)


func test_lanes_are_clear_of_obstacles() -> void:
	# Lane centres, sampled downrange: nothing but ground between line and backstop.
	var half_width: float = _range.get_lanes_width() * 0.5
	for lane: int in _range.lane_count:
		var x: float = -half_width + _range.lane_width * (float(lane) + 0.5)
		for z: float in [-5.0, -25.0, -50.0, -100.0, -200.0, -300.0]:
			var hit: Dictionary = _ray_down(x, z)
			var point: Vector3 = hit.get("position", Vector3.INF)
			assert_almost_eq(point.y, 0.0, 0.001, "lane %d is flat ground at z = %.0f" % [lane + 1, z])


func test_there_is_a_backstop_behind_the_last_marker() -> void:
	var from := Vector3(0.0, 1.5, -1.0)
	var to := Vector3(0.0, 1.5, -400.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = RangeBuilder.WORLD_LAYER
	var hit: Dictionary = _range.get_world_3d().direct_space_state.intersect_ray(query)
	assert_false(hit.is_empty(), "a level shot down the middle lane hits something")
	if not hit.is_empty():
		var point: Vector3 = hit["position"]
		assert_lt(point.z, -_range.get_range_length(), "and it is beyond the furthest marker")


func test_player_spawns_behind_the_firing_line_on_the_ground() -> void:
	var player := _range.get_node("Player") as PlayerController
	assert_not_null(player)
	assert_gt(player.global_position.z, 0.0, "behind the line (line is z = 0, downrange is -Z)")
	assert_true(player.is_on_floor())
	assert_almost_eq(player.global_position.y, 0.0, 0.02)
	assert_almost_eq(player.yaw, 0.0, 0.0001, "facing downrange")
