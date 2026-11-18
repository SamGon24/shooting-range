class_name WeaponPreview
extends SubViewportContainer
## One isolated, bounded preview world. It never connects to gameplay signals.
var logic: WeaponLogic
var _viewport: SubViewport
var _pivot: Node3D
var _model: Node3D
var _definition: WeaponData
var _animator: WeaponAnimator
var _input: WeaponInput = WeaponInput.new()
var _angle: float = 0.0
var _centre: Vector3 = Vector3.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(300, 280)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	stretch = true
	stretch_shrink = 1
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(450, 480)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var world := Node3D.new()
	_viewport.add_child(world)
	var environment := WorldEnvironment.new()
	var tuning := Environment.new()
	tuning.background_mode = Environment.BG_COLOR
	tuning.background_color = Color(0.075, 0.09, 0.10)
	tuning.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	tuning.ambient_light_color = Color(0.8, 0.85, 0.9)
	tuning.ambient_light_energy = 0.65
	environment.environment = tuning
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.5
	world.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0.12, 1.65)
	camera.rotation_degrees.x = -4
	camera.fov = 48
	camera.near = 0.01
	world.add_child(camera)
	_pivot = Node3D.new()
	world.add_child(_pivot)
	set_physics_process(false)
	set_process(false)


func show_build(build: WeaponBuild) -> void:
	if _model != null:
		_model.free()
	_definition = build.base
	_model = _definition.viewmodel_scene.instantiate() as Node3D
	# Remove native optics before binding: no detached nodes remain to leak.
	if build.get_attachment(WeaponTypes.Slot.OPTIC) != null:
		for part_name: String in ["RearSight", "FrontSightPost", "Scope", "ScopeBell", "ScopeMountFront", "ScopeMountRear"]:
			var native: Node = _model.get_node_or_null(part_name)
			if native != null:
				native.free()
	for attachment: AttachmentData in build.get_attachments():
		var mount := _model.get_node_or_null("Mounts/" + WeaponTypes.SLOT_NAMES[attachment.slot]) as Node3D
		if mount != null and attachment.part_scene != null:
			var part := attachment.part_scene.instantiate() as Node3D
			mount.add_child(part)
			var point := part.get_node(attachment.part_mount) as Node3D
			part.transform = point.transform.affine_inverse()
	_pivot.add_child(_model)
	logic = WeaponLogic.new(build.get_stats())
	logic.equip_instantly()
	_angle = 0.9
	# Fit all actual meshes, including long barrels and the shield.
	var bounds: AABB = _bounds(_model, Transform3D.IDENTITY)
	_centre = bounds.get_center()
	_model.position -= _centre
	_animator = WeaponAnimator.new()
	_animator.bind(_definition, _model)
	var extent: float = maxf(bounds.size.length(), 0.25)
	_pivot.scale = Vector3.ONE * (1.15 / extent)
	set_physics_process(true)
	set_process(true)
	_process(0.0)


func _bounds(node: Node3D, parent_transform: Transform3D) -> AABB:
	var result := AABB()
	var transform: Transform3D = parent_transform * node.transform
	if node is MeshInstance3D:
		result = transform * (node as MeshInstance3D).get_aabb()
	for child: Node in node.get_children():
		if child is Node3D:
			var child_bounds: AABB = _bounds(child as Node3D, transform)
			if child_bounds.size != Vector3.ZERO:
				result = child_bounds if result.size == Vector3.ZERO else result.merge(child_bounds)
	return result


func rotate_by(direction: float) -> void:
	_angle += direction * PI / 6.0


func demonstrate() -> void:
	if logic == null:
		return
	logic.equip_instantly()
	if logic.data.uses_ammo:
		logic.ammo = 0
		_input.reload_pressed = true
	else:
		_input.trigger_pressed = true
		_input.trigger_held = true


func _physics_process(delta: float) -> void:
	logic.tick(delta, _input)
	_input.reload_pressed = false
	_input.trigger_pressed = false
	_input.trigger_held = false


func _process(_delta: float) -> void:
	if logic == null:
		return
	# Same ordering as WeaponView: pose parts before writing the pivot.
	_animator.apply(_definition, logic, logic.raise_progress)
	_pivot.rotation = Vector3(0.12, _angle, 0)
