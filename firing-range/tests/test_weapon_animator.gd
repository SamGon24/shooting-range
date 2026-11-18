extends GutTest
## Handling animation on the real viewmodels: profile data matches the
## models, poses start and end at rest, reload parts follow the logic, and
## cancelling, switching or pausing leaves nothing stale behind.

const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")
const ACTIONS: Array[StringName] = [&"fire", &"aim", &"reload", &"weapon_1", &"weapon_2"]
const WEAPONS: Array[String] = [
	"halberd_rifle", "rill_smg", "foundry_lmg", "breakwater_shotgun", "longwatch_sniper",
	"wayline_pistol", "cairn_launcher", "latch_knife", "palisade_shield",
]
const RACK_PARTS: Array[StringName] = [&"ChargingHandle", &"BoltHandle", &"Slide"]
const REST_TOLERANCE: float = 0.00001

var _world: Node3D
var _player: PlayerController
var _weapons: WeaponController
var _view: WeaponView
var _releases: Array[Node3D] = []


func before_each() -> void:
	_releases.clear()
	get_tree().paused = false
	_world = Node3D.new()
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child_autofree(_world)
	var floor_body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100.0, 1.0, 100.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	floor_body.add_child(collider)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	_world.add_child(floor_body)
	_world.add_child(ProjectileSystem.new())
	_player = PLAYER_SCENE.instantiate() as PlayerController
	_world.add_child(_player)
	_weapons = _player.get_node("Weapons") as WeaponController
	_view = _player.get_node("Head/CameraFeel/Camera/WeaponView") as WeaponView
	_view.get_animator().copy_released.connect(func(part: Node3D, _follower: Node3D) -> void: _releases.append(part))
	await wait_physics_frames(5)


func after_each() -> void:
	get_tree().paused = false
	for action: StringName in ACTIONS:
		Input.action_release(action)


func _seconds(seconds: float) -> int:
	return ceili(seconds * float(Engine.physics_ticks_per_second))


func _data(name: String) -> WeaponData:
	return load("res://weapons/data/%s.tres" % name) as WeaponData


func _profiled() -> Array[WeaponData]:
	var result: Array[WeaponData] = []
	for name: String in WEAPONS:
		var data: WeaponData = _data(name)
		if data.handling != null:
			result.append(data)
	return result


func _parts_in(profile: HandlingProfile, event: HandlingTrack.Event) -> Array[StringName]:
	var parts: Array[StringName] = []
	for track: HandlingTrack in profile.tracks_for(event):
		parts.append(track.part)
	return parts


## Hidden parts may wait anywhere (a rocket out of sight before it is
## loaded), so only shown parts must be at rest.
func _assert_rest(pose: HandlingPose, message: String) -> void:
	for part: StringName in pose.offsets:
		if pose.is_hidden(part):
			continue
		assert_almost_eq(pose.offset(part).length(), 0.0, REST_TOLERANCE, "%s offset of '%s'" % [message, part])
	for part: StringName in pose.rotations:
		if pose.is_hidden(part):
			continue
		assert_almost_eq(pose.rotation(part).length(), 0.0, REST_TOLERANCE, "%s rotation of '%s'" % [message, part])


func _press(action: StringName) -> void:
	Input.action_press(action)
	await wait_physics_frames(1)
	Input.action_release(action)


# --- Profile data -------------------------------------------------------------


func test_every_profile_is_valid_and_names_real_viewmodel_parts() -> void:
	assert_eq(_profiled().size(), WEAPONS.size(), "all nine weapons animate")
	for data: WeaponData in _profiled():
		assert_true(data.handling.is_valid(), data.display_name)
		var model := data.viewmodel_scene.instantiate() as Node3D
		for part: StringName in data.handling.get_parts():
			if not part.is_empty():
				assert_not_null(model.get_node_or_null(NodePath(part)), "%s has part %s" % [data.display_name, part])
		model.free()


func test_magazine_weapons_drop_a_copy_once_per_reload_and_ammo_free_weapons_never() -> void:
	for data: WeaponData in _profiled():
		var expected: int = 1 if data.uses_ammo and data.reload_policy.kind == ReloadData.Kind.MAGAZINE else 0
		for event: HandlingTrack.Event in [HandlingTrack.Event.RELOAD_TACTICAL, HandlingTrack.Event.RELOAD_EMPTY]:
			var released: int = HandlingTimeline.releases_between(data.handling, event, -1.0, 1.0).size()
			assert_eq(released, expected, "%s event %d" % [data.display_name, event])
		for event: int in [HandlingTrack.Event.CYCLE, HandlingTrack.Event.LOWERED, HandlingTrack.Event.SHELL_INSERT]:
			assert_true(HandlingTimeline.releases_between(data.handling, event, -1.0, 1.0).is_empty())


