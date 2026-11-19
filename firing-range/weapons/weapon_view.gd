class_name WeaponView
extends Node3D
## First-person viewmodel and aim zoom. Cosmetic only.
##
## Shows the current weapon's greybox model in front of the camera and moves
## it: hip and aimed poses, sway that trails the mouse, bob while walking,
## inertia from jumping and strafing, a recoil kick per shot, and raise,
## lower and sprint poses. Reload, action-cycle, equip and melee motions of
## individual parts come from each weapon's `HandlingProfile` through
## `WeaponAnimator`. It also tells `CameraFeel` how far to zoom.
##
## Everything here reads from the player and the weapon controller. Bullets
## leave from the player's gameplay eye, so nothing in this file can change
## where they go.

## Emitted when a shot's muzzle flash is shown, with the muzzle's world
## position. For effects that want to start at the barrel.
signal muzzle_flashed(world_position: Vector3)

## The flash is hidden by shrinking it, not with `visible`; see
## `_set_model_shown` for why.
const VIEWMODEL_LAYER: int = 1 << 19

const GROUP: StringName = &"weapon_view"
const FLASH_HIDDEN_SCALE: Vector3 = Vector3(0.0001, 0.0001, 0.0001)

@export var controller: WeaponController
@export var player: PlayerController
@export var camera_feel: CameraFeel

@export_group("Sway")
## Seconds of turn rate the weapon trails behind the view. Higher is looser.
@export_range(0.0, 0.1, 0.001, "suffix:s") var sway_lag: float = 0.018
@export_range(0.0, 15.0, 0.1, "suffix:°") var sway_max_degrees: float = 4.0
@export_range(1.0, 40.0, 0.5, "suffix:1/s") var sway_blend_rate: float = 12.0

@export_group("Bob")
## Metres travelled per full bob cycle.
@export_range(0.5, 6.0, 0.05, "suffix:m") var bob_stride_length: float = 2.6
@export_range(0.0, 0.05, 0.001, "suffix:m") var bob_horizontal_amplitude: float = 0.008
@export_range(0.0, 0.05, 0.001, "suffix:m") var bob_vertical_amplitude: float = 0.006
@export_range(0.5, 12.0, 0.1, "suffix:m/s") var bob_reference_speed: float = 4.5
@export_range(1.0, 30.0, 0.5, "suffix:1/s") var bob_blend_rate: float = 10.0

@export_group("Inertia")
## Metres the weapon lifts per m/s of falling speed (and drops when rising).
@export_range(0.0, 0.02, 0.0005) var inertia_vertical_per_speed: float = 0.006
@export_range(0.0, 0.1, 0.001, "suffix:m") var inertia_vertical_max: float = 0.03
## Degrees of roll per m/s of sideways speed.
@export_range(0.0, 3.0, 0.05) var inertia_roll_per_speed: float = 0.6
@export_range(1.0, 30.0, 0.5, "suffix:1/s") var inertia_blend_rate: float = 8.0

@export_group("Recoil kick")
## Spring that returns the weapon after a shot. Higher is snappier.
@export_range(20.0, 800.0, 5.0) var kick_spring_stiffness: float = 260.0
@export_range(0.2, 2.0, 0.05) var kick_spring_damping_ratio: float = 0.8

@export_group("Poses")
## How much sway, bob and inertia remain when fully aimed.
@export_range(0.0, 1.0, 0.05) var aimed_motion_scale: float = 0.25
## Offset and pitch when the weapon is put away.
@export var lens_ads_offset: Vector3 = Vector3(0.0, -0.04, 0.04)
@export var lowered_offset: Vector3 = Vector3(0.02, -0.32, 0.06)
@export_range(0.0, 90.0, 1.0, "suffix:°") var lowered_pitch_degrees: float = 45.0
## Offset and angles while sprinting.
@export var sprint_offset: Vector3 = Vector3(-0.05, -0.05, 0.05)
@export var sprint_rotation_degrees: Vector3 = Vector3(-12.0, 32.0, 8.0)
@export_range(1.0, 30.0, 0.5, "suffix:1/s") var sprint_blend_rate: float = 9.0
## The 8x weapon model is hidden above this aim blend (the HUD draws the
## blackout scope instead).
@export_range(0.5, 1.0, 0.01) var scope_hide_threshold: float = 0.85

