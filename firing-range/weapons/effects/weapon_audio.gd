class_name WeaponAudio
extends Node
## Plays placeholder weapon sounds in response to the weapon controller's
## signals. Sound only; it has no effect on gameplay.

@export var controller: WeaponController
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var shot_volume_db: float = -9.0
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var handling_volume_db: float = -14.0
## Shots that can overlap before the oldest is cut off.
@export_range(1, 16) var shot_polyphony: int = 6

var _shot_players: Dictionary[WeaponData, AudioStreamPlayer] = {}
var _handling_player: AudioStreamPlayer
var _click_high: AudioStreamWAV
var _click_mid: AudioStreamWAV
var _click_low: AudioStreamWAV


func _ready() -> void:
	if controller == null:
		push_error("WeaponAudio: `controller` must be assigned.")
		return
	for data: WeaponData in controller.get_definitions():
		var player := AudioStreamPlayer.new()
		player.bus = &"Effects"
		player.stream = SfxFactory.gunshot(data.shot_sound_pitch_hz, data.shot_sound_duration)
		player.volume_db = shot_volume_db
		player.max_polyphony = shot_polyphony
		add_child(player)
		_shot_players[data] = player

	_handling_player = AudioStreamPlayer.new()
	_handling_player.bus = &"Effects"
	_handling_player.volume_db = handling_volume_db
	_handling_player.max_polyphony = 3
	add_child(_handling_player)
	_click_high = SfxFactory.click(2200.0, 0.03)
	_click_mid = SfxFactory.click(1100.0, 0.05)
	_click_low = SfxFactory.click(520.0, 0.07)

	controller.shot_fired.connect(_on_shot_fired)
	controller.dry_fired.connect(_play_handling.bind(_click_high))
	controller.reload_started.connect(_on_reload_started)
	controller.reload_finished.connect(_play_handling.bind(_click_mid))
	controller.shell_inserted.connect(_on_shell_inserted)
	controller.weapon_changed.connect(_on_weapon_changed)


func _on_shot_fired(data: WeaponData) -> void:
	var player: AudioStreamPlayer = _shot_players.get(data.definition())
	if player != null:
		player.play()


func _on_reload_started(_is_empty: bool, _duration: float) -> void:
	_play_handling(_click_low)


func _on_weapon_changed(_data: WeaponData) -> void:
	_play_handling(_click_low)


func _on_shell_inserted(_ammo: int) -> void:
	_play_handling(_click_mid)


func _play_handling(stream: AudioStreamWAV) -> void:
	_handling_player.stream = stream
	_handling_player.play()
