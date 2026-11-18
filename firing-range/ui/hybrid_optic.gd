class_name HybridOptic
extends Control
## Presentation only. No access to weapon logic, recoil or projectiles.
## Performance gate: flip false if the lens spike misses 90 fps uncapped.
const LENS_MODE_AVAILABLE: bool = false
const LENS_RESOLUTION: int = 256
const LENS_HEIGHT_FRACTION: float = 300.0 / 720.0
var viewport: SubViewport
var lens_camera: Camera3D
var lens: TextureRect
var lens_active: bool = false

func _ready() -> void:
	add_to_group(&"hybrid_optic")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()

static func uses_lens() -> bool:
	return LENS_MODE_AVAILABLE and ViewSettings.hybrid_lens

func update_view(data: WeaponData, aim: float, source: Camera3D) -> void:
	visible = data != null and data.optic_kind == 5 and aim >= 0.85
	lens_active = visible and uses_lens() and source != null
	if lens_active:
		if viewport == null:
			_create_lens(source)
		lens_camera.global_transform = source.global_transform
		lens_camera.fov = OpticMath.lens_fov(ViewSettings.fov_degrees, data.optic_magnification, LENS_HEIGHT_FRACTION)
		lens_camera.near = source.near
		lens_camera.far = source.far
		lens_camera.cull_mask = source.cull_mask
		var diameter: float = size.y * LENS_HEIGHT_FRACTION
		lens.position = size * 0.5 - Vector2.ONE * diameter * 0.5
		lens.size = Vector2.ONE * diameter
	if viewport != null:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if lens_active else SubViewport.UPDATE_DISABLED
		lens.visible = lens_active
	queue_redraw()

func _create_lens(source: Camera3D) -> void:
	viewport = SubViewport.new()
	viewport.name = "HybridLensViewport"
	viewport.size = Vector2i.ONE * LENS_RESOLUTION
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.world_3d = source.get_world_3d()
	viewport.gui_disable_input = true
	viewport.audio_listener_enable_3d = false
	add_child(viewport)
	lens_camera = Camera3D.new()
	viewport.add_child(lens_camera)
	lens_camera.current = true
	lens = TextureRect.new()
	lens.name = "HybridLensImage"
	lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lens.texture = viewport.get_texture()
	var material := ShaderMaterial.new()
	material.shader = preload("res://ui/hybrid_lens.gdshader")
	lens.material = material
	# Lens draws first; the etched reticle Control is a child drawn above it.
	add_child(lens)
	var reticle := Control.new()
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(reticle)
	reticle.draw.connect(_draw_reticle)

func _draw() -> void:
	if not lens_active:
		_draw_reticle()
	else:
		# Redraw the reticle child after the lens texture.
		(get_child(get_child_count()-1) as Control).queue_redraw()

func _draw_reticle() -> void:
	var target: CanvasItem = self
	if lens_active:
		target = get_child(get_child_count()-1) as CanvasItem
	var center: Vector2 = size * 0.5
	var unit: float = size.y / 720.0
	var ink := Color(0.08,0.09,0.08,0.95)
	var light := Color(0.8,0.81,0.7,0.8)
	if lens_active:
		target.draw_arc(center, size.y * LENS_HEIGHT_FRACTION * 0.5, 0, TAU, 96, ink, 4*unit, true)
	else:
		var frame := Rect2(Vector2(10,10)*unit, size-Vector2(20,20)*unit)
		target.draw_rect(frame, ink, false, 3*unit)
		target.draw_rect(frame.grow(-2*unit), light, false, unit)
	# Small etched cross and ticks; no opaque fill or vignette anywhere.
	for side: float in [-1.0,1.0]:
		target.draw_line(center+Vector2(8*side,0)*unit,center+Vector2(65*side,0)*unit,ink,2*unit,true)
		target.draw_line(center+Vector2(0,8*side)*unit,center+Vector2(0,65*side)*unit,ink,2*unit,true)
		for tick: int in [25,45,65]:
			target.draw_line(center+Vector2(tick*side,-4)*unit,center+Vector2(tick*side,4)*unit,ink,unit,true)
			target.draw_line(center+Vector2(-4,tick*side)*unit,center+Vector2(4,tick*side)*unit,ink,unit,true)
	target.draw_circle(center, 1.5*unit, ink)
