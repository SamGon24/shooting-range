extends GutTest
## Proves the headless GUT pipeline works and that the project settings the
## rest of the game depends on are actually in effect.


func test_gut_runs() -> void:
	assert_eq(1 + 1, 2, "GUT is wired up")


func test_physics_tick_is_60_hz() -> void:
	assert_eq(Engine.physics_ticks_per_second, 60)


func test_physics_engine_is_jolt() -> void:
	assert_eq(str(ProjectSettings.get_setting("physics/3d/physics_engine")), "Jolt Physics")


func test_gravity_is_si() -> void:
	assert_almost_eq(float(ProjectSettings.get_setting("physics/3d/default_gravity")), 9.81, 0.0001)


func test_renderer_is_compatibility() -> void:
	assert_eq(str(ProjectSettings.get_setting("rendering/renderer/rendering_method")), "gl_compatibility")


func test_window_is_720p() -> void:
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_width")), 1280)
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_height")), 720)
