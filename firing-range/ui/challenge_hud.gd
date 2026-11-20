class_name ChallengeHud
extends CanvasLayer

signal retry_requested
signal completed(attempt: ChallengeAttempt)
var attempt: ChallengeAttempt
var player: PlayerController
var projectiles: ProjectileSystem
var _countdown: float = 3.0
var _closing: bool = false
var _display_time: int = -1
var _display_hits: int = -1
var _display_shots: int = -1
var _display_outside: bool = false
var _retry_prompt: String
var _status := Label.new()
var _panel := PanelContainer.new()

func _ready() -> void:
	layer = 8
	projectiles.shot_started.connect(_on_launch)
	projectiles.shot_finished.connect(attempt.finish_shot)
	for node: Node in get_tree().get_nodes_in_group(&"target_dummy"):
		var dummy := node as TargetDummy
		var kind := ChallengeRule.Target.MOVING if dummy.get_parent() is TargetRail else ChallengeRule.Target.STATIONARY
		dummy.damaged.connect(_dummy_hit.bind(kind))
	for node: Node in get_tree().get_nodes_in_group(&"steel_plate"):
		var plate := node as SteelPlate
		plate.rang.connect(_steel_hit.bind(plate))
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.offset_top = 10
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_status)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameInput.device_changed.connect(_update_prompt)
	_update_prompt()

func _update_prompt() -> void:
	_retry_prompt = GameInput.prompt("challenge_retry").trim_suffix(" - Physical")
	_display_hits = -1
	_refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED and is_node_ready():
		_update_prompt()

func _on_launch(id: int) -> void:
	if _countdown > 0 or not projectiles.is_scoring_shot(id):
		return
	if attempt.rule.target == ChallengeRule.Target.STEEL and player.global_position.z < 0:
		return
	attempt.launch(id)

func _dummy_hit(hit: ProjectileHit, _zone: TargetSettings.Zone, _amount: float, kind: ChallengeRule.Target) -> void:
	attempt.contact(hit.shot_id, kind)

func _steel_hit(plate: SteelPlate) -> void:
	attempt.contact(plate.last_hit.shot_id, ChallengeRule.Target.STEEL)

func _physics_process(delta: float) -> void:
	if _closing:
		return
	if _countdown > 0:
		_countdown = maxf(0, _countdown - delta)
	else:
		attempt.advance(delta)
	if attempt.done:
		_closing = true
		completed.emit(attempt)
	elif Engine.get_physics_frames() % 6 == 0:
		_refresh()

func _refresh() -> void:
	var clock: int = -ceili(_countdown) if _countdown > 0 else ceili(attempt.remaining)
	var outside: bool = attempt.rule.target == ChallengeRule.Target.STEEL and player.global_position.z < 0
	var shown_shots: int = attempt.shots if attempt.rule.shots_allowed > 0 else 0
	if clock == _display_time and attempt.hits == _display_hits and shown_shots == _display_shots and outside == _display_outside:
		return
	_display_time = clock
	_display_hits = attempt.hits
	_display_shots = shown_shots
	_display_outside = outside
	var progress: String
	if _countdown > 0:
		progress = "Starts in %d" % ceili(_countdown)
	elif outside:
		progress = "Return behind the firing line"
	elif attempt.rule.shots_allowed > 0 and attempt.shots == attempt.rule.shots_allowed:
		progress = "Waiting for final impacts"
	elif attempt.rule.shots_allowed > 0:
		progress = "%d of %d shots   ·   %d hits" % [attempt.shots, attempt.rule.shots_allowed, attempt.hits]
	else:
		progress = "%d s   ·   %d hits" % [ceili(attempt.remaining), attempt.hits]
	_status.text = "  %s   ·   %s  \n  %s   ·   %s Retry  " % [attempt.rule.title, progress, attempt.rule.objective, _retry_prompt]

func _unhandled_input(event: InputEvent) -> void:
	if not _closing and not event.is_echo() and event.is_action_pressed("challenge_retry"):
		_closing = true
		get_viewport().set_input_as_handled()
		retry_requested.emit()
