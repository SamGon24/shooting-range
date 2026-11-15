class_name MovementSettings
extends Resource
## All player movement tuning. Units are SI: metres, seconds, m/s, m/s^2.
## The live values are in `player/data/movement_default.tres`.

@export_group("Speeds")
## Target ground speed when walking, m/s.
@export_range(0.5, 12.0, 0.1, "suffix:m/s") var walk_speed: float = 4.5
## Target ground speed when sprinting, m/s.
@export_range(0.5, 14.0, 0.1, "suffix:m/s") var sprint_speed: float = 7.0
## Target ground speed when crouched, m/s.
@export_range(0.5, 8.0, 0.1, "suffix:m/s") var crouch_speed: float = 2.2
## Forward input (0..1) needed to sprint. 0.5 allows forward diagonals but
## not pure strafing or backpedalling.
@export_range(0.0, 1.0, 0.05) var sprint_min_forward: float = 0.5

@export_group("Ground")
## Acceleration rate, 1/s. Actual acceleration is this times the target
## speed, so 9 at walk speed 4.5 is about 40 m/s^2 from rest. Must be greater
## than `ground_friction` or the player never reaches the target speed.
@export_range(1.0, 30.0, 0.1, "suffix:1/s") var ground_accel: float = 9.0
## Friction rate, 1/s. Speed decays as exp(-friction * t) above `stop_speed`.
@export_range(0.0, 20.0, 0.1, "suffix:1/s") var ground_friction: float = 6.0
## Below this speed friction acts as if moving at this speed, so the player
## comes to a clean stop instead of creeping. m/s.
@export_range(0.0, 6.0, 0.1, "suffix:m/s") var stop_speed: float = 2.5

@export_group("Air")
## Air steering rate, 1/s. Air control can redirect momentum but never adds
## speed beyond what the player took off with.
@export_range(0.0, 10.0, 0.1, "suffix:1/s") var air_accel: float = 1.5

@export_group("Jump")
## Apex height of a standing jump, metres. Jump velocity is derived from this
## and gravity, so changing gravity keeps the jump height.
@export_range(0.1, 2.0, 0.01, "suffix:m") var jump_height: float = 0.65
## Grace period after walking off a ledge during which a jump still works.
@export_range(0.0, 0.3, 0.01, "suffix:s") var coyote_time: float = 0.1
## A jump pressed this long before landing fires on the landing tick.
@export_range(0.0, 0.3, 0.01, "suffix:s") var jump_buffer_time: float = 0.1

@export_group("Slide")
## Minimum horizontal speed to start a slide, m/s. Sits above walk speed so
## only a sprint (or carried momentum) can slide.
@export_range(0.0, 12.0, 0.1, "suffix:m/s") var slide_min_entry_speed: float = 5.5
## Speed added when a slide starts, m/s.
@export_range(0.0, 6.0, 0.1, "suffix:m/s") var slide_boost: float = 1.5
## The boost never pushes speed above this, m/s.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var slide_max_speed: float = 9.0
## Constant deceleration while sliding, m/s^2 (kinetic friction, mu * g).
@export_range(0.0, 20.0, 0.1, "suffix:m/s²") var slide_deceleration: float = 6.0
## The slide ends and becomes a crouch at this speed, m/s.
@export_range(0.0, 8.0, 0.1, "suffix:m/s") var slide_end_speed: float = 3.0
## How quickly the slide direction can be steered, 1/s. 0 locks direction.
@export_range(0.0, 10.0, 0.1, "suffix:1/s") var slide_steer_accel: float = 2.0
## Seconds after a slide starts before another slide gets the boost again.
## Slides inside the cooldown still work, just without the speed boost.
@export_range(0.0, 5.0, 0.1, "suffix:s") var slide_boost_cooldown: float = 1.5

@export_group("Body")
@export_range(0.2, 0.6, 0.01, "suffix:m") var capsule_radius: float = 0.35
@export_range(1.0, 2.2, 0.01, "suffix:m") var stand_height: float = 1.8
## Collider height when crouched or sliding, metres.
@export_range(0.7, 1.8, 0.01, "suffix:m") var crouch_height: float = 1.1
## Eye position below the top of the collider, metres.
@export_range(0.0, 0.4, 0.01, "suffix:m") var eye_offset_from_top: float = 0.12
## How fast the collider and eye height change between stances, m/s.
@export_range(0.5, 12.0, 0.1, "suffix:m/s") var crouch_transition_speed: float = 3.5

@export_group("Floor")
## Distance the body is pulled down to stay glued to floors and ramps.
@export_range(0.0, 1.0, 0.01, "suffix:m") var floor_snap_length: float = 0.25
## Steepest walkable slope, degrees.
@export_range(0.0, 89.0, 1.0, "suffix:°") var floor_max_angle_degrees: float = 45.0


## Target ground speed for a stance/sprint combination.
func target_speed(is_crouched: bool, is_sprinting: bool) -> float:
	if is_crouched:
		return crouch_speed
	if is_sprinting:
		return sprint_speed
	return walk_speed


## Eye height above the feet for a given collider height.
func eye_height_for(collider_height: float) -> float:
	return collider_height - eye_offset_from_top
