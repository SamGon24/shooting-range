class_name HybridOptic
extends Control
## Single-render scope lens and original housing. Presentation only.
const LENS_HEIGHT_FRACTION: float = 0.52
var lens: ColorRect
var lens_active: bool = false
var sample_zoom: float = 1.0
var _world_copy: BackBufferCopy
var _material: ShaderMaterial

static func supports(data: WeaponData) -> bool:
	return data != null and data.optic_kind in [3, 5]

func _ready() -> void:
	add_to_group(&"hybrid_optic")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world_copy = BackBufferCopy.new()
	_world_copy.name = "ScopeWorldCopy"
	_world_copy.copy_mode = BackBufferCopy.COPY_MODE_RECT
	add_child(_world_copy)
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
		return
	var target_fov: float = OpticMath.target_fov(data, ViewSettings.fov_degrees)
	sample_zoom = OpticMath.screen_lens_zoom(source.fov, target_fov)
	_material.set_shader_parameter(&"magnification", sample_zoom)
	var diameter: float = size.y * LENS_HEIGHT_FRACTION
	var unit: float = size.y / 720.0
	var extent: float = diameter + 80.0 * unit
	lens.position = size * 0.5 - Vector2.ONE * extent * 0.5
	lens.size = Vector2.ONE * extent
	_material.set_shader_parameter(&"radius", diameter * 0.5)
	_material.set_shader_parameter(&"unit", unit)
	# Explicitly copy only the texels sampled by the lens. This suppresses
	# Godot's implicit full-screen screen_texture copy on the Intel GPU.
	var source_size: Vector2 = Vector2.ONE * diameter / sample_zoom
	_world_copy.rect = Rect2(size * 0.5 - source_size * 0.5, source_size).grow(2.0)
