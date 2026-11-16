class_name BulletPaths
extends Node3D
## Debug view of projectile flight: one line per bullet through the points
## the simulation actually visited (one per physics tick), coloured from
## yellow at muzzle speed to red as drag slows it, with a cyan cross where
## it hit. Toggle with F4, or start with it on using `-- --bullet-paths`.
##
## Only listens to the ProjectileSystem; it never changes a projectile. It
## records nothing while turned off.

const ARGUMENT: String = "--bullet-paths"

## Finished paths kept on screen; the oldest is dropped first.
@export_range(1, 200) var max_paths: int = 40
## Speed, as a fraction of muzzle speed, that is drawn fully red.
@export_range(0.1, 1.0, 0.01) var slow_speed_fraction: float = 0.6
@export var fast_colour: Color = Color(1.0, 0.9, 0.2)
@export var slow_colour: Color = Color(1.0, 0.15, 0.1)
@export var impact_colour: Color = Color(0.2, 0.9, 1.0)
@export_range(0.01, 1.0, 0.01, "suffix:m") var impact_cross_size: float = 0.5

var enabled: bool = false:
	set(value):
		enabled = value
		if _mesh_instance != null:
			_mesh_instance.visible = value
		_dirty = true

var _system: ProjectileSystem
## Paths still in flight, by pool slot.
var _live: Dictionary[int, BulletPath] = {}
var _finished: Array[BulletPath] = []
var _dirty: bool = false
var _mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D


## One bullet's recorded flight.
class BulletPath:
	var points: PackedVector3Array = PackedVector3Array()
	## Speed fraction (of muzzle speed) at each point.
	var speeds: PackedFloat32Array = PackedFloat32Array()
	var muzzle_speed: float = 1.0
	var hit: bool = false


func _ready() -> void:
	# Sample after the ProjectileSystem (priority 100) has moved everything.
	process_physics_priority = 101
	_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _mesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	# Drawn over everything, so a path stays visible behind walls and props.
	material.no_depth_test = true
	_mesh_instance.material_override = material
	add_child(_mesh_instance)
	enabled = enabled or OS.get_cmdline_user_args().has(ARGUMENT)
	_connect.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_bullet_paths"):
		enabled = not enabled


func _physics_process(_delta: float) -> void:
	sample()


func _process(_delta: float) -> void:
	if _dirty:
		_rebuild()


## Attaches to a ProjectileSystem. Found through its group when not given.
func attach(system: ProjectileSystem) -> void:
	if _system != null:
		return
	_system = system
	_system.projectile_fired.connect(_on_fired)
	_system.projectile_hit.connect(_on_hit)
	_system.projectile_expired.connect(_on_expired)


## Appends every live bullet's current position. Runs each physics tick;
## tests that step the system by hand call it directly.
func sample() -> void:
	if not enabled or _system == null:
		return
	for slot: int in _live:
		if not _system.is_slot_active(slot):
			continue
		var path: BulletPath = _live[slot]
		path.points.append(_system.get_slot_position(slot))
		path.speeds.append(_system.get_slot_velocity(slot).length() / path.muzzle_speed)
		_dirty = true


func clear() -> void:
	_live.clear()
	_finished.clear()
	_dirty = true


## Finished paths, oldest first.
func get_path_count() -> int:
	return _finished.size()


func get_path_points(index: int) -> PackedVector3Array:
	return _finished[index].points


func get_path_speeds(index: int) -> PackedFloat32Array:
	return _finished[index].speeds


func get_live_count() -> int:
	return _live.size()


func _connect() -> void:
	if _system != null:
		return
	var system := get_tree().get_first_node_in_group(ProjectileSystem.GROUP) as ProjectileSystem
	if system == null:
		push_warning("BulletPaths: no ProjectileSystem in the scene.")
		return
	attach(system)


func _on_fired(slot: int, origin: Vector3, velocity: Vector3, _spec: ProjectileSpec) -> void:
	if not enabled:
		return
	var path := BulletPath.new()
	path.muzzle_speed = maxf(velocity.length(), 0.001)
	path.points.append(origin)
	path.speeds.append(1.0)
	_live[slot] = path
	_dirty = true


func _on_hit(hit: ProjectileHit) -> void:
	var path: BulletPath = _live.get(hit.slot)
	if path == null:
		return
	path.points.append(hit.position)
	path.speeds.append(hit.velocity.length() / path.muzzle_speed)
	path.hit = true
	_finish(hit.slot)


func _on_expired(slot: int) -> void:
	if _live.has(slot):
		_finish(slot)


func _finish(slot: int) -> void:
	_finished.append(_live[slot])
	_live.erase(slot)
	while _finished.size() > max_paths:
		_finished.pop_front()
	_dirty = true


func _rebuild() -> void:
	_dirty = false
	_mesh.clear_surfaces()
	if not enabled:
		return
	var paths: Array[BulletPath] = _finished.duplicate()
	for slot: int in _live:
		paths.append(_live[slot])
	var vertex_count: int = 0
	for path: BulletPath in paths:
		vertex_count += (path.points.size() - 1) * 2 + (6 if path.hit else 0)
	if vertex_count <= 0:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for path: BulletPath in paths:
		for i: int in path.points.size() - 1:
			_mesh.surface_set_color(_speed_colour(path.speeds[i]))
			_mesh.surface_add_vertex(path.points[i])
			_mesh.surface_set_color(_speed_colour(path.speeds[i + 1]))
			_mesh.surface_add_vertex(path.points[i + 1])
		if path.hit:
			var end: Vector3 = path.points[path.points.size() - 1]
			var half: float = impact_cross_size * 0.5
			_mesh.surface_set_color(impact_colour)
			for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
				_mesh.surface_add_vertex(end - axis * half)
				_mesh.surface_add_vertex(end + axis * half)
	_mesh.surface_end()


func _speed_colour(fraction: float) -> Color:
	var t: float = clampf((1.0 - fraction) / (1.0 - slow_speed_fraction), 0.0, 1.0)
	return fast_colour.lerp(slow_colour, t)
