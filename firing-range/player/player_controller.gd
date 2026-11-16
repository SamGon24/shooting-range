class_name PlayerController
extends CharacterBody3D
## First-person movement: walk, sprint, crouch, jump and slide.
##
## All gameplay runs in `_physics_process` at the fixed 60 Hz tick, using the
## pure functions in `MovementMath` and the numbers in `MovementSettings`.
## `_process` only places the camera rig between ticks; it never changes
## movement state. Feel effects (bob, FOV kick) live in `CameraFeel` and only
## read from this node.

signal jumped
signal landed(impact_speed: float)
signal stance_changed(new_stance: Stance)
signal slide_started
signal slide_ended

enum Stance { STAND, CROUCH, SLIDE }

const MAX_PITCH: float = deg_to_rad(89.0)

@export var settings: MovementSettings

## Multiplies mouse sensitivity. Weapons will lower this while aiming.
var look_sensitivity_scale: float = 1.0

## When false the player ignores mouse look and gives the cursor back to the
## OS. Automated runs (tests, Movie Maker captures, the perf probe) turn this
## off so they never grab the real mouse; a pause menu can use it too.
var mouse_look_enabled: bool = true:
	set(value):
		mouse_look_enabled = value
		if is_inside_tree():
			_apply_mouse_mode()

## Look angles in radians. Yaw turns around +Y, pitch is positive looking up.
var yaw: float = 0.0
var pitch: float = 0.0
## View kick from weapon recoil, radians, on top of `pitch` and `yaw` (same
## signs). Weapons add to it and let it recover; mouse movement against it
## cancels it first. Bullets and the camera both follow it.
var recoil_pitch: float = 0.0
var recoil_yaw: float = 0.0

var stance: Stance = Stance.STAND
var is_sprinting: bool = false

var _gravity: float = 9.81
var _capsule: CapsuleShape3D
var _height: float = 1.8
var _previous_height: float = 1.8
var _time_since_grounded: float = 0.0
var _jump_buffer: float = 0.0
var _jump_consumed: bool = false
var _slide_boost_cooldown: float = 0.0
var _was_on_floor: bool = true
var _just_landed: bool = false
## Recoil offset at the start of the physics tick (x pitch, y yaw), so the
## camera can blend a kick between ticks.
var _previous_recoil: Vector2 = Vector2.ZERO

@onready var _collider: CollisionShape3D = $Collider
@onready var _head: Node3D = $Head


func _ready() -> void:
	if settings == null:
		push_error("PlayerController: no MovementSettings assigned; using defaults.")
		settings = MovementSettings.new()

	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity"))

	# The capsule is symmetric, so the body itself never rotates. Take the
	# spawn facing as the initial yaw and keep the look angles as plain floats.
	yaw = global_rotation.y
	global_rotation = Vector3.ZERO

	_capsule = CapsuleShape3D.new()
	_capsule.radius = settings.capsule_radius
	_collider.shape = _capsule
	_height = settings.stand_height
	_previous_height = _height
	_apply_height()

	floor_max_angle = deg_to_rad(settings.floor_max_angle_degrees)
	floor_snap_length = settings.floor_snap_length
	floor_constant_speed = true

	_update_head(1.0)
	reset_physics_interpolation()

	if DisplayServer.get_name() == "headless" or OS.has_feature("movie"):
		mouse_look_enabled = false
	_apply_mouse_mode()


func _unhandled_input(event: InputEvent) -> void:
	if not mouse_look_enabled:
		return
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion := event as InputEventMouseMotion
			_apply_look(motion.screen_relative)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		# Esc frees the mouse; clicking the window grabs it again.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	_update_head(Engine.get_physics_interpolation_fraction())