@export_group("Muzzle flash")
@export_range(0.01, 0.2, 0.005, "suffix:s") var flash_duration: float = 0.045
@export var flash_color: Color = Color(1.0, 0.85, 0.45)

var _pivot: Node3D
var _models: Dictionary[WeaponData, Node3D] = {}
var _muzzles: Dictionary[WeaponData, Node3D] = {}
var _attachment_parts: Dictionary[WeaponData, Array] = {}
var _native_optics: Dictionary[WeaponData, Array] = {}
var _optic_anchor: Marker3D
var _optic_rest: Transform3D = Transform3D.IDENTITY
var _optic_radius: float = 0.0
var _model_rests: Dictionary[WeaponData, Transform3D] = {}
var _current_data: WeaponData
var _flash_mesh: MeshInstance3D
var _flash_particles: CPUParticles3D
var _flash_time_left: float = 0.0

var _last_yaw: float = 0.0
var _last_pitch: float = 0.0
var _sway: Vector2 = Vector2.ZERO
var _bob_phase: float = 0.0
var _bob_weight: float = 0.0
var _inertia_y: float = 0.0
var _inertia_roll: float = 0.0
var _kick: float = 0.0
var _kick_velocity: float = 0.0
var _sprint_blend: float = 0.0
var _animator: WeaponAnimator = WeaponAnimator.new()
## Lives beside the player in the world, outside the camera rig, so the
## dropped copies are ordinary interpolated physics bodies.
var _drop_pool: MagazineDropPool
var _casings: CasingPool
var _smoke: MuzzleSmoke
## A casing waiting for its bolt or pump to open: the weapon and seconds left.
var _casing_pending: WeaponData
var _casing_time_left: float = 0.0


func _ready() -> void:
	if controller == null or player == null or camera_feel == null:
		push_error("WeaponView: `controller`, `player` and `camera_feel` must be assigned.")
		set_process(false)
		return

	add_to_group(GROUP)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)

	for data: WeaponData in controller.get_available_definitions():
		if data.viewmodel_scene == null:
			continue
		# Models wait outside the tree until they are the current weapon.
		var model := data.viewmodel_scene.instantiate() as Node3D
		_set_viewmodel_layer(model)
		_model_rests[data] = model.transform
		_models[data] = model
		_native_optics[data] = []
		for part_name: String in ["RearSight", "FrontSightPost", "Scope", "ScopeBell", "ScopeMountFront", "ScopeMountRear"]:
			var native: Node3D = model.get_node_or_null(part_name) as Node3D
			if native != null:
				_native_optics[data].append(native)
		_muzzles[data] = model.get_node_or_null("Muzzle") as Node3D
		_animator.bind(data, model)

	_build_muzzle_flash()
	_warm_up_flash.call_deferred()
	if player.get_parent() != null:
		_drop_pool = MagazineDropPool.new()
		_drop_pool.name = "MagazineDrops"
		player.add_sibling.call_deferred(_drop_pool)
		_casings = CasingPool.new()
		_casings.name = "Casings"
		player.add_sibling.call_deferred(_casings)
		_smoke = MuzzleSmoke.new()
		_smoke.name = "MuzzleSmoke"
		player.add_sibling.call_deferred(_smoke)
		_animator.copy_released.connect(_on_copy_released)
	_last_yaw = player.yaw
	_last_pitch = player.pitch
	controller.weapon_changed.connect(_on_weapon_changed)
	controller.shot_fired.connect(_on_shot_fired)
	if controller.get_current_data() != null:
		_on_weapon_changed(controller.get_current_data())


