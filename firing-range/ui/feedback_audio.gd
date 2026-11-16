class_name FeedbackAudio
extends Node
## Non-spatial confirmation sounds, independent of distant physical impacts.

@export var feedback: RangeFeedback
@export var polyphony: int = 4
@export_group("Hit")
@export var hit_volume_db: float = -15.0
@export var hit_start_hz: float = 1400.0
@export var hit_end_hz: float = 1000.0
@export var hit_seconds: float = 0.045
@export_group("Armor break")
@export var armor_volume_db: float = -11.0
@export var armor_start_hz: float = 2300.0
@export var armor_end_hz: float = 400.0
@export var armor_seconds: float = 0.16
@export_group("Kill")
@export var kill_volume_db: float = -9.0
@export var kill_start_hz: float = 1000.0
@export var kill_end_hz: float = 1800.0
@export var kill_seconds: float = 0.22

var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	_add_player(hit_start_hz, hit_end_hz, hit_seconds, hit_volume_db)
	_add_player(armor_start_hz, armor_end_hz, armor_seconds, armor_volume_db)
	_add_player(kill_start_hz, kill_end_hz, kill_seconds, kill_volume_db)
	if feedback != null:
		feedback.feedback.connect(_on_feedback)


func _add_player(start: float, end: float, duration: float, volume: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = SfxFactory.confirmation(start, end, duration)
	player.volume_db = volume
	player.max_polyphony = polyphony
	add_child(player)
	_players.append(player)


func _on_feedback(kind: HitFeedback.Kind, _point: Vector3, _amount: float, _headshot: bool) -> void:
	_players[kind].play()
