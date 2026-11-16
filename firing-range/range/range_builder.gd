class_name RangeBuilder
extends Node3D
## Builds the greybox firing range from a handful of numbers.
##
## Layout (1 unit = 1 m): the firing line is at z = 0 and the lanes run
## downrange along -Z. The player spawns just behind the line, at +Z. A small
## movement test area (steps, ramp, crouch tunnel) sits further behind.
##
## Everything is generated in `_ready` so distances live in one place and the
## scene file stays tiny. All solid geometry is on physics layer 1 ("world").

const GRID_SHADER: Shader = preload("res://range/greybox_grid.gdshader")

const MARKER_GROUP: StringName = &"distance_marker"
const WORLD_LAYER: int = 1

@export_group("Lanes")
@export_range(1, 12) var lane_count: int = 5
@export_range(2.0, 12.0, 0.5, "suffix:m") var lane_width: float = 6.0
## Distances that get a ground stripe and a sign on each side, in metres.
@export var marker_distances: PackedInt32Array = PackedInt32Array([25, 50, 100, 200, 300])

@export_group("Ground")
## Half-width of the ground slab, metres.
@export_range(20.0, 200.0, 1.0, "suffix:m") var ground_half_width: float = 40.0
## How far the ground extends behind the firing line, metres.
@export_range(10.0, 100.0, 1.0, "suffix:m") var ground_behind_line: float = 40.0
## Gap between the furthest marker and the backstop, metres.
@export_range(2.0, 50.0, 1.0, "suffix:m") var backstop_margin: float = 12.0

@export_group("Signs")
## Digit height as a fraction of the sign's distance, so far signs stay legible.
@export_range(0.005, 0.05, 0.001) var sign_height_per_metre: float = 0.02
@export_range(0.5, 3.0, 0.1, "suffix:m") var sign_min_digit_height: float = 1.0
## Gap between the outermost lane line and the nearest sign edge, metres.
@export_range(0.5, 10.0, 0.1, "suffix:m") var sign_lane_gap: float = 1.5
## Sideways clearance between signs as seen from the firing line, as a
## fraction of distance (0.012 is about 0.7 degrees).
@export_range(0.0, 0.05, 0.001) var sign_clearance_slope: float = 0.012

@export_group("Colors")
@export var ground_color: Color = Color(0.40, 0.42, 0.40)
@export var wall_color: Color = Color(0.50, 0.48, 0.44)
@export var prop_color: Color = Color(0.62, 0.50, 0.36)
@export var line_paint_color: Color = Color(0.92, 0.80, 0.22)
@export var lane_paint_color: Color = Color(0.85, 0.85, 0.82)
@export var sign_board_color: Color = Color(0.10, 0.11, 0.12)
@export var sign_text_color: Color = Color(0.96, 0.92, 0.55)

@export_group("Targets")
@export var dummy_settings: TargetSettings = preload("res://targets/data/dummy_default.tres")
@export var rail_length: float = 4.0
@export var walk_target_speed: float = 1.5
@export var sprint_target_speed: float = 6.0

var _geometry: Node3D
var _grid_materials: Dictionary[Color, ShaderMaterial] = {}
var _flat_materials: Dictionary[Color, StandardMaterial3D] = {}


func _ready() -> void:
	_geometry = Node3D.new()
	_geometry.name = "Geometry"
	add_child(_geometry)

	_build_ground_and_walls()
	_build_firing_line()
	_build_lanes()
	_build_distance_markers()
	_build_movement_test_area()
	_build_targets()


## Total width of all lanes, metres.
func get_lanes_width() -> float:
	return lane_width * float(lane_count)


## Distance from the firing line to the far end of the lanes, metres.
func get_range_length() -> float:
	var longest: int = 0
	for distance: int in marker_distances:
		longest = maxi(longest, distance)
	return float(longest)


# --- Sections ---


