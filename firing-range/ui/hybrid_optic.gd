class_name HybridOptic
extends Control
## Native-pixel lens render and original housing. Presentation only.
const LENS_HEIGHT_FRACTION: float = 0.52
var lens: ColorRect
var lens_active: bool = false
var sample_zoom: float = 1.0
var viewport: SubViewport
var lens_camera: Camera3D
var render_size: int = 0
var carrier: Node2D
var eye_alignment: float = 0.0
var _window_size: Vector2 = Vector2.ZERO
var _material: ShaderMaterial

static func supports(data: WeaponData) -> bool:
	return data != null and data.optic_kind in [2, 3, 5]

func _ready() -> void:
	add_to_group(&"hybrid_optic")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	carrier = Node2D.new()
	carrier.name = "AnimatedOptic"
	add_child(carrier)
	lens = ColorRect.new()
	lens.name = "ScopeLens"
	lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = preload("res://ui/hybrid_lens.gdshader")
	lens.material = _material
	carrier.add_child(lens)
	hide()

func update_view(data: WeaponData, aim: float, source: Camera3D, pose: Dictionary = {}) -> void:
	visible = supports(data) and source != null and not pose.is_empty()
	lens_active = false
	if not visible:
		_stop_render()
		return
	var actual: Transform3D = pose["world"]
	var rest: Transform3D = pose["rest"]
	var radius_m: float = pose["radius"]
	if source.is_position_behind(actual.origin) or source.to_local(actual.origin).z >= -source.near:
		hide()
		_stop_render()
		return
	var to_eye: Vector3 = (source.global_position - actual.origin).normalized()
	if actual.basis.z.normalized().dot(to_eye) <= 0.01:
		hide()
		_stop_render()
		return
	var actual_center: Vector2 = _project(source, actual.origin)
	var rest_center: Vector2 = _project(source, rest.origin)
	var actual_x: Vector2 = _project(source, actual * (Vector3.RIGHT * radius_m)) - actual_center
	var actual_y: Vector2 = _project(source, actual * (Vector3.DOWN * radius_m)) - actual_center
	var rest_radius: float = (_project(source, rest * (Vector3.RIGHT * radius_m)) - rest_center).length()
	var diameter: float = size.y * LENS_HEIGHT_FRACTION
	var radius: float = diameter * 0.5
	var aimed: float = smoothstep(0.0, 1.0, clampf(aim, 0.0, 1.0))
	var boost: float = lerpf(1.0, radius / maxf(rest_radius, 0.001), aimed)
	var center: Vector2 = actual_center + (size * 0.5 - rest_center) * aimed
	var axis_x: Vector2 = actual_x * boost / maxf(radius, 0.001)
	var axis_y: Vector2 = actual_y * boost / maxf(radius, 0.001)
	if absf(axis_x.cross(axis_y)) < 0.0001:
		hide()
		_stop_render()
		return
	carrier.transform = Transform2D(axis_x, axis_y, center)
	var extent: float = diameter + 80.0 * size.y / 720.0
	lens.position = -Vector2.ONE * extent * 0.5
	lens.size = Vector2.ONE * extent
	_material.set_shader_parameter(&"radius", radius)
	_material.set_shader_parameter(&"unit", size.y / 720.0)
	eye_alignment = smoothstep(0.95, 0.995, actual.basis.z.normalized().dot(to_eye))
	_material.set_shader_parameter(&"view_strength", eye_alignment)
	var screen_bounds := Rect2(center - Vector2.ONE * extent, Vector2.ONE * extent * 2.0)
	visible = screen_bounds.intersects(Rect2(Vector2.ZERO, size))
	lens_active = visible and eye_alignment > 0.02
	if not lens_active:
		_stop_render()
		return
	var target_fov: float = OpticMath.target_fov(data, ViewSettings.fov_degrees)
	sample_zoom = OpticMath.screen_lens_zoom(source.fov, target_fov)
	if viewport == null:
		_create_viewport(source)
	# Cache a high-water resolution per window size; sway must not recreate
	# the render target every frame. Never undersample the projected glass.
	var apparent_diameter: float = diameter * maxf(axis_x.length(), axis_y.length())
	var required_size: int = maxi(64, ceili(maxf(diameter, apparent_diameter) / 64.0) * 64)
	if required_size > render_size or _window_size != size:
		render_size = required_size
		viewport.size = Vector2i.ONE * render_size
		_window_size = size
	var scale: float = 2.0 * tan(deg_to_rad(source.fov) * 0.5) / maxf(size.y, 1.0)
	var ray_local := Vector3((center.x-size.x*0.5)*scale, -(center.y-size.y*0.5)*scale, -1.0).normalized()
	var direction: Vector3 = source.global_basis * ray_local
	lens_camera.global_transform = Transform3D(Basis.looking_at(direction, actual.basis.y.normalized()), source.global_position)
	lens_camera.cull_mask = source.cull_mask & ~WeaponView.VIEWMODEL_LAYER
	lens_camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(target_fov) * 0.5) * apparent_diameter / maxf(size.y, 1.0)))
	lens_camera.near = source.near
	lens_camera.far = source.far
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _stop_render() -> void:
	if viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _create_viewport(source: Camera3D) -> void:
	viewport = SubViewport.new()
	viewport.name = "NativeScopeRender"
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.world_3d = source.get_world_3d()
	viewport.gui_disable_input = true
	viewport.audio_listener_enable_3d = false
	add_child(viewport)
	lens_camera = Camera3D.new()
	lens_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(lens_camera)
	lens_camera.current = true
	_material.set_shader_parameter(&"lens_image", viewport.get_texture())


## FPS cameras use vertical FOV. Project the current presentation transform,
## including transforms changed this frame before the renderer updates.
func _project(source: Camera3D, world_position: Vector3) -> Vector2:
	var point: Vector3 = source.global_transform.affine_inverse() * world_position
	var scale: float = size.y / (2.0 * tan(deg_to_rad(source.fov) * 0.5))
	return size * 0.5 + Vector2(point.x, -point.y) * scale / maxf(-point.z, 0.001)
