class_name PerfProbe
extends Node
## Command-line frame-rate check for the 60 fps budget.
##
## Does nothing unless the game is started with the user argument
## `--perf-probe`. It then sprints the player downrange while sweeping the
## view, measures frame times for a few seconds, prints a summary to stdout
## and quits.
##
##   godot --path . -- --perf-probe                              (as played)
##   godot --path . --disable-vsync --max-fps 0 -- --perf-probe  (uncapped)
##   godot --path . -- --perf-probe --perf-fire                  (firing)
##   godot --path . -- --perf-probe --perf-fire --perf-weapon=shotgun
##
## With `--perf-fire` the player walks instead of sprinting (sprinting blocks
## firing). Automatic guns hold the trigger; pump guns receive press/release
## edges and interrupt shell loading once a round is ready.
##
## Adding `--perf-cold` holds all firing back until the warm-up ends, so the
## first shot, first impact and first reload of a session land inside the
## measurement. Without it they happen during the warm-up and a first-use
## stall can hide there; the report's worst frame then shows it.
##
## Adding `--perf-reload` presses reload whenever the gun has fired at least
## one round, so the run is dominated by tactical reloads: handling
## animation, magazine release and the pooled physics drops.
##
## The report includes the real vsync mode and how much of the run the window
## was focused. Keep the window in front while it runs: an unfocused or
## hidden window is paced differently by macOS and gives misleading numbers.

const ARGUMENT: String = "--perf-probe"
const FIRE_ARGUMENT: String = "--perf-fire"
const RELOAD_ARGUMENT: String = "--perf-reload"
const COLD_ARGUMENT: String = "--perf-cold"
const PLAYER_GROUP: StringName = &"player"
const WARMUP_SECONDS: float = 2.0
const MEASURE_SECONDS: float = 10.0
const SWEEP_DEGREES: float = 50.0
const SWEEP_PERIOD_SECONDS: float = 4.0
const GUARD_INTERVAL_TICKS: int = 15
const GUARD_TEST_DISTANCE_M: float = 2.0
const GUARD_ROUND: ProjectileSpec = preload("res://debug/data/guard_probe_round.tres")

var _player: PlayerController
var _elapsed: float = 0.0
var _last_ticks_usec: int = 0
var _frame_times_usec: PackedInt64Array = PackedInt64Array()
var _probe_optic: AttachmentData
var _lens_peak_size: int = 0
var _lens_frames: int = 0
var _focused_frames: int = 0
var _firing: bool = false
var _shots: int = 0
var _weapons: WeaponController
var _system: ProjectileSystem
var _peak_projectiles: int = 0
var _hits: int = 0
var _stress: Node
var _min_ragdoll_parts: int = 1000000
var _max_ragdoll_parts: int = 0
var _guard_ticks: int = 0
var _blasts: int = 0
var _guard_hits: int = 0
var _reload_stress: bool = false
var _cold: bool = false
var _reloads: int = 0
var _drops: int = 0
var _drop_pool: MagazineDropPool
var _peak_drops: int = 0


func _ready() -> void:
	if not OS.get_cmdline_user_args().has(ARGUMENT):
		set_process(false)
		set_physics_process(false)
		return
	if OS.get_cmdline_user_args().has("--perf-2x"):
		_probe_optic = preload("res://weapons/attachments/data/scope_2x.tres")
	elif OS.get_cmdline_user_args().has("--perf-4x"):
		_probe_optic = preload("res://weapons/attachments/data/scope_4x.tres")
	elif OS.get_cmdline_user_args().has("--perf-hybrid"):
		_probe_optic = preload("res://weapons/attachments/data/hybrid_35x.tres")
	_firing = OS.get_cmdline_user_args().has(FIRE_ARGUMENT)
	_reload_stress = _firing and OS.get_cmdline_user_args().has(RELOAD_ARGUMENT)
	_cold = _firing and OS.get_cmdline_user_args().has(COLD_ARGUMENT)
	process_physics_priority = -20
	set_physics_process(_firing)
	Input.action_press("move_forward")
	if _firing:
		if not _cold:
			Input.action_press("fire")
		_count_shots.call_deferred()
	else:
		Input.action_press("sprint")
	_last_ticks_usec = Time.get_ticks_usec()