func _build_ground_and_walls() -> void:
	var far_edge: float = -(get_range_length() + backstop_margin + 6.0)
	var near_edge: float = ground_behind_line
	var length: float = near_edge - far_edge
	var centre_z: float = (near_edge + far_edge) * 0.5
	var width: float = ground_half_width * 2.0

	_add_box("Ground", Vector3(width, 1.0, length), Vector3(0.0, -0.5, centre_z), ground_color)

	# Backstop berm behind the furthest targets.
	var backstop_z: float = -(get_range_length() + backstop_margin)
	_add_box("Backstop", Vector3(width, 10.0, 4.0), Vector3(0.0, 5.0, backstop_z - 2.0), wall_color)

	# Perimeter walls so the player cannot leave the slab.
	var wall_height: float = 4.0
	for side: float in [-1.0, 1.0]:
		_add_box(
			"SideWall",
			Vector3(1.0, wall_height, length),
			Vector3(side * (ground_half_width - 0.5), wall_height * 0.5, centre_z),
			wall_color
		)
	_add_box(
		"RearWall",
		Vector3(width, wall_height, 1.0),
		Vector3(0.0, wall_height * 0.5, near_edge - 0.5),
		wall_color
	)


func _build_firing_line() -> void:
	var lanes_width: float = get_lanes_width()

	# Painted line at z = 0. Visual only.
	_add_paint("FiringLine", Vector3(lanes_width, 0.02, 0.4), Vector3(0.0, 0.01, 0.0), line_paint_color)

	# Stall partitions between shooting positions, just behind the line.
	for index: int in lane_count + 1:
		var x: float = -lanes_width * 0.5 + lane_width * float(index)
		_add_box("StallPartition", Vector3(0.15, 1.3, 1.6), Vector3(x, 0.65, 1.0), wall_color)


func _build_lanes() -> void:
	var lanes_width: float = get_lanes_width()
	var length: float = get_range_length()

	for index: int in lane_count + 1:
		var x: float = -lanes_width * 0.5 + lane_width * float(index)
		_add_paint(
			"LaneLine",
			Vector3(0.12, 0.02, length),
			Vector3(x, 0.01, -length * 0.5),
			lane_paint_color
		)


func _build_distance_markers() -> void:
	var lanes_width: float = get_lanes_width()

	# Far signs are drawn bigger, so seen from the firing line they would
	# overlap the nearer ones. Work from the furthest sign inward and push each
	# one sideways until it clears the sign behind it. "Slope" is sideways
	# offset divided by distance, i.e. how far off-centre the sign appears.
	var distances: Array[int] = []
	for distance: int in marker_distances:
		distances.append(distance)
	distances.sort()
	distances.reverse()
	var occupied_slope: float = 0.0

	for distance: int in distances:
		var z: float = -float(distance)
		var digit_height: float = maxf(float(distance) * sign_height_per_metre, sign_min_digit_height)

		var marker := Node3D.new()
		marker.name = "Marker%dm" % distance
		marker.position = Vector3(0.0, 0.0, z)
		marker.add_to_group(MARKER_GROUP)
		marker.set_meta(&"distance_m", distance)
		_geometry.add_child(marker)

		# Stripe across every lane. Wider at distance so it stays visible.
		var stripe_depth: float = clampf(float(distance) * 0.006, 0.3, 2.0)
		_add_paint(
			"Stripe",
			Vector3(lanes_width, 0.02, stripe_depth),
			Vector3(0.0, 0.012, 0.0),
			line_paint_color,
			marker
		)

		# A numbered sign on each side of the lanes, facing the firing line.
		var text: String = str(distance)
		var board_size := Vector3(
			digit_height * (0.62 * float(text.length()) + 0.5), digit_height * 1.4, 0.2
		)
		var post_height: float = 1.0 + digit_height * 0.25
		var inner_edge: float = maxf(
			lanes_width * 0.5 + sign_lane_gap,
			(occupied_slope + sign_clearance_slope) * float(distance)
		)
		occupied_slope = (inner_edge + board_size.x) / float(distance)

		for side: float in [-1.0, 1.0]:
			var x: float = side * (inner_edge + board_size.x * 0.5)
			_add_box(
				"SignPost",
				Vector3(0.3, post_height, 0.3),
				Vector3(x, post_height * 0.5, 0.0),
				wall_color,
				marker
			)
			_add_box(
				"SignBoard",
				board_size,
				Vector3(x, post_height + board_size.y * 0.5, 0.0),
				sign_board_color,
				marker,
				false
			)
			_add_sign_text(
				text,
				digit_height,
				Vector3(x, post_height + board_size.y * 0.5, board_size.z * 0.5 + 0.02),
				marker
			)


