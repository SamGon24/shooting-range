extends GutTest
## Integration tests: the real player scene on a flat Jolt floor, driven
## through the input map, stepped by real physics ticks.
##
## These run in real time (60 ticks per second), so they take a few seconds.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"sprint", &"crouch",
]
const SPEED_TOLERANCE: float = 0.05

var _world: Node3D
var _player: PlayerController
var _settings: MovementSettings


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)
	_add_slab(Vector3(400.0, 1.0, 400.0), Vector3(0.0, -0.5, 0.0))

	_player = PLAYER_SCENE.instantiate() as PlayerController
	_world.add_child(_player)
	_settings = _player.settings
	await wait_physics_frames(10)


func after_each() -> void:
	for action: StringName in ACTIONS:
		Input.action_release(action)


func _add_slab(size: Vector3, centre: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	body.position = centre
	_world.add_child(body)
	return body


func _seconds(seconds: float) -> int:
	return roundi(seconds * float(Engine.physics_ticks_per_second))


# --- Spawn ---


func test_spawns_standing_on_the_floor() -> void:
	assert_true(_player.is_on_floor(), "on the floor")
	assert_almost_eq(_player.global_position.y, 0.0, 0.02, "feet at ground level")
	assert_eq(_player.stance, PlayerController.Stance.STAND)
	assert_almost_eq(_player.get_height(), _settings.stand_height, 0.0001)
	assert_almost_eq(_player.get_horizontal_speed(), 0.0, 0.001, "at rest")


func test_eye_position_is_at_standing_eye_height() -> void:
	var expected: float = _settings.stand_height - _settings.eye_offset_from_top
	assert_almost_eq(_player.get_eye_position().y, expected, 0.02)


# --- Walk ---


func test_walk_builds_up_speed_instead_of_snapping() -> void:
	Input.action_press("move_forward")
	await wait_physics_frames(3)
	var early_speed: float = _player.get_horizontal_speed()
	assert_gt(early_speed, 0.0, "started moving")
	assert_lt(early_speed, _settings.walk_speed * 0.7, "not at full speed after 3 ticks")


func test_walk_settles_at_walk_speed_heading_forward() -> void:
	Input.action_press("move_forward")
	await wait_physics_frames(_seconds(1.0))
	assert_almost_eq(_player.get_horizontal_speed(), _settings.walk_speed, SPEED_TOLERANCE)
	assert_lt(_player.global_position.z, -2.0, "moved toward -Z (downrange)")
	assert_almost_eq(_player.global_position.x, 0.0, 0.01, "no sideways drift")
	assert_false(_player.is_sprinting)


func test_diagonal_walk_is_not_faster() -> void:
	Input.action_press("move_forward")
	Input.action_press("move_right")
	await wait_physics_frames(_seconds(1.0))
	assert_almost_eq(_player.get_horizontal_speed(), _settings.walk_speed, SPEED_TOLERANCE)


func test_releasing_input_coasts_then_stops() -> void:
	Input.action_press("move_forward")
	await wait_physics_frames(_seconds(1.0))
	Input.action_release("move_forward")
	await wait_physics_frames(3)
	assert_gt(_player.get_horizontal_speed(), 0.5, "still carrying momentum just after release")
	await wait_physics_frames(_seconds(1.0))
	assert_almost_eq(_player.get_horizontal_speed(), 0.0, 0.001, "then comes to a full stop")


func test_movement_follows_yaw() -> void:
	_player.yaw = deg_to_rad(90.0)  # Facing -X.
	Input.action_press("move_forward")
	await wait_physics_frames(_seconds(1.0))
	assert_lt(_player.global_position.x, -2.0, "forward is -X after turning 90 degrees left")
	assert_almost_eq(_player.global_position.z, 0.0, 0.01)


# --- Sprint ---


func test_sprint_reaches_sprint_speed() -> void:
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait_physics_frames(_seconds(1.5))
	assert_true(_player.is_sprinting)
	assert_almost_eq(_player.get_horizontal_speed(), _settings.sprint_speed, SPEED_TOLERANCE)


func test_cannot_sprint_backwards_or_sideways() -> void:
	Input.action_press("sprint")
	Input.action_press("move_back")
	await wait_physics_frames(_seconds(1.0))
	assert_false(_player.is_sprinting, "no sprint while backpedalling")
	assert_almost_eq(_player.get_horizontal_speed(), _settings.walk_speed, SPEED_TOLERANCE)

	Input.action_release("move_back")
	Input.action_press("move_right")
	await wait_physics_frames(_seconds(1.0))
	assert_false(_player.is_sprinting, "no sprint while strafing")
	assert_almost_eq(_player.get_horizontal_speed(), _settings.walk_speed, SPEED_TOLERANCE)


# --- Crouch ---


func test_crouch_lowers_body_and_slows_movement() -> void:
	Input.action_press("crouch")
	Input.action_press("move_forward")
	await wait_physics_frames(_seconds(1.0))
	assert_eq(_player.stance, PlayerController.Stance.CROUCH)
	assert_almost_eq(_player.get_height(), _settings.crouch_height, 0.0001)
	assert_almost_eq(_player.get_horizontal_speed(), _settings.crouch_speed, SPEED_TOLERANCE)
	assert_true(_player.is_on_floor(), "stays grounded while the collider shrinks")


func test_crouch_height_changes_gradually() -> void:
	Input.action_press("crouch")
	await wait_physics_frames(3)
	var height: float = _player.get_height()
	assert_lt(height, _settings.stand_height, "started lowering")
	assert_gt(height, _settings.crouch_height, "but has not snapped to crouch height")


func test_releasing_crouch_stands_back_up() -> void:
	Input.action_press("crouch")
	await wait_physics_frames(_seconds(0.5))
	Input.action_release("crouch")
	await wait_physics_frames(_seconds(0.5))
	assert_eq(_player.stance, PlayerController.Stance.STAND)
	assert_almost_eq(_player.get_height(), _settings.stand_height, 0.0001)


func test_cannot_stand_up_under_a_low_ceiling() -> void:
	Input.action_press("crouch")
	await wait_physics_frames(_seconds(0.5))
	# Slab whose underside is 1.3 m up: room to crouch (1.1 m), not to stand.
	var ceiling: StaticBody3D = _add_slab(Vector3(4.0, 0.2, 4.0), Vector3(0.0, 1.4, 0.0))
	await wait_physics_frames(2)

	Input.action_release("crouch")
	await wait_physics_frames(_seconds(0.5))
	assert_eq(_player.stance, PlayerController.Stance.CROUCH, "stays crouched under the ceiling")
	assert_almost_eq(_player.get_height(), _settings.crouch_height, 0.0001)

	ceiling.queue_free()
	await wait_physics_frames(_seconds(0.5))
	assert_eq(_player.stance, PlayerController.Stance.STAND, "stands once the ceiling is gone")


# --- Jump ---


func test_jump_reaches_configured_height_and_lands() -> void:
	watch_signals(_player)
	Input.action_press("jump")
	var apex: float = 0.0
	var left_ground: bool = false
	for _tick: int in _seconds(1.2):
		await wait_physics_frames(1)
		apex = maxf(apex, _player.global_position.y)
		if not _player.is_on_floor():
			left_ground = true
	Input.action_release("jump")

	assert_true(left_ground, "left the ground")
	assert_almost_eq(apex, _settings.jump_height, 0.03, "apex matches jump_height")
	assert_true(_player.is_on_floor(), "landed again")
	assert_almost_eq(_player.global_position.y, 0.0, 0.02, "back at ground level")
	assert_signal_emit_count(_player, "jumped", 1, "holding jump does not auto-repeat")
	assert_signal_emit_count(_player, "landed", 1)


func test_jump_keeps_horizontal_momentum() -> void:
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait_physics_frames(_seconds(1.5))
	Input.action_press("jump")
	await wait_physics_frames(10)
	assert_false(_player.is_on_floor(), "airborne")
	assert_almost_eq(_player.get_horizontal_speed(), _settings.sprint_speed, 0.1)


func test_air_control_does_not_add_speed() -> void:
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait_physics_frames(_seconds(1.5))
	Input.action_press("jump")
	Input.action_press("move_right")
	var top_speed: float = 0.0
	for _tick: int in 30:
		await wait_physics_frames(1)
		top_speed = maxf(top_speed, _player.get_horizontal_speed())
	assert_lte(top_speed, _settings.sprint_speed + SPEED_TOLERANCE)


# --- Slide ---


func test_crouch_while_sprinting_starts_a_boosted_slide() -> void:
	watch_signals(_player)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait_physics_frames(_seconds(1.5))
	Input.action_press("crouch")
	await wait_physics_frames(2)

	assert_eq(_player.stance, PlayerController.Stance.SLIDE)
	assert_signal_emitted(_player, "slide_started")
	assert_gt(_player.get_horizontal_speed(), _settings.sprint_speed, "slide entry adds speed")
	assert_lte(_player.get_horizontal_speed(), _settings.slide_max_speed + 0.001)


func test_slide_speed_decays_every_tick_then_becomes_a_crouch() -> void:
	watch_signals(_player)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait_physics_frames(_seconds(1.5))
	Input.action_press("crouch")
	await wait_physics_frames(2)

	# `wait_physics_frames(1)` can span more than one tick, so time the slide
	# with the engine's own physics tick counter.
	var entry_speed: float = _player.get_horizontal_speed()
	var start_tick: int = Engine.get_physics_frames()
	var end_tick: int = start_tick
	var previous: float = entry_speed
	while _player.stance == PlayerController.Stance.SLIDE and end_tick - start_tick < _seconds(4.0):
		await wait_physics_frames(1)
		end_tick = Engine.get_physics_frames()
		if _player.stance != PlayerController.Stance.SLIDE:
			break
		var speed: float = _player.get_horizontal_speed()
		assert_lt(speed, previous, "slide loses speed every tick")
		previous = speed

	var measured: float = float(end_tick - start_tick) / float(Engine.physics_ticks_per_second)
	var expected: float = MovementMath.slide_duration(
		entry_speed, _settings.slide_end_speed, _settings.slide_deceleration
	)
	assert_almost_eq(measured, expected, 0.06, "slide lasts as long as the math predicts")
	assert_eq(_player.stance, PlayerController.Stance.CROUCH, "ends in a crouch while crouch is held")
	assert_signal_emitted(_player, "slide_ended")

	await wait_physics_frames(_seconds(1.0))
	assert_almost_eq(_player.get_horizontal_speed(), _settings.crouch_speed, SPEED_TOLERANCE)


func test_crouch_at_walk_speed_does_not_slide() -> void:
	Input.action_press("move_forward")
	await wait_physics_frames(_seconds(1.0))
	Input.action_press("crouch")
	await wait_physics_frames(2)
	assert_eq(_player.stance, PlayerController.Stance.CROUCH)


func test_releasing_crouch_ends_the_slide() -> void:
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait_physics_frames(_seconds(1.5))
	Input.action_press("crouch")
	await wait_physics_frames(6)
	assert_eq(_player.stance, PlayerController.Stance.SLIDE)
	Input.action_release("crouch")
	await wait_physics_frames(2)
	assert_eq(_player.stance, PlayerController.Stance.STAND)


func test_second_slide_inside_cooldown_gets_no_boost() -> void:
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait_physics_frames(_seconds(1.5))
	Input.action_press("crouch")
	await wait_physics_frames(4)
	Input.action_release("crouch")
	await wait_physics_frames(2)
	assert_eq(_player.stance, PlayerController.Stance.STAND)

	var speed_before: float = _player.get_horizontal_speed()
	Input.action_press("crouch")
	await wait_physics_frames(1)
	assert_eq(_player.stance, PlayerController.Stance.SLIDE, "can still slide")
	assert_lte(_player.get_horizontal_speed(), speed_before + 0.001, "but without a second boost")


func test_jumping_out_of_a_slide_keeps_speed() -> void:
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await wait_physics_frames(_seconds(1.5))
	Input.action_press("crouch")
	await wait_physics_frames(6)
	var slide_speed: float = _player.get_horizontal_speed()
	Input.action_press("jump")
	await wait_physics_frames(3)
	assert_false(_player.is_on_floor(), "airborne")
	assert_ne(_player.stance, PlayerController.Stance.SLIDE, "no longer sliding")
	assert_almost_eq(_player.get_horizontal_speed(), slide_speed, 0.4, "momentum carried into the jump")
