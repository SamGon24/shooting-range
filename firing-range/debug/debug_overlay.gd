class_name DebugOverlay
extends CanvasLayer
## Development readout: FPS, frame time, player speed and movement state.
## Also hosts the temporary FOV/sensitivity hotkeys until the settings menu
## exists. Read-only with respect to gameplay.

const REFRESH_INTERVAL: float = 0.1
## Start hidden with `-- --hide-overlay`, for clean screenshots.
const HIDE_ARGUMENT: String = "--hide-overlay"
const PLAYER_GROUP: StringName = &"player"

var _player: PlayerController
var _time_to_refresh: float = 0.0
var _frame_count: int = 0
var _frame_time_sum: float = 0.0
var _frame_time_worst: float = 0.0

@onready var _label: Label = $Readout
@onready var _dot: ColorRect = $CentreDot


func _ready() -> void:
	if OS.get_cmdline_user_args().has(HIDE_ARGUMENT):
		visible = false
	_centre_dot()
	get_viewport().size_changed.connect(_centre_dot)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_toggle_overlay"):
		visible = not visible
	elif event.is_action_pressed("fov_increase"):
		ViewSettings.step_fov(1)
		ViewSettings.save_to_disk()
	elif event.is_action_pressed("fov_decrease"):
		ViewSettings.step_fov(-1)
		ViewSettings.save_to_disk()
	elif event.is_action_pressed("sensitivity_increase"):
		ViewSettings.step_sensitivity(1)
		ViewSettings.save_to_disk()
	elif event.is_action_pressed("sensitivity_decrease"):
		ViewSettings.step_sensitivity(-1)
		ViewSettings.save_to_disk()


func _process(delta: float) -> void:
	_frame_count += 1
	_frame_time_sum += delta
	_frame_time_worst = maxf(_frame_time_worst, delta)

	_time_to_refresh -= delta
	if _time_to_refresh > 0.0 or not visible:
		return
	_time_to_refresh = REFRESH_INTERVAL
	_refresh()
	_frame_count = 0
	_frame_time_sum = 0.0
	_frame_time_worst = 0.0


func _refresh() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group(PLAYER_GROUP) as PlayerController

	var average_ms: float = 0.0
	if _frame_count > 0:
		average_ms = _frame_time_sum / float(_frame_count) * 1000.0
	var viewport_size: Vector2i = get_viewport().get_visible_rect().size
	var aspect: float = float(viewport_size.x) / maxf(float(viewport_size.y), 1.0)

	var lines := PackedStringArray()
	lines.append(
		"%d fps   %.1f ms avg   %.1f ms worst   %dx%d"
		% [
			int(Engine.get_frames_per_second()),
			average_ms,
			_frame_time_worst * 1000.0,
			viewport_size.x,
			viewport_size.y,
		]
	)
	if _player != null:
		var state: String = _player.get_stance_name()
		if _player.is_sprinting:
			state += " + sprint"
		if not _player.is_grounded():
			state += " (air)"
		lines.append(
			"speed %.2f m/s   vertical %+.2f m/s   %s"
			% [_player.get_horizontal_speed(), _player.velocity.y, state]
		)
		var feet: Vector3 = _player.global_position
		lines.append(
			"pos x %.1f  y %.2f  z %.1f   downrange %.1f m"
			% [feet.x, feet.y, feet.z, maxf(-feet.z, 0.0)]
		)
	lines.append(
		"fov %.0f° vertical (%.0f° horizontal)   sensitivity %.3f °/count"
		% [
			ViewSettings.fov_degrees,
			ViewSettings.horizontal_fov_degrees(aspect),
			ViewSettings.mouse_sensitivity,
		]
	)
	lines.append("[ ] fov   - = sensitivity   F3 or \\ overlay   Esc free mouse")
	_label.text = "\n".join(lines)


func _centre_dot() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_dot.position = (viewport_size - _dot.size) * 0.5
