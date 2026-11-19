class_name PlateView
extends Node3D
## Cosmetic greybox plate shown while one is inserted. Reads PlayerHealth;
## never changes gameplay. Hidden by shrinking rather than `visible`, as the
## camera rig does for the muzzle flash (see WeaponView).

const HIDDEN_SCALE: float = 0.001

@export var health: PlayerHealth
@export var plate_size: Vector3 = Vector3(0.20, 0.25, 0.02)
@export var plate_color: Color = Color(0.30, 0.33, 0.28)

var _mesh: MeshInstance3D
var _previous: float = 0.0
var _current: float = 0.0


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = plate_size
	var material := StandardMaterial3D.new()
	material.albedo_color = plate_color
	material.roughness = 0.9
	box.material = material
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	_mesh.layers = WeaponView.VIEWMODEL_LAYER
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_apply(0.0)


func _physics_process(_delta: float) -> void:
	_previous = _current
	_current = health.plate_progress() if health != null else 0.0
	if _current < _previous:
		_previous = _current


func _process(_delta: float) -> void:
	_apply(lerpf(_previous, _current, Engine.get_physics_interpolation_fraction()))


func get_progress() -> float:
	return _current


func _apply(progress: float) -> void:
	if progress <= 0.0 or progress >= 1.0:
		_mesh.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * HIDDEN_SCALE), PlateMotion.GONE)
		return
	_mesh.transform = PlateMotion.pose(progress)