func test_rack_only_on_empty_reloads() -> void:
	for data: WeaponData in _profiled():
		var tactical: Array[StringName] = _parts_in(data.handling, HandlingTrack.Event.RELOAD_TACTICAL)
		var empty: Array[StringName] = _parts_in(data.handling, HandlingTrack.Event.RELOAD_EMPTY)
		var model := data.viewmodel_scene.instantiate() as Node3D
		for part: StringName in RACK_PARTS:
			assert_false(tactical.has(part), "%s racks %s on a tactical reload" % [data.display_name, part])
			if model.has_node(NodePath(part)) and data.reload_policy.kind == ReloadData.Kind.MAGAZINE:
				assert_true(empty.has(part), "%s racks %s on an empty reload" % [data.display_name, part])
		model.free()


func test_every_event_ends_at_rest_and_joins_its_neighbours() -> void:
	var pose := HandlingPose.new()
	var other := HandlingPose.new()
	for data: WeaponData in _profiled():
		var profile: HandlingProfile = data.handling
		for event: HandlingTrack.Event in [HandlingTrack.Event.RELOAD_TACTICAL, HandlingTrack.Event.RELOAD_EMPTY, HandlingTrack.Event.SHELL_FINISH, HandlingTrack.Event.CYCLE]:
			HandlingTimeline.evaluate(profile, {event: 1.0}, false, pose)
			_assert_rest(pose, "%s end of event %d" % [data.display_name, event])
			assert_true(pose.hidden.keys().all(func(part: StringName) -> bool: return profile.staged_parts.has(part)), "%s only staged parts hidden at the end" % data.display_name)
		for event: HandlingTrack.Event in [HandlingTrack.Event.RELOAD_TACTICAL, HandlingTrack.Event.CYCLE, HandlingTrack.Event.SHELL_START]:
			HandlingTimeline.evaluate(profile, {event: 0.0}, false, pose)
			_assert_rest(pose, "%s start of event %d" % [data.display_name, event])
		# An empty reload begins where the empty hold leaves off (the pistol's
		# locked slide), so there is no jump when it starts.
		HandlingTimeline.evaluate(profile, {HandlingTrack.Event.RELOAD_EMPTY: 0.0}, true, pose)
		HandlingTimeline.evaluate(profile, {HandlingTrack.Event.EMPTY_HOLD: 1.0}, true, other)
		for part: StringName in profile.get_parts():
			if pose.is_hidden(part) or other.is_hidden(part):
				continue
			assert_almost_eq(pose.offset(part).distance_to(other.offset(part)), 0.0, REST_TOLERANCE, "%s %s empty hold -> reload" % [data.display_name, part])
		HandlingTimeline.evaluate(profile, {HandlingTrack.Event.LOWERED: 0.0}, false, pose)
		_assert_rest(pose, "%s fully raised" % data.display_name)
		if profile.has_event(HandlingTrack.Event.SHELL_START):
			HandlingTimeline.evaluate(profile, {HandlingTrack.Event.SHELL_START: 1.0}, false, pose)
			HandlingTimeline.evaluate(profile, {HandlingTrack.Event.SHELL_INSERT: 0.5}, false, other)
			assert_almost_eq(pose.offset(&"").distance_to(other.offset(&"")), 0.0, REST_TOLERANCE)
			HandlingTimeline.evaluate(profile, {HandlingTrack.Event.SHELL_FINISH: 0.0}, false, other)
			assert_almost_eq(pose.rotation(&"").distance_to(other.rotation(&"")), 0.0, REST_TOLERANCE)


# --- Live viewmodel -------------------------------------------------------------


func test_reload_moves_the_magazine_with_its_mount_and_returns_to_rest() -> void:
	var rifle: WeaponData = _weapons.get_current_data()
	var model: Node3D = _view.get_current_model()
	var magazine := model.get_node("Magazine") as Node3D
	var mount := model.get_node("Mounts/Magazine") as Node3D
	var rest: Transform3D = magazine.transform
	var mount_rest: Transform3D = mount.transform
	var logic: WeaponLogic = _weapons.get_current_logic()
	logic.ammo = 0
	await _press(&"reload")
	assert_true(logic.is_reloading())
	await wait_physics_frames(_seconds(rifle.reload_empty_time * 0.3))
	assert_lt(magazine.transform.origin.y, rest.origin.y - 0.1, "magazine is out")
	var expected_mount: Transform3D = magazine.transform * rest.affine_inverse() * mount_rest
	assert_almost_eq(mount.transform.origin.distance_to(expected_mount.origin), 0.0, 0.0001, "mount follows the magazine")
	assert_eq(_releases, [magazine] as Array[Node3D], "one copy released")
	await wait_physics_frames(_seconds(rifle.reload_empty_time * 0.7) + 3)
	assert_false(logic.is_reloading())
	assert_eq(logic.ammo, rifle.magazine_size)
	assert_almost_eq(magazine.transform.origin.distance_to(rest.origin), 0.0, 0.0001)
	assert_almost_eq(magazine.transform.basis.get_scale().length(), Vector3.ONE.length(), 0.0001)
	assert_eq(model.transform, Transform3D.IDENTITY)
	assert_eq(_releases.size(), 1)


