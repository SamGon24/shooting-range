class_name ChallengeMenu
extends Control

const RULES: Array[ChallengeRule] = [
	preload("res://range/challenges/data/timed.tres"),
	preload("res://range/challenges/data/accuracy.tres"),
	preload("res://range/challenges/data/steel.tres"),
	preload("res://range/challenges/data/moving.tres")
]
signal selected(rule: ChallengeRule)
signal back
var scores: ChallengeScores
var result: ChallengeAttempt
var save_error: Error = OK

func _ready() -> void:
	GameInput.clear()
	var margin: MarginContainer = MenuStyle.backdrop(self)
	var rows := VBoxContainer.new()
	rows.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rows.add_theme_constant_override("separation", 10)
	margin.add_child(rows)
	var controls: Array[Control] = []
	if result == null:
		rows.add_child(MenuStyle.label("Range challenges", 32))
		for rule: ChallengeRule in RULES:
			var best: int = scores.best(rule.id)
			var caption: String = rule.title
			if best >= 0:
				caption += "    ·    Best " + rule.score_text(best)
			var choice: Button = MenuStyle.button(caption, selected.emit.bind(rule))
			rows.add_child(choice)
			controls.append(choice)
			var thresholds: String = "Bronze %s   ·   Silver %s   ·   Gold %s" % [
				rule.score_text(rule.medals.x), rule.score_text(rule.medals.y), rule.score_text(rule.medals.z)
			]
			rows.add_child(MenuStyle.label(rule.objective + "\n" + thresholds, 15, MenuStyle.MUTED))
	else:
		var rule: ChallengeRule = result.rule
		rows.add_child(MenuStyle.label(rule.title, 32))
		rows.add_child(MenuStyle.label(rule.medal(result.score()), 28, MenuStyle.ACCENT))
		rows.add_child(MenuStyle.label("Score   " + rule.score_text(result.score())))
		var best: int = scores.best(rule.id)
		if best >= 0:
			rows.add_child(MenuStyle.label("Personal best   " + rule.score_text(best)))
		if save_error != OK:
			rows.add_child(MenuStyle.label("Could not save this result."))
		var retry: Button = MenuStyle.button("Retry", selected.emit.bind(rule))
		rows.add_child(retry)
		controls.append(retry)
	var leave: Button = MenuStyle.button("Main menu" if result == null else "Challenges", back.emit)
	rows.add_child(leave)
	controls.append(leave)
	SettingsPanel.wire_focus(controls)
	controls[0].grab_focus()

func _input(event: InputEvent) -> void:
	# D-pad Right also navigates focused Controls. Handle the result shortcut first.
	if result != null and not event.is_echo() and event.is_action_pressed("challenge_retry"):
		get_viewport().set_input_as_handled()
		selected.emit(result.rule)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_echo() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back.emit()