func _count_shots() -> void:
	var weapons := get_tree().get_first_node_in_group(WeaponController.GROUP) as WeaponController
	_weapons = weapons
	if weapons != null:
		_select_weapon()
		if _probe_optic != null:
			weapons.request_attachment(WeaponTypes.Slot.OPTIC, _probe_optic)
			Input.action_press("aim")
		weapons.shot_fired.connect(func(_data: WeaponData) -> void: _shots += 1)
		weapons.reload_started.connect(func(_empty: bool, _duration: float) -> void: _reloads += 1)
	var view := get_tree().get_first_node_in_group(WeaponView.GROUP) as WeaponView
	if view != null:
		_drop_pool = view.get_drop_pool()
		view.get_animator().copy_released.connect(func(_part: Node3D, _follower: Node3D) -> void: _drops += 1)
	var projectiles := get_tree().get_first_node_in_group(ProjectileSystem.GROUP) as ProjectileSystem
	_system = projectiles
	if projectiles != null:
		projectiles.projectile_fired.connect(_on_projectile_fired)
		projectiles.projectile_hit.connect(_on_projectile_hit)
	var explosions := get_tree().get_first_node_in_group(ExplosionSystem.GROUP) as ExplosionSystem
	if explosions != null:
		explosions.exploded.connect(func(_point: Vector3, _data: ExplosionData) -> void: _blasts += 1)


func _select_weapon() -> void:
	var prefix: String = "--perf-weapon="
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with(prefix):
			continue
		var classes: Dictionary[String, WeaponTypes.Class] = {
			"rifle": WeaponTypes.Class.RIFLE, "smg": WeaponTypes.Class.SMG,
			"lmg": WeaponTypes.Class.LMG, "shotgun": WeaponTypes.Class.SHOTGUN,
			"sniper": WeaponTypes.Class.SNIPER, "pistol": WeaponTypes.Class.PISTOL,
			"rocket": WeaponTypes.Class.ROCKET, "knife": WeaponTypes.Class.KNIFE,
			"shield": WeaponTypes.Class.SHIELD,
		}
		var weapon_key: String = argument.trim_prefix(prefix)
		if not classes.has(weapon_key):
			push_warning("PerfProbe: unknown weapon '%s'" % weapon_key)
			return
		var secondary: bool = classes[weapon_key] >= WeaponTypes.Class.PISTOL
		var choices: Array[WeaponData] = _weapons.get_secondary_choices() if secondary else _weapons.get_primary_choices()
		for definition: WeaponData in choices:
			if definition.weapon_class == classes[weapon_key]:
				if secondary:
					_weapons.request_secondary(definition)
				else:
					_weapons.request_primary(definition)
				return


func _physics_process(_delta: float) -> void:
	if OS.get_cmdline_user_args().has("--perf-controller") and _player != null:
		_player._controller_look(_delta, true)
	if _weapons == null or _weapons.get_current_data() == null:
		return
	if _cold and _elapsed < WARMUP_SECONDS:
		return
	if _drop_pool != null:
		_peak_drops = maxi(_peak_drops, _drop_pool.active_count())
	if _reload_stress:
		_press_reload_when_possible()
	if _weapons.get_current_data().guard != null:
		_guard_ticks = (_guard_ticks + 1) % GUARD_INTERVAL_TICKS
		if _guard_ticks == 0 and _system != null:
			# One-tick incoming flight exercises real blocks while walking /
			# sweeping. A 15 m test round can be dodged during its flight.
			var player: PlayerController = _weapons.player
			var aim: Basis = player.get_aim_basis()
			_system.fire(player.get_eye_position() - aim.z * GUARD_TEST_DISTANCE_M, aim.z, GUARD_ROUND)
	if _weapons.get_current_data().automatic:
		if not Input.is_action_pressed("fire"):
			Input.action_press("fire")
		return
	# Pump / bolt weapons need real press/release edges, including a fresh
	# pull after reload. Keep enlarged shell capacities from spending the
	# whole measurement loading: close and fire as soon as a shell is ready.
	if Input.is_action_pressed("fire"):
		Input.action_release("fire")
		return
	var logic: WeaponLogic = _weapons.get_current_logic()
	if logic.is_reloading() and logic.ammo > 0 and logic.data.reload_policy != null and logic.data.reload_policy.kind == ReloadData.Kind.SHELL:
		Input.action_press("fire")
		return
	if logic.state in [WeaponLogic.State.READY, WeaponLogic.State.FIRING] and logic.get_time_to_next_shot() <= WeaponLogic.TIME_EPSILON:
		Input.action_press("fire")


