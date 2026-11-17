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


func test_crosshair_projects_current_spread_and_bloom_then_recovers() -> void:
	var crosshair := _hud.get_node("Crosshair") as Crosshair
	var initial: float = crosshair.spread_radius
	assert_gt(initial, 0.0)
	Input.action_press("fire")
	await wait_physics_frames(30)
	Input.action_release("fire")
	assert_gt(crosshair.spread_radius, initial)
	await wait_physics_frames(60)
	assert_almost_eq(crosshair.spread_radius, initial, 0.02)


func test_stats_reset_key_clears_session_and_transient_feedback() -> void:
	_hud.feedback.stats.record_shot()
	_hud.feedback.stats.record_hit(1, true, true, 1.0)
	_hud.feedback.stats_changed.emit()
	_hud.feedback_view.show_feedback(HitFeedback.Kind.KILL, Vector3(0, 1.5, -25), 100.0, true)
	Input.action_press("range_stats_reset")
	await wait_physics_frames(2)
	Input.action_release("range_stats_reset")
	assert_eq(_hud.feedback.stats.shots, 0)
	assert_eq(_hud.feedback.stats.hits, 0)
	assert_eq(_hud.feedback.stats.last_time_to_kill, -1.0)
	assert_false(_hud.feedback_view.is_marker_active())
	assert_string_contains((_hud.get_node("Stats/Readout") as Label).text, "Shots  0")
	assert_string_contains((_hud.get_node("FPS") as Label).text, "FPS")


func test_stats_record_immediately_and_display_within_refresh_interval() -> void:
	var readout := _hud.get_node("Stats/Readout") as Label
	_hud.feedback.stats.record_shot()
	_hud.feedback.stats_changed.emit()
	assert_eq(_hud.feedback.stats.shots, 1)
	assert_string_contains(readout.text, "Shots  0", "text work is deferred, not the statistics")
	await wait_physics_frames(15)
	assert_string_contains(readout.text, "Shots  1")


func test_red_dot_reticle_is_visible_without_a_scope_blackout_model_hide() -> void:
	var optic := load("res://weapons/attachments/data/red_dot.tres") as AttachmentData
	_weapons.request_attachment(WeaponTypes.Slot.OPTIC, optic)
	await wait_physics_frames(3)
	Input.action_press("aim")
	await wait_physics_frames(30)
	assert_false(_hud.is_crosshair_visible())
	assert_true(_hud.is_scope_visible())
	assert_eq(((_hud.get_node("Scope") as ColorRect).material as ShaderMaterial).get_shader_parameter("reticle_kind"), 1)
	assert_true((_player.get_node("Head/CameraFeel/Camera/WeaponView") as WeaponView).is_model_shown())
