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
##
## With `--perf-fire` the player walks instead of sprinting (sprinting blocks
## firing) and holds the trigger, so the rifle fires full-auto and reloads
## for the whole run.
##
## The report includes the real vsync mode and how much of the run the window
## was focused. Keep the window in front while it runs: an unfocused or
## hidden window is paced differently by macOS and gives misleading numbers.

const ARGUMENT: String = "--perf-probe"
const FIRE_ARGUMENT: String = "--perf-fire"
const PLAYER_GROUP: StringName = &"player"
const WARMUP_SECONDS: float = 2.0
const MEASURE_SECONDS: float = 10.0
const SWEEP_DEGREES: float = 50.0
const SWEEP_PERIOD_SECONDS: float = 4.0

var _player: PlayerController
var _elapsed: float = 0.0
var _last_ticks_usec: int = 0
var _frame_times_usec: PackedInt64Array = PackedInt64Array()
var _focused_frames: int = 0
var _firing: bool = false
var _shots: int = 0
var _hits: int = 0


func _ready() -> void:
	if not OS.get_cmdline_user_args().has(ARGUMENT):
		set_process(false)
		return
	_firing = OS.get_cmdline_user_args().has(FIRE_ARGUMENT)
	Input.action_press("move_forward")
	if _firing:
		Input.action_press("fire")
		_count_shots.call_deferred()
	else:
		Input.action_press("sprint")
	_last_ticks_usec = Time.get_ticks_usec()


func _count_shots() -> void:
	var weapons := get_tree().get_first_node_in_group(WeaponController.GROUP) as WeaponController
	if weapons != null:
		weapons.shot_fired.connect(func(_data: WeaponData) -> void: _shots += 1)
	var projectiles := get_tree().get_first_node_in_group(ProjectileSystem.GROUP) as ProjectileSystem
	if projectiles != null:
		projectiles.projectile_hit.connect(func(_hit: ProjectileHit) -> void: _hits += 1)


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

	if _elapsed < WARMUP_SECONDS:
		return
	_frame_times_usec.append(frame_usec)
	if DisplayServer.window_is_focused():
		_focused_frames += 1
	if _elapsed >= WARMUP_SECONDS + MEASURE_SECONDS:
		_report_and_quit()


func _report_and_quit() -> void:
	set_process(false)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	Input.action_release("fire")

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
		print("shots fired:     %d (%d hits) since start" % [_shots, _hits])
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