func _press_reload_when_possible() -> void:
	if Input.is_action_pressed("reload"):
		Input.action_release("reload")
		return
	var logic: WeaponLogic = _weapons.get_current_logic()
	if logic.data.uses_ammo and logic.ammo > 0 and logic.ammo < logic.data.magazine_size and logic.can_reload():
		Input.action_press("reload")


func _on_projectile_fired(_slot: int, _origin: Vector3, _velocity: Vector3, _spec: ProjectileSpec) -> void:
	_peak_projectiles = maxi(_peak_projectiles, _system.get_active_count())


func _on_projectile_hit(hit: ProjectileHit) -> void:
	_hits += 1
	if hit.collider is WeaponGuard and not hit.spec.stats_eligible:
		_guard_hits += 1


func _process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group(PLAYER_GROUP) as PlayerController
		if _player != null:
			# The probe drives the view itself; never grab the real mouse.
			_player.mouse_look_enabled = false

	var now: int = Time.get_ticks_usec()
	var frame_usec: int = now - _last_ticks_usec
	_last_ticks_usec = now
	_elapsed += delta

	if _player != null:
		# Sweep the view left and right so the whole range gets drawn.
		var sweep: float = sin(_elapsed / SWEEP_PERIOD_SECONDS * TAU)
		_player.yaw = deg_to_rad(SWEEP_DEGREES) * sweep
		_player.pitch = deg_to_rad(-4.0)

	if _probe_optic != null and _weapons != null:
		var data: WeaponData = _weapons.get_current_data()
		if data != null and data.optic_kind != _probe_optic.optic_kind:
			_weapons.request_attachment(WeaponTypes.Slot.OPTIC, _probe_optic)
		# Keep the optic visible through reloads for the worst-case render budget.
		var overlay := get_tree().get_first_node_in_group(&"hybrid_optic") as HybridOptic
		if overlay != null and data != null:
			var view := get_tree().get_first_node_in_group(WeaponView.GROUP) as WeaponView
			var optic_pose: Dictionary = view.get_optic_pose() if view != null else {}
			if not optic_pose.is_empty():
				optic_pose["world"] = optic_pose["rest"]
				overlay.update_view(data, 1.0, get_viewport().get_camera_3d(), optic_pose)
			if overlay.lens_active and _elapsed >= WARMUP_SECONDS:
				_lens_frames += 1
				_lens_peak_size = maxi(_lens_peak_size,overlay.render_size)
	if _elapsed < WARMUP_SECONDS:
		return
	_frame_times_usec.append(frame_usec)
	if _stress == null:
		_stress = get_tree().get_first_node_in_group(&"range_stress")
	if _stress != null:
		var active: int = int(_stress.call("get_active_part_count"))
		_min_ragdoll_parts = mini(_min_ragdoll_parts, active)
		_max_ragdoll_parts = maxi(_max_ragdoll_parts, active)
	if DisplayServer.window_is_focused():
		_focused_frames += 1
	if _elapsed >= WARMUP_SECONDS + MEASURE_SECONDS:
		_report_and_quit()


