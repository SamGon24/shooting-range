class_name Hud
extends CanvasLayer
## Read-only gameplay HUD: weapon state, spread, target feedback and stats.
## The diagnostic F3 overlay is a separate CanvasLayer.

## The crosshair is hidden once the weapon is aimed further than this.
@export_range(0.0, 1.0, 0.05) var crosshair_hide_aim_blend: float = 0.5
@export_range(0.0, 1.0, 0.05) var red_dot_show_aim_blend: float = 0.85

@export var fps_update_seconds: float = 0.25
## Stats are recorded immediately; throttle expensive text shaping.
@export var stats_update_seconds: float = 0.2

var _stats_dirty: bool = false
var _stats_elapsed: float = 0.0

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
@onready var _zero: Label = $Zero


func _ready() -> void:
	ViewSettings.changed.connect(_refresh_preferences)
	_refresh_preferences()
	feedback.feedback.connect(feedback_view.show_feedback)
	feedback.damage_total.connect(feedback_view.show_damage_total)
	feedback.stats_changed.connect(_mark_stats_dirty)
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
		_refresh_stats()
		feedback_view.clear_feedback()


func _process(delta: float) -> void:
	_stats_elapsed += delta
	if _stats_dirty and _stats_elapsed >= stats_update_seconds:
		_refresh_stats()
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
	var data: WeaponData = _controller.get_current_data()
	_scope.visible = scoped or (data != null and data.optic_kind == 1 and aim >= red_dot_show_aim_blend)
	_crosshair.visible = not scoped and aim < crosshair_hide_aim_blend
	var camera: Camera3D = get_viewport().get_camera_3d()
	var recoil: RecoilLogic = _controller.get_current_recoil()
	var logic: WeaponLogic = _controller.get_current_logic()
	if camera != null and recoil != null and logic != null:
		var spread: float = recoil.spread_degrees(logic.aim_progress)
		if data.delivery != null and data.delivery.kind == DeliveryData.Kind.PELLET:
			spread += data.delivery.pellet_spread_degrees
		_crosshair.set_spread(spread, camera.fov, get_viewport().get_visible_rect().size.y)


## Connects the HUD to a weapon controller and view. Called automatically
## with the ones found in the scene; tests can call it directly.
func bind(controller: WeaponController, view: WeaponView) -> void:
	_controller = controller
	_view = view
	controller.weapon_changed.connect(_on_weapon_changed)
	controller.zero_changed.connect(_refresh_weapon_name.unbind(1))
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
	(_scope.material as ShaderMaterial).set_shader_parameter(&"reticle_kind", data.optic_kind)
	_refresh_weapon_name()


## The weapon's name, and its sight zero when the player can change it.
func _refresh_weapon_name() -> void:
	var data: WeaponData = _controller.get_current_data()
	if data == null:
		return
	_weapon_name.text = data.display_name
	_zero.visible = data.zero_options.size() > 1
	_zero.text = "ZERO %d m  [Z]" % roundi(_controller.get_zero_distance())


func get_zero_text() -> String:
	return _zero.text if _zero.visible else ""


func _on_ammo_changed(ammo: int, magazine_size: int) -> void:
	var logic: WeaponLogic = _controller.get_current_logic()
	if not logic.data.uses_ammo:
		_ammo.text = "MELEE"
		return
	var shell_loading: bool = logic.is_reloading() and logic.reload_phase != WeaponLogic.ReloadPhase.NONE and logic.data.reload_policy != null and logic.data.reload_policy.kind == ReloadData.Kind.SHELL
	_ammo.text = ("LOADING " if shell_loading else "") + "%d / %d" % [ammo, magazine_size]


func _on_reload_started(_is_empty: bool, _duration: float) -> void:
	if _controller.get_current_data().reload_policy != null and _controller.get_current_data().reload_policy.kind == ReloadData.Kind.SHELL:
		_refresh_ammo()
		return
	_ammo.text = "RELOADING"


func _refresh_ammo() -> void:
	var logic: WeaponLogic = _controller.get_current_logic()
	if logic != null:
		_on_ammo_changed(logic.ammo, logic.data.magazine_size)


func _update_scope_aspect() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var material := _scope.material as ShaderMaterial
	material.set_shader_parameter(&"aspect", viewport_size.x / maxf(viewport_size.y, 1.0))


func _mark_stats_dirty() -> void:
	_stats_dirty = true


func _refresh_stats() -> void:
	_stats_dirty = false
	_stats_elapsed = 0.0
	var stats: RangeStats = feedback.stats
	var ttk: String = "—" if stats.last_time_to_kill < 0.0 else "%.3f s" % stats.last_time_to_kill
	_stats_label.text = "RANGE STATS\nShots  %d     Hits  %d\nAccuracy  %.1f%%\nHeadshots  %.1f%%\nLast TTK  %s\n[T] Reset stats" % [stats.shots, stats.hits, stats.accuracy_percent(), stats.headshot_percent(), ttk]


func _refresh_preferences() -> void:
	_fps.visible = ViewSettings.show_fps
