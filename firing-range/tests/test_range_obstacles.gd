extends GutTest
## The player against the movement test area of the real range scene: ramp
## and crouch tunnel. Runs in real time on the Jolt physics server.

const RANGE_SCENE: PackedScene = preload("res://range/range.tscn")
const ACTIONS: Array[StringName] = [&"move_forward", &"crouch", &"sprint", &"jump"]
## Facing +Z, i.e. away from the targets, toward the test area.
const FACING_BACK: float = PI

var _range: RangeBuilder
var _player: PlayerController
var _settings: MovementSettings


func before_each() -> void:
	_range = RANGE_SCENE.instantiate() as RangeBuilder
	add_child_autofree(_range)
	_player = _range.get_node("Player") as PlayerController
	_settings = _player.settings
	await wait_physics_frames(5)


func after_each() -> void:
	for action: StringName in ACTIONS:
		Input.action_release(action)


func _seconds(seconds: float) -> int:
	return roundi(seconds * float(Engine.physics_ticks_per_second))


func test_walks_up_the_ramp_onto_the_platform_at_constant_speed() -> void:
	# Ramp starts at z = 10 and climbs 1.5 m toward +Z; platform follows.
	_player.teleport(Vector3(12.0, 0.0, 8.5), FACING_BACK)
	await wait_physics_frames(3)
	Input.action_press("move_forward")

	await wait_physics_frames(_seconds(1.2))
	assert_gt(_player.global_position.y, 0.2, "climbing the ramp")
	assert_true(_player.is_on_floor(), "stays glued to the slope")
	assert_almost_eq(_player.velocity.length(), _settings.walk_speed, 0.15, "no slowdown going uphill")

	await wait_physics_frames(_seconds(1.3))
	assert_almost_eq(_player.global_position.y, 1.5, 0.05, "standing on the 1.5 m platform")
	assert_true(_player.is_on_floor())


func test_cannot_enter_the_crouch_tunnel_standing() -> void:
	# Tunnel roof spans z = 19..25 with 1.3 m of headroom.
	_player.teleport(Vector3(0.0, 0.0, 16.0), FACING_BACK)
	await wait_physics_frames(3)
	Input.action_press("move_forward")
	await wait_physics_frames(_seconds(2.0))
	assert_lt(_player.global_position.z, 19.0, "blocked by the tunnel roof")
	assert_gt(_player.global_position.z, 18.0, "but walked right up to it")


func test_crouch_walks_through_the_tunnel_and_cannot_stand_inside() -> void:
	_player.teleport(Vector3(0.0, 0.0, 16.0), FACING_BACK)
	await wait_physics_frames(3)
	Input.action_press("crouch")
	Input.action_press("move_forward")

	# 16 m -> about 22 m at crouch speed: the middle of the tunnel.
	await wait_physics_frames(_seconds(2.9))
	assert_between(_player.global_position.z, 20.0, 24.0, "inside the tunnel")

	Input.action_release("crouch")
	await wait_physics_frames(_seconds(0.3))
	assert_eq(_player.stance, PlayerController.Stance.CROUCH, "no room to stand, so stays crouched")
	assert_between(_player.global_position.z, 20.0, 24.5, "still inside")

	await wait_physics_frames(_seconds(3.0))
	assert_gt(_player.global_position.z, 25.5, "came out the far end")
	assert_eq(_player.stance, PlayerController.Stance.STAND, "and stood up once clear")
