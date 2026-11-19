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
var _material: ShaderMaterial

static func supports(data: WeaponData) -> bool:
	return data != null and data.optic_kind in [2, 3, 5]

func _ready() -> void:
	add_to_group(&"hybrid_optic")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lens = ColorRect.new()
	lens.name = "ScopeLens"
	lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = preload("res://ui/hybrid_lens.gdshader")
	lens.material = _material
	add_child(lens)
	hide()

func update_view(data: WeaponData, aim: float, source: Camera3D) -> void:
	visible = supports(data) and aim >= 0.85 and source != null
	lens_active = visible
	if not visible:
		if viewport != null:
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var target_fov: float = OpticMath.target_fov(data, ViewSettings.fov_degrees)
	sample_zoom = OpticMath.screen_lens_zoom(source.fov, target_fov)
	var diameter: float = size.y * LENS_HEIGHT_FRACTION
	var unit: float = size.y / 720.0
	var extent: float = diameter + 80.0 * unit
	lens.position = size * 0.5 - Vector2.ONE * extent * 0.5
	lens.size = Vector2.ONE * extent
	_material.set_shader_parameter(&"radius", diameter * 0.5)
	_material.set_shader_parameter(&"unit", unit)
	if viewport == null:
		_create_viewport(source)
	# At least one freshly rendered texel per displayed lens pixel. Round up
	# to an even size to avoid resampling from a smaller image on resize.
	var required_size: int = maxi(2, ceili(diameter / 2.0) * 2)
	if required_size != render_size:
		render_size = required_size
		viewport.size = Vector2i.ONE * render_size
	lens_camera.global_transform = source.global_transform
	lens_camera.cull_mask = source.cull_mask & ~WeaponView.VIEWMODEL_LAYER
	lens_camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(target_fov) * 0.5) * LENS_HEIGHT_FRACTION))
	lens_camera.near = source.near
	lens_camera.far = source.far
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

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