func _process(delta: float) -> void:
	if _current_data == null or delta <= 0.0:
		return
	var fraction: float = Engine.get_physics_interpolation_fraction()
	var aim: float = smoothstep(0.0, 1.0, controller.get_aim_blend(fraction))
	var raise: float = smoothstep(0.0, 1.0, controller.get_raise_blend(fraction))
	var motion_scale: float = lerpf(1.0, aimed_motion_scale, aim)

	camera_feel.aim_blend = aim
	camera_feel.aim_fov_degrees = _current_data.ads_fov_degrees
	if HybridOptic.supports(_current_data):
		camera_feel.aim_fov_degrees = ViewSettings.fov_degrees

	_update_sway(delta)
	_update_bob(delta)
	_update_inertia(delta)
	_step_kick_spring(delta)
	_sprint_blend = lerpf(_sprint_blend, 1.0 if player.is_sprinting else 0.0, _blend(sprint_blend_rate, delta))

	var bob_scale: float = ViewSettings.head_bob_scale * motion_scale
	var offset: Vector3 = _current_data.hip_position.lerp(_current_data.ads_position, aim)
	if HybridOptic.supports(_current_data):
		offset += lens_ads_offset * aim
	offset.x += sin(_bob_phase) * bob_horizontal_amplitude * _bob_weight * bob_scale
	offset.y -= absf(sin(_bob_phase)) * bob_vertical_amplitude * _bob_weight * bob_scale
	offset.y += _inertia_y * motion_scale
	offset.z += _kick * _current_data.kick_back
	offset += lowered_offset * (1.0 - raise)
	offset += sprint_offset * _sprint_blend

	var angles := Vector3.ZERO
	angles.x = _sway.y * motion_scale + deg_to_rad(_current_data.kick_pitch_degrees) * _kick
	angles.y = _sway.x * motion_scale
	angles.z = deg_to_rad(_inertia_roll) * motion_scale
	angles.x -= deg_to_rad(lowered_pitch_degrees) * (1.0 - raise)
	angles += sprint_rotation_degrees * (PI / 180.0) * _sprint_blend

	# Parts must be posed before the pivot is written. Under the camera rig
	# (interpolation off), the renderer only picked up model-part transforms
	# that changed before the pivot's transform propagated down to them.
	_animator.apply(_current_data.definition(), controller.get_current_logic(), controller.get_raise_blend(fraction))
	_tick_pending_casing(delta)
	_pivot.position = offset
	_pivot.rotation = angles

	_set_model_shown(_current_data.definition(), not (_current_data.optic_kind == 4 and aim >= scope_hide_threshold))

	if _flash_time_left > 0.0:
		_flash_time_left -= delta
		if _flash_time_left <= 0.0:
			_flash_mesh.scale = FLASH_HIDDEN_SCALE


## True when the scoped view should replace the viewmodel on screen.
func is_scope_view_active() -> bool:
	if _current_data == null or _current_data.optic_kind != 4:
		return false
	return camera_feel.aim_blend >= scope_hide_threshold


func get_current_model() -> Node3D:
	return _models.get(_current_data.definition()) if _current_data != null else null


## True if the current weapon's model is on screen (false while scoped in).
func is_model_shown() -> bool:
	var model: Node3D = get_current_model()
	return model != null and model.is_inside_tree()


func _notification(what: int) -> void:
	# Models that are not the current weapon live outside the tree, so they
	# are not freed with it.
	if what == NOTIFICATION_PREDELETE:
		# A view freed before its deferred add leaves the pool orphaned.
		_free_if_orphaned(_drop_pool)
		_free_if_orphaned(_casings)
		_free_if_orphaned(_smoke)
		for nodes: Array in _native_optics.values():
			for native: Node3D in nodes:
				if is_instance_valid(native) and native.get_parent() == null:
					native.free()
		for model: Node3D in _models.values():
			if is_instance_valid(model) and not model.is_inside_tree():
				model.free()


func get_animator() -> WeaponAnimator:
	return _animator


func get_drop_pool() -> MagazineDropPool:
	return _drop_pool


func get_casing_pool() -> CasingPool:
	return _casings


