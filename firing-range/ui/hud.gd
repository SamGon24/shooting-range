class_name Hud
extends CanvasLayer
## Minimal heads-up display: crosshair, ammo counter, weapon name and the
## sniper's scope overlay. Reads from the weapon controller and view; it
## shows state and changes nothing. The full HUD is Milestone 5.

## The crosshair is hidden once the weapon is aimed further than this.
@export_range(0.0, 1.0, 0.05) var crosshair_hide_aim_blend: float = 0.5

var _controller: WeaponController
var _view: WeaponView

@onready var _crosshair: Crosshair = $Crosshair
@onready var _scope: ColorRect = $Scope
@onready var _ammo: Label = $Ammo
@onready var _weapon_name: Label = $WeaponName


func _ready() -> void:
	_scope.visible = false
	_update_scope_aspect()
	get_viewport().size_changed.connect(_update_scope_aspect)
	_bind_from_tree.call_deferred()


func _process(_delta: float) -> void:
	if _controller == null:
		return
	var scoped: bool = _view != null and _view.is_scope_view_active()
	var aim: float = _controller.get_aim_blend(Engine.get_physics_interpolation_fraction())
	_scope.visible = scoped
	_crosshair.visible = not scoped and aim < crosshair_hide_aim_blend


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