func test_switching_away_mid_reload_resets_every_part() -> void:
	var model: Node3D = _view.get_current_model()
	var magazine := model.get_node("Magazine") as Node3D
	var rest: Transform3D = magazine.transform
	var logic: WeaponLogic = _weapons.get_current_logic()
	logic.ammo = 5
	await _press(&"reload")
	await wait_physics_frames(_seconds(0.8))
	assert_ne(magazine.transform, rest)
	_weapons.request_switch(1)
	await wait_physics_frames(_seconds(1.0))
	assert_ne(_view.get_current_model(), model)
	assert_eq(magazine.transform, rest, "the stored model is at rest")
	assert_eq(model.transform, Transform3D.IDENTITY)
	_weapons.request_switch(0)
	await wait_physics_frames(_seconds(1.0))
	assert_false(logic.is_reloading())
	assert_eq(logic.ammo, 5, "cancelling never grants rounds")
	assert_eq(magazine.transform, rest)
	assert_eq(_releases.size(), 1, "no extra drop on the way back")


func test_pausing_freezes_the_animation() -> void:
	var model: Node3D = _view.get_current_model()
	var magazine := model.get_node("Magazine") as Node3D
	_weapons.get_current_logic().ammo = 0
	await _press(&"reload")
	await wait_physics_frames(_seconds(0.3))
	get_tree().paused = true
	await wait_process_frames(2)
	var frozen: Transform3D = magazine.transform
	await get_tree().create_timer(0.3, true).timeout
	assert_eq(magazine.transform, frozen)
	get_tree().paused = false
	await wait_physics_frames(10)
	assert_ne(magazine.transform, frozen)


func test_pistol_slide_cycles_and_locks_back_when_empty() -> void:
	_weapons.request_switch(1)
	await wait_physics_frames(_seconds(1.0))
	var pistol: WeaponData = _weapons.get_current_data()
	assert_eq(pistol.weapon_class, WeaponTypes.Class.PISTOL)
	var slide := _view.get_current_model().get_node("Slide") as Node3D
	var rest: Transform3D = _view.get_animator().get_rest(pistol.definition(), &"Slide")
	var logic: WeaponLogic = _weapons.get_current_logic()
	logic.ammo = 2
	await _press(&"fire")
	await wait_physics_frames(3)
	assert_gt(slide.transform.origin.z, rest.origin.z + 0.005, "slide moves back after a shot")
	await wait_physics_frames(_seconds(pistol.shot_interval()) + 2)
	assert_almost_eq(slide.transform.origin.z, rest.origin.z, 0.0001, "and returns")
	await _press(&"fire")
	await wait_physics_frames(_seconds(pistol.shot_interval()) + 2)
	assert_eq(logic.ammo, 0)
	assert_almost_eq(slide.transform.origin.z, rest.origin.z + 0.03, 0.0001, "locked back on empty")
	await _press(&"reload")
	await wait_physics_frames(_seconds(pistol.reload_empty_time) + 2)
	assert_eq(logic.ammo, pistol.magazine_size)
	assert_almost_eq(slide.transform.origin.z, rest.origin.z, 0.0001, "released by the reload")


func test_sniper_bolt_cycles_after_each_shot() -> void:
	var sniper: WeaponData
	for choice: WeaponData in _weapons.get_primary_choices():
		if choice.weapon_class == WeaponTypes.Class.SNIPER:
			sniper = choice
	assert_true(_weapons.request_primary(sniper))
	await wait_physics_frames(_seconds(1.5))
	assert_eq(_weapons.get_current_data().definition(), sniper)
	var bolt := _view.get_current_model().get_node("BoltHandle") as Node3D
	var rest: Transform3D = _view.get_animator().get_rest(sniper, &"BoltHandle")
	await _press(&"fire")
	await wait_physics_frames(_seconds(sniper.shot_interval() * 0.45))
	assert_gt(bolt.transform.origin.z, rest.origin.z + 0.04, "bolt pulled back mid-cycle")
	await wait_physics_frames(_seconds(sniper.shot_interval() * 0.6))
	assert_almost_eq(bolt.transform.origin.distance_to(rest.origin), 0.0, 0.0001)
	assert_almost_eq(bolt.transform.basis.get_euler().length(), 0.0, 0.0001)