func get_muzzle_smoke() -> MuzzleSmoke:
	return _smoke


## Frees an effects pool that was never added to the world.
func _free_if_orphaned(pool: Variant) -> void:
	if is_instance_valid(pool) and (pool as Node).get_parent() == null:
		(pool as Node).free()


## Current visual recoil, 0 at rest. For tests and debugging.
func get_kick() -> float:
	return _kick


# --- Motion ---


func _update_sway(delta: float) -> void:
	var yaw_rate: float = angle_difference(_last_yaw, player.yaw) / delta
	var pitch_rate: float = (player.pitch - _last_pitch) / delta
	_last_yaw = player.yaw
	_last_pitch = player.pitch
	# The weapon trails the view: turning left leaves it pointing a little right.
	var limit: float = deg_to_rad(sway_max_degrees)
	var target := Vector2(
		clampf(-yaw_rate * sway_lag, -limit, limit),
		clampf(-pitch_rate * sway_lag, -limit, limit)
	)
	_sway = _sway.lerp(target, _blend(sway_blend_rate, delta))


func _update_bob(delta: float) -> void:
	var speed: float = player.get_horizontal_speed()
	var target: float = 0.0
	if player.is_grounded() and not player.is_sliding():
		target = clampf(speed / bob_reference_speed, 0.0, 1.5)
		_bob_phase = wrapf(_bob_phase + speed * delta / bob_stride_length * TAU, 0.0, TAU * 2.0)
	_bob_weight = lerpf(_bob_weight, target, _blend(bob_blend_rate, delta))


func _update_inertia(delta: float) -> void:
	var velocity: Vector3 = player.velocity
	var target_y: float = clampf(
		-velocity.y * inertia_vertical_per_speed, -inertia_vertical_max, inertia_vertical_max
	)
	# Sideways speed in view space: positive when moving right.
	var sideways: float = velocity.dot(Basis(Vector3.UP, player.yaw).x)
	var target_roll: float = -sideways * inertia_roll_per_speed
	var blend: float = _blend(inertia_blend_rate, delta)
	_inertia_y = lerpf(_inertia_y, target_y, blend)
	_inertia_roll = lerpf(_inertia_roll, target_roll, blend)


## Damped spring pulling the recoil kick back to rest. Sub-stepped so a long
## frame cannot make it unstable.
func _step_kick_spring(delta: float) -> void:
	const MAX_STEP: float = 1.0 / 120.0
	var damping: float = 2.0 * sqrt(kick_spring_stiffness) * kick_spring_damping_ratio
	var remaining: float = minf(delta, 0.1)
	while remaining > 0.0:
		var step: float = minf(remaining, MAX_STEP)
		_kick_velocity += (-kick_spring_stiffness * _kick - damping * _kick_velocity) * step
		_kick += _kick_velocity * step
		remaining -= step