## Obstacles behind the firing line for testing jump, crouch and ramps.
func _build_movement_test_area() -> void:
	# Steps of 0.5 / 1.0 / 1.5 m. Each is one jump higher than the last.
	for index: int in 3:
		var height: float = 0.5 * float(index + 1)
		_add_box(
			"Step",
			Vector3(2.5, height, 2.5),
			Vector3(-14.0 + 2.5 * float(index), height * 0.5, 14.0),
			prop_color
		)

	# 15 degree ramp up to a platform.
	var ramp_start := Vector3(12.0, 0.0, 10.0)
	var ramp_rise: float = 1.5
	var ramp_run: float = ramp_rise / tan(deg_to_rad(15.0))
	_add_ramp("Ramp", ramp_start, ramp_run, ramp_rise, 3.0, prop_color)
	_add_box(
		"RampPlatform",
		Vector3(3.0, ramp_rise, 4.0),
		Vector3(ramp_start.x, ramp_rise * 0.5, ramp_start.z + ramp_run + 2.0),
		prop_color
	)

	# Crouch tunnel: 1.3 m of headroom, so you fit crouched or sliding only.
	var tunnel_centre := Vector3(0.0, 0.0, 22.0)
	var tunnel_length: float = 6.0
	var clearance: float = 1.3
	for side: float in [-1.0, 1.0]:
		_add_box(
			"TunnelWall",
			Vector3(0.3, clearance + 0.3, tunnel_length),
			Vector3(tunnel_centre.x + side * 1.15, (clearance + 0.3) * 0.5, tunnel_centre.z),
			prop_color
		)
	_add_box(
		"TunnelRoof",
		Vector3(2.6, 0.3, tunnel_length),
		Vector3(tunnel_centre.x, clearance + 0.15, tunnel_centre.z),
		prop_color
	)


## Stagger the stationary silhouettes across lanes so near ones do not mask
## every distant target. The middle of each lane remains a walking route.
func _build_targets() -> void:
	var targets := Node3D.new()
	targets.name = "Targets"
	add_child(targets)
	var hits := TargetHits.new()
	targets.add_child(hits)
	for index: int in marker_distances.size():
		var lane: int = index % lane_count
		var x: float = -get_lanes_width() * 0.5 + lane_width * (float(lane) + 0.3)
		var dummy := TargetDummy.new()
		dummy.name = "Dummy%dm" % marker_distances[index]
		dummy.settings = dummy_settings
		dummy.armor_plates = index % 4
		dummy.position = Vector3(x, 0.0, -float(marker_distances[index]))
		targets.add_child(dummy)
	for distance: int in [50, 100]:
		for fast: bool in [false, true]:
			var rail := TargetRail.new()
			rail.name = "Rail%d%s" % [distance, "Sprint" if fast else "Walk"]
			rail.length = rail_length
			rail.speed = sprint_target_speed if fast else walk_target_speed
			var x: float = get_lanes_width() * 0.5 - lane_width if fast else -get_lanes_width() * 0.5 + 0.5
			rail.position = Vector3(x, 0.0, -float(distance))
			targets.add_child(rail)
			var dummy := TargetDummy.new()
			dummy.settings = dummy_settings
			rail.add_child(dummy)
			_add_paint("Rail", Vector3(rail_length, 0.04, 0.10), Vector3(x + rail_length * 0.5, 0.03, -float(distance)), wall_color, targets)
	for index: int in 3:
		var distance: int = [100, 200, 300][index]
		var x: float = -get_lanes_width() * 0.5 + lane_width * (float(index * 2 % lane_count) + 0.75)
		var plate := SteelPlate.new()
		plate.name = "Steel%dm" % distance
		plate.position = Vector3(x, 1.5, -float(distance))
		targets.add_child(plate)
		_add_box("SteelPost", Vector3(0.10, 2.1, 0.10), Vector3(x - 0.5, 1.05, -float(distance)), wall_color, targets)
		_add_box("SteelBar", Vector3(1.0, 0.08, 0.10), Vector3(x, 1.89, -float(distance)), wall_color, targets)


