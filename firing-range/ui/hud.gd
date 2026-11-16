class_name Hud
extends CanvasLayer
## Read-only gameplay HUD: weapon state, spread, target feedback and stats.
## The diagnostic F3 overlay is a separate CanvasLayer.

## The crosshair is hidden once the weapon is aimed further than this.
@export_range(0.0, 1.0, 0.05) var crosshair_hide_aim_blend: float = 0.5

@export var fps_update_seconds: float = 0.25

var _fps_elapsed: float = 0.0
var _fps_frames: int = 0
var _reset_latched: bool = false
var _controller: WeaponController
var _view: WeaponView

@onready var feedback: RangeFeedback = $RangeFeedback
@onready var feedback_view: FeedbackView = $FeedbackView
@onready var _fps: Label = $FPS
@onready var _stats_label: Label = $Stats/Readout
@onready var _crosshair: Crosshair = $Crosshair
@onready var _scope: ColorRect = $Scope
@onready var _ammo: Label = $Ammo
@onready var _weapon_name: Label = $WeaponName


func _ready() -> void:
	feedback.feedback.connect(feedback_view.show_feedback)
	feedback.stats_changed.connect(_refresh_stats)
	_refresh_stats()
	_scope.visible = false
	_update_scope_aspect()
	get_viewport().size_changed.connect(_update_scope_aspect)
	_bind_from_tree.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("range_stats_reset") and not event.is_echo():
		_reset_latched = true


func _physics_process(_delta: float) -> void:
	if _reset_latched or Input.is_action_just_pressed("range_stats_reset"):
		_reset_latched = false
		feedback.reset_stats()
		feedback_view.clear_feedback()


func _process(delta: float) -> void:
	_fps_elapsed += delta
	_fps_frames += 1
	if _fps_elapsed >= fps_update_seconds:
		_fps.text = "%d FPS" % roundi(float(_fps_frames) / _fps_elapsed)
		_fps_elapsed = 0.0
		_fps_frames = 0
	if _controller == null:
		return
	var scoped: bool = _view != null and _view.is_scope_view_active()
	var aim: float = _controller.get_aim_blend(Engine.get_physics_interpolation_fraction())
	_scope.visible = scoped
	_crosshair.visible = not scoped and aim < crosshair_hide_aim_blend
	var camera: Camera3D = get_viewport().get_camera_3d()
	var recoil: RecoilLogic = _controller.get_current_recoil()
	var logic: WeaponLogic = _controller.get_current_logic()
	if camera != null and recoil != null and logic != null:
		_crosshair.set_spread(recoil.spread_degrees(logic.aim_progress), camera.fov, get_viewport().get_visible_rect().size.y)


## Connects the HUD to a weapon controller and view. Called automatically
## with the ones found in the scene; tests can call it directly.
func bind(controller: WeaponController, view: WeaponView) -> void:
	_controller = controller
	_view = view
	controller.weapon_changed.connect(_on_weapon_changed)
	controller.ammo_changed.connect(_on_ammo_changed)
	controller.reload_started.connect(_on_reload_started)
	controller.reload_finished.connect(_refresh_ammo)
	controller.reload_cancelled.connect(_refresh_ammo)
	if controller.get_current_data() != null:
		_on_weapon_changed(controller.get_current_data())
		_refresh_ammo()


func get_ammo_text() -> String:
	return _ammo.text


func get_weapon_name_text() -> String:
	return _weapon_name.text


func is_crosshair_visible() -> bool:
	return _crosshair.visible


func is_scope_visible() -> bool:
	return _scope.visible


func _bind_from_tree() -> void:
	if _controller != null:
		return
	var controller := get_tree().get_first_node_in_group(WeaponController.GROUP) as WeaponController
	var view := get_tree().get_first_node_in_group(WeaponView.GROUP) as WeaponView
	if controller != null:
		bind(controller, view)


func _on_weapon_changed(data: WeaponData) -> void:
	_weapon_name.text = data.display_name


func _on_ammo_changed(ammo: int, magazine_size: int) -> void:
	_ammo.text = "%d / %d" % [ammo, magazine_size]


func _on_reload_started(_is_empty: bool, _duration: float) -> void:
	_ammo.text = "RELOADING"


func _refresh_ammo() -> void:
	var logic: WeaponLogic = _controller.get_current_logic()
	if logic != null:
		_on_ammo_changed(logic.ammo, logic.data.magazine_size)


func _update_scope_aspect() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var material := _scope.material as ShaderMaterial
	material.set_shader_parameter(&"aspect", viewport_size.x / maxf(viewport_size.y, 1.0))


func _refresh_stats() -> void:
	var stats: RangeStats = feedback.stats
	var ttk: String = "—" if stats.last_time_to_kill < 0.0 else "%.3f s" % stats.last_time_to_kill
	_stats_label.text = "RANGE STATS\nShots  %d     Hits  %d\nAccuracy  %.1f%%\nHeadshots  %.1f%%\nLast TTK  %s\n[T] Reset stats" % [stats.shots, stats.hits, stats.accuracy_percent(), stats.headshot_percent(), ttk]
