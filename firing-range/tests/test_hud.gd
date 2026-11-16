extends GutTest
## The minimal HUD mirrors weapon state: ammo, weapon name, crosshair and
## the scope overlay.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const HUD_SCENE: PackedScene = preload("res://ui/hud.tscn")
const ACTIONS: Array[StringName] = [&"fire", &"aim", &"reload"]

var _player: PlayerController
var _weapons: WeaponController
var _hud: Hud
var _rifle: WeaponData
var _sniper: WeaponData


func before_each() -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	var floor_body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200.0, 1.0, 200.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	floor_body.add_child(collider)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	world.add_child(floor_body)
	world.add_child(ProjectileSystem.new())

	_player = PLAYER_SCENE.instantiate() as PlayerController
	world.add_child(_player)
	_weapons = _player.get_node("Weapons") as WeaponController
	_rifle = _weapons.loadout[0]
	_sniper = _weapons.loadout[1]
	_hud = HUD_SCENE.instantiate() as Hud
	world.add_child(_hud)
	await wait_physics_frames(5)


func after_each() -> void:
	for action: StringName in ACTIONS:
		Input.action_release(action)


func _seconds(seconds: float) -> int:
	return roundi(seconds * float(Engine.physics_ticks_per_second))


func _switch_to_sniper() -> void:
	_weapons.request_switch(1)
	await wait_physics_frames(_seconds(_rifle.lower_time + _sniper.raise_time) + 4)


func test_shows_weapon_name_and_full_magazine_at_start() -> void:
	assert_eq(_hud.get_weapon_name_text(), _rifle.display_name)
	assert_eq(_hud.get_ammo_text(), "%d / %d" % [_rifle.magazine_size, _rifle.magazine_size])
	assert_true(_hud.is_crosshair_visible())
	assert_false(_hud.is_scope_visible())


func test_ammo_counter_follows_shots() -> void:
	Input.action_press("fire")
	await wait_physics_frames(_seconds(0.5))
	Input.action_release("fire")
	await wait_physics_frames(3)
	var ammo: int = _weapons.get_current_logic().ammo
	assert_lt(ammo, _rifle.magazine_size)
	assert_eq(_hud.get_ammo_text(), "%d / %d" % [ammo, _rifle.magazine_size])


func test_shows_reloading_then_the_refilled_count() -> void:
	Input.action_press("fire")
	await wait_physics_frames(10)
	Input.action_release("fire")
	await wait_physics_frames(8)
	Input.action_press("reload")
	await wait_physics_frames(3)
	Input.action_release("reload")
	assert_eq(_hud.get_ammo_text(), "RELOADING")
	await wait_physics_frames(_seconds(_rifle.reload_tactical_time) + 4)
	assert_eq(_hud.get_ammo_text(), "%d / %d" % [_rifle.magazine_size, _rifle.magazine_size])


func test_cancelled_reload_shows_the_unchanged_count_after_switching_back() -> void:
	Input.action_press("fire")
	await wait_physics_frames(10)
	Input.action_release("fire")
	await wait_physics_frames(8)
	var ammo: int = _weapons.get_current_logic().ammo
	Input.action_press("reload")
	await wait_physics_frames(3)
	Input.action_release("reload")

	await _switch_to_sniper()
	assert_eq(_hud.get_weapon_name_text(), _sniper.display_name)
	assert_eq(_hud.get_ammo_text(), "%d / %d" % [_sniper.magazine_size, _sniper.magazine_size])

	_weapons.request_switch(0)
	await wait_physics_frames(_seconds(_sniper.lower_time + _rifle.raise_time) + 4)
	assert_eq(_hud.get_ammo_text(), "%d / %d" % [ammo, _rifle.magazine_size])


func test_crosshair_hides_while_aiming_the_rifle() -> void:
	Input.action_press("aim")
	await wait_physics_frames(_seconds(_rifle.ads_time) + 4)
	assert_false(_hud.is_crosshair_visible())
	assert_false(_hud.is_scope_visible(), "the rifle has no scope")
	Input.action_release("aim")
	await wait_physics_frames(_seconds(_rifle.ads_time) + 4)
	assert_true(_hud.is_crosshair_visible())


func test_scope_overlay_shows_only_when_the_sniper_is_aimed() -> void:
	await _switch_to_sniper()
	assert_false(_hud.is_scope_visible())
	Input.action_press("aim")
	await wait_physics_frames(_seconds(_sniper.ads_time) + 6)
	assert_true(_hud.is_scope_visible())
	assert_false(_hud.is_crosshair_visible())
	Input.action_release("aim")
	await wait_physics_frames(_seconds(_sniper.ads_time) + 6)
	assert_false(_hud.is_scope_visible())
	assert_true(_hud.is_crosshair_visible())
