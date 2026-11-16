extends GutTest


func test_spread_radius_matches_projection_and_fov() -> void:
	var crosshair := Crosshair.new()
	add_child_autofree(crosshair)
	crosshair.set_spread(2.0, 65.0, 720.0)
	var expected: float = tan(deg_to_rad(2.0)) * 360.0 / tan(deg_to_rad(65.0) * 0.5)
	assert_almost_eq(crosshair.spread_radius, expected, 0.0001)
	crosshair.set_spread(2.0, 45.0, 720.0)
	assert_gt(crosshair.spread_radius, expected)
	crosshair.set_spread(0.0, 65.0, 720.0)
	assert_eq(crosshair.spread_radius, 0.0)


func test_marker_colors_priority_and_expiry() -> void:
	var view := FeedbackView.new()
	add_child_autofree(view)
	view.set_process(false)
	view.show_feedback(HitFeedback.Kind.HIT, Vector3.ZERO, 0.0, false)
	assert_eq(view.get_marker_color(), Color.WHITE)
	view.show_feedback(HitFeedback.Kind.ARMOR_BREAK, Vector3.ZERO, 0.0, false)
	assert_eq(view.get_marker_color(), view.armor_color)
	view.show_feedback(HitFeedback.Kind.KILL, Vector3.ZERO, 0.0, false)
	assert_eq(view.get_marker_color(), view.kill_color)
	view.show_feedback(HitFeedback.Kind.HIT, Vector3.ZERO, 0.0, false)
	assert_eq(view.marker_kind, HitFeedback.Kind.KILL)
	view._process(view.marker_hold_seconds + view.marker_fade_seconds + 0.01)
	assert_false(view.is_marker_active())


func test_number_pool_reuses_labels_and_headshot_color_is_distinct() -> void:
	var view := FeedbackView.new()
	view.number_capacity = 4
	add_child_autofree(view)
	var nodes: int = get_tree().get_node_count()
	for index: int in 20:
		view.show_feedback(HitFeedback.Kind.HIT, Vector3(0, 1, -25), 48.0, index % 2 == 0)
	assert_eq(get_tree().get_node_count(), nodes)
	assert_eq(view.get_child_count(), 4)
	var head := view.get_child(0) as Label
	var body := view.get_child(1) as Label
	assert_eq(head.get_theme_color("font_color"), view.headshot_color)
	assert_eq(body.get_theme_color("font_color"), view.number_color)
	assert_ne(view.headshot_color, view.number_color)
	assert_eq(head.text, "48")
	view._process(view.number_lifetime + 0.01)
	assert_false(head.visible)
