class_name DeathScreen
extends Control
## Shown while the player is dead: what killed them and the respawn countdown.

const ZONE_NAMES: PackedStringArray = ["Headshot", "Torso", "Limb"]
const SOURCE_NAMES: PackedStringArray = ["ballistic", "pellet", "splash", "melee"]

var health: PlayerHealth
var _shade: ColorRect
var _title: Label
var _detail: Label
var _countdown: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade = ColorRect.new()
	_shade.color = Color(0.25, 0.0, 0.0, 0.55)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	rows.offset_left = -300
	rows.offset_right = 300
	rows.offset_top = -70
	rows.offset_bottom = 70
	add_child(rows)
	_title = _label(rows, 40)
	_title.text = "YOU WERE KILLED"
	_detail = _label(rows, 18)
	_countdown = _label(rows, 18)
	visible = false


func _label(parent: Control, font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	parent.add_child(label)
	return label


func bind(target: PlayerHealth) -> void:
	health = target
	health.died.connect(_on_died.unbind(2))
	health.respawned.connect(func() -> void: visible = false)


func _on_died() -> void:
	_detail.text = "%s · %s" % [ZONE_NAMES[health.last_death_zone], SOURCE_NAMES[health.last_death_source]]
	visible = true
	_process(0.0)


func get_countdown_text() -> String:
	return _countdown.text


func _process(_delta: float) -> void:
	if not visible or health == null:
		return
	_countdown.text = "Respawning in %.1f s" % health.respawn_time_left()
