extends GutTest
## Player status HUD, damage-direction indicator, death screen and the
## cosmetic plate animation, bound to a real player scene.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const HUD_SCENE: PackedScene = preload("res://ui/hud.tscn")

var _world: Node3D
var _player: PlayerController
var _health: PlayerHealth
var _hud: Hud
var _plate_view: PlateView


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)
	var floor_body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100.0, 1.0, 100.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	floor_body.add_child(collider)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	_world.add_child(floor_body)
	_player = PLAYER_SCENE.instantiate() as PlayerController
	(_player.get_node("Weapons") as WeaponController).loadout_definition = preload("res://tests/fixtures/mvp_loadout.tres")
	_world.add_child(_player)
	_health = _player.get_node("Health") as PlayerHealth
	_health.follow_range_setting = false
	_health.invulnerable = false
	_plate_view = _player.get_node("Head/CameraFeel/Camera/PlateView") as PlateView
	_hud = HUD_SCENE.instantiate() as Hud
	_world.add_child(_hud)
	await wait_physics_frames(3)


func after_each() -> void:
	Input.action_release(&"apply_plate")


func _hit_from(attacker_offset: Vector3, damage: float) -> void:
	var hit := ProjectileHit.new()
	hit.spec = ProjectileSpec.new()
	hit.damage = damage
	hit.velocity = -attacker_offset.normalized() * 800.0
	_health.receive_hit(hit, TargetSettings.Zone.TORSO)


# --- Plate animation ---


func _on_screen(pose: Transform3D) -> bool:
	# Inside a generous 65-degree vertical frustum, in front of the camera.
	var depth: float = -pose.origin.z
	return depth > 0.05 and absf(pose.origin.y) / depth < tan(deg_to_rad(32.5))


func test_plate_pose_starts_and_ends_out_of_view() -> void:
	assert_false(_on_screen(PlateMotion.pose(0.0)))
	assert_true(_on_screen(PlateMotion.pose(PlateMotion.RISE_END)), "held up in view")
	assert_false(_on_screen(PlateMotion.pose(1.0)))


func test_plate_pose_is_continuous() -> void:
	var previous: Transform3D = PlateMotion.pose(0.0)
	for step: int in range(1, 101):
		var pose: Transform3D = PlateMotion.pose(float(step) / 100.0)
		assert_lt(pose.origin.distance_to(previous.origin), 0.03, "no jump at %d%%" % step)
		previous = pose


func test_plate_view_timeline_matches_the_insert_timing() -> void:
	_health.vitals.armor = 0.0
	_health.request_plate()
	var lower: int = ceili(_health.weapons.get_current_data().lower_time * 60.0) + 2
	await wait_physics_frames(lower)
	var insert: int = roundi(_health.settings.plate_insert_seconds * 60.0)
	await wait_physics_frames(insert / 2)
	assert_almost_eq(_plate_view.get_progress(), _health.plate_progress(), 0.02, "the view follows the gameplay clock")
	assert_almost_eq(_health.plate_progress(), 0.5, 0.1)
	await wait_physics_frames(insert / 2 + 4)
	assert_eq(_plate_view.get_progress(), 0.0, "reset once the plate is in")
	assert_eq(_health.vitals.armor, 50.0)


func test_cancelling_resets_the_plate_animation() -> void:
	_health.vitals.armor = 0.0
	_health.request_plate()
	await wait_physics_frames(ceili(_health.weapons.get_current_data().lower_time * 60.0) + 20)
	assert_gt(_plate_view.get_progress(), 0.0)
	_health.cancel_plate()
	await wait_physics_frames(2)
	assert_eq(_plate_view.get_progress(), 0.0)


# --- Status ---


func test_status_shows_vest_and_spares_behind_the_option() -> void:
	var before: bool = ViewSettings.show_armor_plates
	ViewSettings.show_armor_plates = true
	_health.vitals.apply_damage(60.0)
	await wait_process_frames(2)
	assert_string_contains(_hud.status_view.get_plates_text(), "VEST 2/3")
	assert_string_contains(_hud.status_view.get_plates_text(), "SPARES %d" % _health.settings.spare_plates)
	ViewSettings.show_armor_plates = false
	await wait_process_frames(2)
	assert_eq(_hud.status_view.get_plates_text(), "")
	ViewSettings.show_armor_plates = before


# --- Direction indicator ---


func test_indicator_points_at_the_attacker_and_tracks_turning() -> void:
	_player.yaw = 0.0
	_hit_from(Vector3(10.0, 0.0, 0.0), 10.0)
	assert_eq(_hud.damage_indicator.active_count(), 1)
	assert_almost_eq(_hud.damage_indicator.newest_angle(), PI * 0.5, 0.01, "right")
	_player.yaw = -PI * 0.5
	assert_almost_eq(_hud.damage_indicator.newest_angle(), 0.0, 0.01, "turning right to face the shooter centres it")


func test_indicator_fades_out() -> void:
	_hit_from(Vector3(0.0, 0.0, 10.0), 10.0)
	assert_eq(_hud.damage_indicator.active_count(), 1)
	await wait_seconds(_hud.damage_indicator.lifetime + 0.2)
	assert_eq(_hud.damage_indicator.active_count(), 0)


func test_indicator_also_shows_while_invulnerable() -> void:
	_health.invulnerable = true
	_hit_from(Vector3(0.0, 0.0, -10.0), 10.0)
	assert_eq(_hud.damage_indicator.active_count(), 1)
	assert_eq(_health.vitals.armor, 150.0)


# --- Death screen ---


func test_death_screen_counts_down_then_hides_on_respawn() -> void:
	_health.vitals.armor = 0.0
	var hit := ProjectileHit.new()
	hit.spec = ProjectileSpec.new()
	hit.damage = 200.0
	hit.velocity = Vector3(0, 0, 800)
	_health.receive_hit(hit, TargetSettings.Zone.HEAD)
	assert_true(_hud.death_screen.visible)
	assert_string_contains(_hud.death_screen.get_countdown_text(), "Respawning in")
	await wait_physics_frames(roundi(_health.settings.reset_seconds * 60.0) + 3)
	assert_false(_hud.death_screen.visible)
	assert_eq(_hud.damage_indicator.active_count(), 0, "indicators cleared on respawn")