func _select(choices: Array[WeaponData], weapon_class: WeaponTypes.Class, primary: bool) -> WeaponData:
	for choice: WeaponData in choices:
		if choice.weapon_class == weapon_class:
			if primary:
				assert_true(_weapons.request_primary(choice))
			else:
				assert_true(_weapons.request_secondary(choice))
			return choice
	return null


func _is_shown(node: Node3D) -> bool:
	return node.transform.basis.get_scale().x > 0.5


func test_shells_load_one_at_a_time_and_firing_cuts_the_insert() -> void:
	var shotgun: WeaponData = _select(_weapons.get_primary_choices(), WeaponTypes.Class.SHOTGUN, true)
	await wait_physics_frames(_seconds(1.5))
	assert_eq(_weapons.get_current_data().definition(), shotgun)
	var model: Node3D = _view.get_current_model()
	var shell := model.get_node("LoadingShell") as Node3D
	var pump := model.get_node("Handguard") as Node3D
	var pump_rest: Transform3D = _view.get_animator().get_rest(shotgun, &"Handguard")
	assert_false(_is_shown(shell), "staged shell hidden at rest")
	var logic: WeaponLogic = _weapons.get_current_logic()
	logic.ammo = 3
	await _press(&"reload")
	await wait_physics_frames(_seconds(shotgun.reload_policy.shell_start_time) + 6)
	assert_eq(logic.reload_phase, WeaponLogic.ReloadPhase.INSERT)
	assert_true(_is_shown(shell), "a shell is on its way in")
	assert_ne(model.transform, Transform3D.IDENTITY, "tilted to the loading port")
	await _press(&"fire")
	await wait_physics_frames(1)
	assert_ne(logic.reload_phase, WeaponLogic.ReloadPhase.INSERT)
	assert_false(_is_shown(shell), "the unfinished shell vanishes with the insert")
	assert_eq(logic.ammo, 3, "no partial shell granted")
	await wait_physics_frames(_seconds(shotgun.reload_policy.shell_end_time) + _seconds(shotgun.shot_interval() * 0.4))
	assert_eq(logic.ammo, 2, "the queued shot fired")
	assert_gt(pump.transform.origin.z, pump_rest.origin.z + 0.05, "pumping after the shot")
	await wait_physics_frames(_seconds(shotgun.shot_interval()))
	assert_almost_eq(pump.transform.origin.distance_to(pump_rest.origin), 0.0, 0.0001)
	assert_eq(model.transform, Transform3D.IDENTITY)
	assert_true(_releases.is_empty(), "shells never drop a magazine")


func test_rocket_disappears_when_fired_and_slides_in_on_reload() -> void:
	var launcher: WeaponData = _select(_weapons.get_secondary_choices(), WeaponTypes.Class.ROCKET, false)
	await wait_physics_frames(_seconds(1.5))
	assert_eq(_weapons.get_current_data().definition(), launcher)
	var rocket := _view.get_current_model().get_node("LoadedRocket") as Node3D
	var rest: Transform3D = _view.get_animator().get_rest(launcher, &"LoadedRocket")
	assert_true(_is_shown(rocket))
	var logic: WeaponLogic = _weapons.get_current_logic()
	logic.ammo = 0
	await wait_physics_frames(2)
	assert_false(_is_shown(rocket), "empty tube")
	await _press(&"reload")
	await wait_physics_frames(_seconds(launcher.reload_empty_time * 0.1))
	assert_false(_is_shown(rocket), "not yet in hand")
	await wait_physics_frames(_seconds(launcher.reload_empty_time * 0.3))
	assert_true(_is_shown(rocket))
	assert_lt(rocket.transform.origin.y, rest.origin.y - 0.05, "still sliding in")
	await wait_physics_frames(_seconds(launcher.reload_empty_time * 0.6) + 3)
	assert_eq(logic.ammo, 1)
	assert_true(_is_shown(rocket))
	assert_almost_eq(rocket.transform.origin.distance_to(rest.origin), 0.0, 0.0001)
	assert_true(_releases.is_empty())