# --- Helpers ---


## Adds a box with the grid material. Solid boxes get a static collider.
func _add_box(
	box_name: String,
	size: Vector3,
	centre: Vector3,
	color: Color,
	parent: Node3D = null,
	gridded: bool = true
) -> Node3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = centre
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0

	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

	body.add_child(_make_box_mesh(size, _grid_material(color) if gridded else _flat_material(color)))
	_parent_or_geometry(parent).add_child(body, true)
	return body


## Adds a thin unlit, non-colliding box used as ground paint.
func _add_paint(
	paint_name: String, size: Vector3, centre: Vector3, color: Color, parent: Node3D = null
) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = _make_box_mesh(size, _flat_material(color))
	mesh_instance.name = paint_name
	mesh_instance.position = centre
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_parent_or_geometry(parent).add_child(mesh_instance, true)
	return mesh_instance


## Adds a solid ramp whose top surface starts at `start` (ground level) and
## climbs `rise` metres over `run` metres along +Z.
func _add_ramp(
	ramp_name: String, start: Vector3, run: float, rise: float, width: float, color: Color
) -> Node3D:
	var thickness: float = 0.3
	var slope_length: float = sqrt(run * run + rise * rise)
	var angle: float = atan2(rise, run)
	var ramp_basis := Basis(Vector3.RIGHT, -angle)
	var top_centre: Vector3 = start + Vector3(0.0, rise * 0.5, run * 0.5)
	var centre: Vector3 = top_centre - ramp_basis.y * (thickness * 0.5)

	var body: Node3D = _add_box(ramp_name, Vector3(width, thickness, slope_length), centre, color)
	body.basis = ramp_basis
	return body


func _add_sign_text(text: String, digit_height: float, centre: Vector3, parent: Node3D) -> void:
	const FONT_SIZE: int = 96
	var label := Label3D.new()
	label.name = "SignText"
	label.text = text
	label.font_size = FONT_SIZE
	label.outline_size = 0
	# `font_size` pixels of text are about one line tall; scale so the digits
	# come out `digit_height` metres high.
	label.pixel_size = digit_height / (float(FONT_SIZE) * 0.72)
	label.modulate = sign_text_color
	label.shaded = false
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.position = centre
	parent.add_child(label, true)


func _make_box_mesh(size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	return mesh_instance


func _parent_or_geometry(parent: Node3D) -> Node3D:
	return parent if parent != null else _geometry


func _grid_material(color: Color) -> ShaderMaterial:
	if _grid_materials.has(color):
		return _grid_materials[color]
	var material := ShaderMaterial.new()
	material.shader = GRID_SHADER
	material.set_shader_parameter(&"base_color", color)
	material.set_shader_parameter(&"line_color", color.darkened(0.28))
	_grid_materials[color] = material
	return material


func _flat_material(color: Color) -> StandardMaterial3D:
	if _flat_materials.has(color):
		return _flat_materials[color]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_flat_materials[color] = material
	return material