func _physics_process(delta: float) -> void:
	_previous_height = _height
	_previous_recoil = Vector2(recoil_pitch, recoil_yaw)

	var on_floor: bool = is_on_floor()
	var move_input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var crouch_held: bool = Input.is_action_pressed("crouch")
	var crouch_pressed: bool = Input.is_action_just_pressed("crouch")
	var sprint_held: bool = Input.is_action_pressed("sprint")

	_tick_timers(delta, on_floor)
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = settings.jump_buffer_time

	_update_stance(on_floor, crouch_held, crouch_pressed)

	# Sprint needs forward input and a standing stance. `move_input.y` is
	# negative when pushing forward.
	is_sprinting = (
		sprint_held
		and stance == Stance.STAND
		and -move_input.y >= settings.sprint_min_forward
	)

	var wish_dir: Vector3 = Basis(Vector3.UP, yaw) * Vector3(move_input.x, 0.0, move_input.y)
	var input_strength: float = minf(move_input.length(), 1.0)
	var wish_speed: float = settings.target_speed(stance != Stance.STAND, is_sprinting) * input_strength

	_update_horizontal_velocity(delta, on_floor, wish_dir, wish_speed)
	var jumped_this_tick: bool = _try_jump(on_floor)
	var airborne: bool = jumped_this_tick or not on_floor

	# Gravity is applied as two half steps around the move (velocity Verlet),
	# which makes the jump arc match the analytic parabola at any tick rate.
	if airborne:
		velocity.y -= _gravity * delta * 0.5
		floor_snap_length = 0.0
	else:
		velocity.y = 0.0
		floor_snap_length = settings.floor_snap_length

	var fall_speed: float = maxf(-velocity.y, 0.0)
	move_and_slide()

	var on_floor_after: bool = is_on_floor()
	if not on_floor_after:
		velocity.y -= _gravity * delta * 0.5

	_just_landed = on_floor_after and not _was_on_floor
	if _just_landed:
		landed.emit(fall_speed)
	_was_on_floor = on_floor_after

	_update_height(delta)


# --- Public read-only API (used by camera feel, debug overlay, later weapons) ---


func get_horizontal_speed() -> float:
	return MovementMath.horizontal_speed(velocity)


func is_grounded() -> bool:
	return _was_on_floor


func is_crouched() -> bool:
	return stance != Stance.STAND


func is_sliding() -> bool:
	return stance == Stance.SLIDE


## Current collider height in metres.
func get_height() -> float:
	return _height


## Eye height above the feet at the last physics tick, in metres.
func get_eye_height() -> float:
	return settings.eye_height_for(_height)


## Gameplay eye position at the last physics tick. This is the origin for
## aiming and bullets; it ignores head bob and every other camera effect.
func get_eye_position() -> Vector3:
	return global_position + Vector3.UP * get_eye_height()


## Gameplay aim orientation (-Z is forward): the look angles plus recoil,
## without any camera effect.
func get_aim_basis() -> Basis:
	return Basis.from_euler(Vector3(_view_pitch(pitch + recoil_pitch), yaw + recoil_yaw, 0.0))


## Kicks the view by recoil, radians (positive pitch is up, positive yaw is
## to the left, as for `pitch` and `yaw`).
func add_recoil(pitch_radians: float, yaw_radians: float) -> void:
	recoil_pitch += pitch_radians
	recoil_yaw += yaw_radians


## Moves the recoil offset back towards zero by up to `radians`, along a
## straight line so pitch and yaw finish together.
func recover_recoil(radians: float) -> void:
	var offset := Vector2(recoil_pitch, recoil_yaw)
	offset = offset.move_toward(Vector2.ZERO, radians)
	recoil_pitch = offset.x
	recoil_yaw = offset.y


func get_stance_name() -> String:
	match stance:
		Stance.CROUCH:
			return "crouch"
		Stance.SLIDE:
			return "slide"
		_:
			return "stand"


## Moves the player and clears momentum, e.g. for a respawn.
func teleport(new_position: Vector3, new_yaw: float = 0.0) -> void:
	global_position = new_position
	velocity = Vector3.ZERO
	yaw = new_yaw
	pitch = 0.0
	recoil_pitch = 0.0
	recoil_yaw = 0.0
	_previous_recoil = Vector2.ZERO
	_update_head(1.0)
	reset_physics_interpolation()


# --- Internals ---


func _apply_mouse_mode() -> void:
	if mouse_look_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _apply_look(relative: Vector2) -> void:
	var radians_per_count: float = deg_to_rad(ViewSettings.mouse_sensitivity) * look_sensitivity_scale
	var pitch_sign: float = -1.0 if ViewSettings.invert_y else 1.0
	# Movement against the recoil offset cancels it first (see
	# RecoilLogic.absorb). The previous-tick offset shifts by the same amount
	# so the camera blend between ticks does not jump.
	var yaw_split: Vector2 = RecoilLogic.absorb(recoil_yaw, -relative.x * radians_per_count)
	var pitch_split: Vector2 = RecoilLogic.absorb(recoil_pitch, -relative.y * radians_per_count * pitch_sign)
	_previous_recoil += Vector2(pitch_split.x - recoil_pitch, yaw_split.x - recoil_yaw)
	recoil_yaw = yaw_split.x
	recoil_pitch = pitch_split.x
	yaw = wrapf(yaw + yaw_split.y, -PI, PI)
	pitch = clampf(pitch + pitch_split.y, -MAX_PITCH, MAX_PITCH)