func test_lmg_belt_empties_and_is_laid_after_a_new_box() -> void:
	var lmg: WeaponData = _select(_weapons.get_primary_choices(), WeaponTypes.Class.LMG, true)
	await wait_physics_frames(_seconds(2.0))
	assert_eq(_weapons.get_current_data().definition(), lmg)
	var model: Node3D = _view.get_current_model()
	var belt := model.get_node("Belt") as Node3D
	var lid := model.get_node("Lid") as Node3D
	assert_true(_is_shown(belt))
	var logic: WeaponLogic = _weapons.get_current_logic()
	logic.ammo = 0
	await wait_physics_frames(2)
	assert_false(_is_shown(belt), "no belt in an empty gun")
	await _press(&"reload")
	await wait_physics_frames(_seconds(lmg.reload_empty_time * 0.2))
	assert_gt(absf(lid.rotation.x), deg_to_rad(60.0), "cover open")
	await wait_physics_frames(_seconds(lmg.reload_empty_time * 0.45))
	assert_eq(_releases, [model.get_node("Magazine")] as Array[Node3D], "the box drops once")
	assert_true(_is_shown(belt), "belt laid")
	await wait_physics_frames(_seconds(lmg.reload_empty_time * 0.4))
	assert_eq(logic.ammo, lmg.magazine_size)
	assert_almost_eq(lid.rotation.length(), 0.0, 0.0001)
	assert_true(_is_shown(belt))
	assert_eq(_releases.size(), 1)


func test_every_weapon_has_equip_and_holster_motion() -> void:
	var pose := HandlingPose.new()
	for data: WeaponData in _profiled():
		assert_true(data.handling.has_event(HandlingTrack.Event.LOWERED), data.display_name)
		HandlingTimeline.evaluate(data.handling, {HandlingTrack.Event.LOWERED: 1.0}, false, pose)
		assert_gt(pose.rotation(&"").length(), 0.0, "%s is turned away when put down" % data.display_name)


func test_switching_turns_the_model_away_and_back() -> void:
	var rifle_model: Node3D = _view.get_current_model()
	var rifle_logic: WeaponLogic = _weapons.get_current_logic()
	_weapons.request_switch(1)
	var lowered_roll: float = 0.0
	var raised_roll: float = 0.0
	for tick: int in 60:
		await wait_physics_frames(1)
		await wait_process_frames(1)
		var logic: WeaponLogic = _weapons.get_current_logic()
		if logic == rifle_logic and logic.raise_progress > 0.3 and logic.raise_progress < 0.7:
			lowered_roll = maxf(lowered_roll, absf(rifle_model.rotation.z))
		elif logic != rifle_logic and logic.raise_progress > 0.3 and logic.raise_progress < 0.7:
			raised_roll = maxf(raised_roll, absf(_view.get_current_model().rotation.z))
	assert_gt(lowered_roll, deg_to_rad(3.0), "rolled while lowering")
	assert_gt(raised_roll, deg_to_rad(3.0), "rolling in while raising")
	assert_ne(_view.get_current_model(), rifle_model)
	assert_eq(rifle_model.transform, Transform3D.IDENTITY, "stored at rest")
	assert_eq(_view.get_current_model().transform, Transform3D.IDENTITY, "fully raised at rest")


func test_knife_swing_strikes_then_recovers_over_the_cooldown() -> void:
	var knife: WeaponData = _select(_weapons.get_secondary_choices(), WeaponTypes.Class.KNIFE, false)
	await wait_physics_frames(_seconds(1.5))
	assert_eq(_weapons.get_current_data().definition(), knife)
	var model: Node3D = _view.get_current_model()
	assert_eq(model.transform, Transform3D.IDENTITY)
	await _press(&"fire")
	await wait_physics_frames(_seconds(knife.shot_interval() * 0.2))
	assert_gt(model.rotation.length(), deg_to_rad(30.0), "mid-swing")
	await wait_physics_frames(_seconds(knife.shot_interval()))
	assert_eq(model.transform, Transform3D.IDENTITY, "back at rest once the cooldown ends")


func test_shield_bash_pushes_forward_and_returns() -> void:
	var shield: WeaponData = _select(_weapons.get_secondary_choices(), WeaponTypes.Class.SHIELD, false)
	await wait_physics_frames(_seconds(1.5))
	assert_eq(_weapons.get_current_data().definition(), shield)
	var model: Node3D = _view.get_current_model()
	await _press(&"fire")
	await wait_physics_frames(_seconds(shield.shot_interval() * 0.2))
	assert_lt(model.position.z, -0.15, "bashing forward")
	await wait_physics_frames(_seconds(shield.shot_interval()))
	assert_eq(model.transform, Transform3D.IDENTITY)