func _report_and_quit() -> void:
	set_process(false)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	Input.action_release("fire")
	Input.action_release("reload")

	var sorted: PackedInt64Array = _frame_times_usec.duplicate()
	sorted.sort()
	var count: int = sorted.size()
	var total_usec: int = 0
	for frame_usec: int in sorted:
		total_usec += frame_usec

	var average_ms: float = float(total_usec) / float(count) / 1000.0
	# "1% low": the average frame rate of the slowest 1% of frames.
	var slow_count: int = maxi(int(float(count) * 0.01), 1)
	var slow_total: int = 0
	for index: int in range(count - slow_count, count):
		slow_total += sorted[index]
	var slow_ms: float = float(slow_total) / float(slow_count) / 1000.0
	# Over 16.67 ms means below 60 fps when uncapped. With vsync on, frames
	# hover around 16.67 ms, so a missed refresh shows up as a frame over 25 ms.
	var over_budget: int = 0
	var missed_refresh: int = 0
	for frame_usec: int in sorted:
		if frame_usec > 16_667:
			over_budget += 1
		if frame_usec > 25_000:
			missed_refresh += 1

	var window_size: Vector2i = DisplayServer.window_get_size()
	var viewport_size: Vector2i = get_viewport().get_visible_rect().size
	print("=== PERF PROBE ===")
	print("renderer:        %s" % RenderingServer.get_current_rendering_method())
	if _probe_optic != null:
		print("optic:           ", _probe_optic.display_name)
		print("optic view:      native-resolution lens")
		print("lens frames:     %d / %d" % [_lens_frames, count])
		print("lens pixels:     %d square (peak cached)" % _lens_peak_size)
	print("adapter:         %s" % RenderingServer.get_video_adapter_name())
	print("window pixels:   %dx%d" % [window_size.x, window_size.y])
	print("vsync mode:      %s" % _vsync_mode_name(DisplayServer.window_get_vsync_mode()))
	# macOS only holds an OpenGL window to the refresh rate while it is in
	# front, so a vsync reading means nothing unless this is near 100%.
	print("window focused:  %.0f%% of measured frames" % (100.0 * float(_focused_frames) / float(count)))
	print("viewport:        %dx%d" % [viewport_size.x, viewport_size.y])
	print("frames measured: %d over %.1f s" % [count, float(total_usec) / 1_000_000.0])
	print("average:         %.1f fps (%.2f ms)" % [1000.0 / average_ms, average_ms])
	print("median:          %.2f ms" % (float(sorted[int(float(count) * 0.5)]) / 1000.0))
	print("1%% low:          %.1f fps (%.2f ms)" % [1000.0 / slow_ms, slow_ms])
	print("worst frame:     %.2f ms" % (float(sorted[count - 1]) / 1000.0))
	print("frames > 16.67 ms: %d (%.1f%%)" % [over_budget, 100.0 * float(over_budget) / float(count)])
	print("frames > 25 ms:  %d (%.1f%%)" % [missed_refresh, 100.0 * float(missed_refresh) / float(count)])
	print("draw calls:      %d" % int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	print("primitives:      %d" % int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	if _player != null:
		print("player speed:    %.2f m/s" % _player.get_horizontal_speed())
	if _firing:
		if _weapons != null:
			print("weapon:          %s" % _weapons.get_current_data().display_name)
		if _system != null:
			print("projectiles:     %d peak / %d capacity, %d dropped" % [_peak_projectiles, _system.capacity, _system.get_dropped_count()])
		print("shots fired:     %d (%d hits) since start" % [_shots, _hits])
		print("armed blasts:    %d since start" % _blasts)
		print("shield blocks:   %d non-scoring rounds since start" % _guard_hits)
		print("reloads:         %d started, %d magazines dropped since start" % [_reloads, _drops])
		if _drop_pool != null:
			print("dropped bodies:  %d peak active / %d pooled" % [_peak_drops, _drop_pool.capacity])
	if _stress != null:
		print("stress props:    %d (awake throughout)" % int(_stress.call("get_prop_count")))
		print("ragdoll parts:   %d min / %d max during measurement" % [_min_ragdoll_parts, _max_ragdoll_parts])
	get_tree().quit()


func _vsync_mode_name(mode: DisplayServer.VSyncMode) -> String:
	match mode:
		DisplayServer.VSYNC_DISABLED:
			return "disabled"
		DisplayServer.VSYNC_ENABLED:
			return "enabled"
		DisplayServer.VSYNC_ADAPTIVE:
			return "adaptive"
		DisplayServer.VSYNC_MAILBOX:
			return "mailbox"
		_:
			return "unknown (%d)" % mode