func _blend(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


# --- Events ---


func _on_weapon_changed(data: WeaponData) -> void:
	if _current_data != null:
		_animator.reset(_current_data.definition())
	_rebuild_attachments(data)
	for other: WeaponData in _models:
		_set_model_shown(other, other == data.definition())
	_current_data = data
	_kick = 0.0
	_kick_velocity = 0.0
	_flash_mesh.scale = FLASH_HIDDEN_SCALE
	_flash_time_left = 0.0

	# The flash rides on the current weapon's muzzle.
	var muzzle: Node3D = _muzzles.get(data.definition())
	if muzzle != null and _flash_mesh.get_parent() != muzzle:
		_flash_mesh.reparent(muzzle, false)
		_flash_particles.reparent(muzzle, false)


func _on_copy_released(part: Node3D, follower: Node3D) -> void:
	if _drop_pool != null and _drop_pool.is_inside_tree():
		_drop_pool.release(part, follower, player.velocity)


func _on_shot_fired(data: WeaponData) -> void:
	if data != _current_data:
		return
	# Jump straight to the kicked pose; the spring brings it back.
	_kick = 1.0
	_kick_velocity = 0.0
	# Queued even when scoped: a bolt or pump throws its casing a moment
	# later, and the eject step skips itself while no model is on screen.
	_queue_casing(data)

	if is_scope_view_active() or (data.delivery != null and data.delivery.kind == DeliveryData.Kind.MELEE):
		return
	_flash_mesh.rotation.z = randf() * TAU
	_flash_mesh.scale = Vector3.ONE
	_flash_time_left = flash_duration
	_flash_particles.restart()
	_flash_particles.emitting = true
	muzzle_flashed.emit(_flash_mesh.global_position)
	_puff_smoke(data)


## Pays the muzzle sparks' first-draw cost before the first shot. The flash
## mesh itself is always drawn (at negligible size), so only the sparks need it.
func _warm_up_flash() -> void:
	if not ParticleWarmup.is_needed():
		return
	await ParticleWarmup.settle(self)
	ParticleWarmup.warm(_flash_particles, Vector3.ZERO)


## Smoke from the muzzle: a pooled emitter restarted where the barrel is now.
func _puff_smoke(data: WeaponData) -> void:
	if _smoke == null or not _smoke.is_inside_tree() or data.muzzle_smoke_particles <= 0:
		return
	var muzzle: Node3D = _muzzles.get(data.definition())
	if muzzle == null or not muzzle.is_inside_tree():
		return
	_smoke.puff(muzzle.global_position, -muzzle.global_basis.z, data.muzzle_smoke_particles)


## Throws the casing now, or after the bolt or pump has had time to open. A
## second shot flushes a casing still waiting for the first.
func _queue_casing(data: WeaponData) -> void:
	if _casings == null or data.casing_size == Vector3.ZERO:
		return
	if _casing_pending != null:
		_eject_casing(_casing_pending)
		_casing_pending = null
	if data.casing_eject_delay_s <= 0.0:
		_eject_casing(data)
	else:
		_casing_pending = data
		_casing_time_left = data.casing_eject_delay_s


func _tick_pending_casing(delta: float) -> void:
	if _casing_pending == null:
		return
	_casing_time_left -= delta
	if _casing_time_left <= 0.0:
		var data: WeaponData = _casing_pending
		_casing_pending = null
		_eject_casing(data)


## The casing leaves the port of the model as it is on screen now. A scoped
## view has no model in the tree, so nothing is thrown then.
func _eject_casing(data: WeaponData) -> void:
	if _casings == null or not _casings.is_inside_tree() or data.definition() != _current_data.definition():
		return
	var model: Node3D = _models.get(data.definition())
	if model == null or not model.is_inside_tree():
		return
	var port := Transform3D(Basis.IDENTITY, data.casing_port)
	_casings.eject(model.global_transform * port, data.casing_size, data.casing_color, player.velocity)


## Adds or removes a weapon's model from the tree.
##
## This deliberately does not use `visible`. The camera rig has physics
## interpolation turned off, and in Godot 4.7 toggling `visible` on a node in
## such a subtree stops the renderer receiving its later transform changes:
## the model freezes on screen while the script keeps moving it.
func _set_model_shown(data: WeaponData, shown: bool) -> void:
	var model: Node3D = _models.get(data)
	if model == null or model.is_inside_tree() == shown:
		return
	if shown:
		_pivot.add_child(model)
	else:
		_pivot.remove_child(model)


func _build_muzzle_flash() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = flash_color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Two crossed boxes read as a star-shaped flash from any angle.
	var flash := BoxMesh.new()
	flash.size = Vector3(0.09, 0.012, 0.12)
	flash.material = material
	_flash_mesh = MeshInstance3D.new()
	_flash_mesh.name = "MuzzleFlash"
	_flash_mesh.mesh = flash
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_mesh.scale = FLASH_HIDDEN_SCALE
	var cross := MeshInstance3D.new()
	cross.mesh = flash
	cross.rotation.z = PI * 0.5
	cross.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_mesh.add_child(cross)
	_flash_mesh.layers = VIEWMODEL_LAYER
	_pivot.add_child(_flash_mesh)

	var spark := BoxMesh.new()
	spark.size = Vector3(0.006, 0.006, 0.03)
	spark.material = material
	_flash_particles = CPUParticles3D.new()
	_flash_particles.name = "MuzzleSparks"
	_flash_particles.mesh = spark
	_flash_particles.emitting = false
	_flash_particles.one_shot = true
	_flash_particles.amount = 6
	_flash_particles.lifetime = 0.08
	_flash_particles.explosiveness = 1.0
	_flash_particles.local_coords = true
	_flash_particles.direction = Vector3(0.0, 0.0, -1.0)
	_flash_particles.spread = 28.0
	_flash_particles.gravity = Vector3.ZERO
	_flash_particles.initial_velocity_min = 2.0
	_flash_particles.initial_velocity_max = 5.0
	_flash_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_particles.layers = VIEWMODEL_LAYER
	_pivot.add_child(_flash_particles)


func _rebuild_attachments(data: WeaponData) -> void:
	_optic_anchor = null
	var definition: WeaponData = data.definition()
	var model: Node3D = _models.get(definition)
	if model == null:
		return
	# Detach flash nodes before freeing a previous muzzle attachment.
	if _flash_mesh.get_parent() != _pivot:
		_flash_mesh.reparent(_pivot, false)
		_flash_particles.reparent(_pivot, false)
	for part: Node3D in _attachment_parts.get(definition, []):
		part.free()
	_attachment_parts[definition] = []
	_muzzles[definition] = model.get_node_or_null("Muzzle") as Node3D
	var build: WeaponBuild = controller.get_build(controller.get_current_slot())
	if build == null:
		return
	var has_optic: bool = build.get_attachment(WeaponTypes.Slot.OPTIC) != null
	for native: Node3D in _native_optics.get(definition, []):
		if has_optic and native.get_parent() != null:
			native.get_parent().remove_child(native)
		elif not has_optic and native.get_parent() == null:
			model.add_child(native)
	for attachment: AttachmentData in build.get_attachments():
		if attachment.part_scene == null:
			continue
		var mount := model.get_node_or_null("Mounts/" + WeaponTypes.SLOT_NAMES[attachment.slot]) as Node3D
		if mount == null:
			continue
		var part := attachment.part_scene.instantiate() as Node3D
		_set_viewmodel_layer(part)
		mount.add_child(part)
		var point := part.get_node(attachment.part_mount) as Node3D
		part.transform = point.transform.affine_inverse()
		_attachment_parts[definition].append(part)
		if attachment.slot == WeaponTypes.Slot.OPTIC:
			_optic_anchor = part.get_node_or_null("LensAnchor") as Marker3D
			if _optic_anchor != null:
				_optic_radius = float(_optic_anchor.get_meta(&"lens_radius_m"))
				var local: Transform3D = _optic_anchor.transform
				var ancestor := _optic_anchor.get_parent() as Node3D
				while ancestor != null and ancestor != model:
					local = ancestor.transform * local
					ancestor = ancestor.get_parent() as Node3D
				_optic_rest = _model_rests[definition] * local
		if attachment.slot == WeaponTypes.Slot.MUZZLE:
			_muzzles[definition] = part.get_node_or_null("Exit") as Node3D


static func _set_viewmodel_layer(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = VIEWMODEL_LAYER
	for child: Node in node.get_children():
		_set_viewmodel_layer(child)


## Read-only presentation pose after the handling animator and viewmodel pivot.
## Rest is the fully aimed pose, used to preserve the authored ADS lens framing.
func get_optic_pose() -> Dictionary:
	if not is_instance_valid(_optic_anchor) or not _optic_anchor.is_inside_tree() or _current_data == null:
		return {}
	return {
		"world": _optic_anchor.global_transform,
		"rest": global_transform * Transform3D(Basis.IDENTITY, _current_data.ads_position + lens_ads_offset) * _optic_rest,
		"radius": _optic_radius,
	}