func _view_pitch(value: float) -> float:
	return clampf(value, -MAX_PITCH, MAX_PITCH)


func _tick_timers(delta: float, on_floor: bool) -> void:
	if on_floor:
		_time_since_grounded = 0.0
		_jump_consumed = false
	else:
		_time_since_grounded += delta
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_slide_boost_cooldown = maxf(_slide_boost_cooldown - delta, 0.0)


func _update_stance(on_floor: bool, crouch_held: bool, crouch_pressed: bool) -> void:
	var speed: float = get_horizontal_speed()

	if stance == Stance.SLIDE:
		if not crouch_held or not on_floor or speed <= settings.slide_end_speed:
			_end_slide(crouch_held)
		return

	if crouch_held:
		var wants_slide: bool = crouch_pressed or _just_landed
		if on_floor and wants_slide and speed >= settings.slide_min_entry_speed:
			_start_slide()
		else:
			_set_stance(Stance.CROUCH)
	elif stance == Stance.CROUCH and _can_stand():
		_set_stance(Stance.STAND)


func _start_slide() -> void:
	var boost: float = settings.slide_boost if _slide_boost_cooldown <= 0.0 else 0.0
	velocity = MovementMath.slide_entry_velocity(velocity, boost, settings.slide_max_speed)
	_slide_boost_cooldown = settings.slide_boost_cooldown
	_set_stance(Stance.SLIDE)
	slide_started.emit()


func _end_slide(crouch_held: bool) -> void:
	if crouch_held or not _can_stand():
		_set_stance(Stance.CROUCH)
	else:
		_set_stance(Stance.STAND)
	slide_ended.emit()


func _set_stance(new_stance: Stance) -> void:
	if stance == new_stance:
		return
	stance = new_stance
	stance_changed.emit(stance)


func _update_horizontal_velocity(delta: float, on_floor: bool, wish_dir: Vector3, wish_speed: float) -> void:
	if not on_floor:
		velocity = MovementMath.accelerate_capped(velocity, wish_dir, wish_speed, settings.air_accel, delta)
	elif stance == Stance.SLIDE:
		velocity = MovementMath.slide_decay(velocity, settings.slide_deceleration, delta)
		# Steering only: the wish speed equals the current speed, so this can
		# turn the slide but never speed it up.
		var slide_speed: float = get_horizontal_speed()
		velocity = MovementMath.accelerate_capped(
			velocity, wish_dir, slide_speed, settings.slide_steer_accel, delta
		)
	else:
		velocity = MovementMath.ground_move(
			velocity,
			wish_dir,
			wish_speed,
			settings.ground_accel,
			settings.ground_friction,
			settings.stop_speed,
			delta
		)


func _try_jump(on_floor: bool) -> bool:
	if _jump_buffer <= 0.0 or _jump_consumed:
		return false
	var grounded_enough: bool = on_floor or _time_since_grounded <= settings.coyote_time
	if not grounded_enough:
		return false

	_jump_buffer = 0.0
	_jump_consumed = true
	velocity.y = MovementMath.jump_velocity(settings.jump_height, _gravity)
	if stance == Stance.SLIDE:
		# Slide-jump: keep the horizontal momentum, leave the slide.
		_end_slide(Input.is_action_pressed("crouch"))
	jumped.emit()
	return true


func _update_height(delta: float) -> void:
	var target: float = settings.stand_height if stance == Stance.STAND else settings.crouch_height
	if is_equal_approx(_height, target):
		return
	_height = move_toward(_height, target, settings.crouch_transition_speed * delta)
	_apply_height()


func _apply_height() -> void:
	# Feet stay at the body origin; the capsule grows and shrinks from the top.
	_capsule.height = _height
	_collider.position.y = _height * 0.5


## True if there is room above the head to return to standing height.
func _can_stand() -> bool:
	var rise: float = settings.stand_height - _height
	if rise <= 0.0:
		return true
	return not test_move(global_transform, Vector3.UP * rise)


## Places the camera rig. `fraction` is how far we are between the previous
## physics tick (0) and the current one (1).
func _update_head(fraction: float) -> void:
	var eye: float = settings.eye_height_for(lerpf(_previous_height, _height, fraction))
	var origin: Vector3 = get_global_transform_interpolated().origin
	var recoil: Vector2 = _previous_recoil.lerp(Vector2(recoil_pitch, recoil_yaw), fraction)
	_head.global_transform = Transform3D(
		Basis.from_euler(Vector3(_view_pitch(pitch + recoil.x), yaw + recoil.y, 0.0)), origin + Vector3.UP * eye
	)
