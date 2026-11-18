class_name Armory
extends Control
signal saved(config: LoadoutConfig)
signal cancelled

var config: LoadoutConfig
var save_path: String = LoadoutConfig.SAVE_PATH
var draft: LoadoutConfig
var role: WeaponTypes.Role = WeaponTypes.Role.PRIMARY
var weapon_picker: OptionButton
var attachment_pickers: Array[OptionButton] = []
var preview: WeaponPreview
var save_button: Button
var cancel_button: Button
var _primary: Button
var _secondary: Button
var _rotate_left: Button
var _rotate_right: Button
var _demonstrate: Button
var _stat_scroll: ScrollContainer
var _stats: GridContainer
var _status: Label
var _loadout_label: Label


func _ready() -> void:
	draft = config.copy()
	var margin: MarginContainer = MenuStyle.backdrop(self)
	for type: String in ["Button", "OptionButton"]:
		theme.set_font_size("font_size", type, 14)
		for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			var box: StyleBox = theme.get_stylebox(state, type)
			box.content_margin_top = 5
			box.content_margin_bottom = 5
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	margin.add_child(rows)
	rows.add_child(MenuStyle.label("ARMORY", 30))
	_loadout_label = MenuStyle.label("", 16, MenuStyle.ACCENT)
	rows.add_child(_loadout_label)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	rows.add_child(columns)
	var choices := VBoxContainer.new()
	choices.custom_minimum_size.x = 285
	choices.add_theme_constant_override("separation", 6)
	columns.add_child(choices)
	_primary = MenuStyle.button("Primary", select_role.bind(WeaponTypes.Role.PRIMARY))
	_secondary = MenuStyle.button("Secondary", select_role.bind(WeaponTypes.Role.SECONDARY))
	var roles := HBoxContainer.new()
	choices.add_child(roles)
	roles.add_child(_primary)
	roles.add_child(_secondary)
	_primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_secondary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_child(MenuStyle.label("WEAPON", 14, MenuStyle.MUTED))
	weapon_picker = OptionButton.new()
	weapon_picker.item_selected.connect(_weapon_selected)
	choices.add_child(weapon_picker)
	choices.add_child(HSeparator.new())
	for slot: int in WeaponTypes.SLOT_NAMES.size():
		choices.add_child(MenuStyle.label(WeaponTypes.SLOT_NAMES[slot], 14, MenuStyle.MUTED))
		var picker := OptionButton.new()
		picker.item_selected.connect(_attachment_selected.bind(slot))
		choices.add_child(picker)
		attachment_pickers.append(picker)
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(middle)
	middle.add_child(MenuStyle.label("WEAPON PREVIEW", 14, MenuStyle.MUTED))
	preview = WeaponPreview.new()
	middle.add_child(preview)
	var preview_buttons := HBoxContainer.new()
	middle.add_child(preview_buttons)
	_rotate_left = MenuStyle.button("Rotate left", preview.rotate_by.bind(-1.0))
	_rotate_right = MenuStyle.button("Rotate right", preview.rotate_by.bind(1.0))
	_demonstrate = MenuStyle.button("Show handling", preview.demonstrate)
	for button: Button in [_rotate_left, _rotate_right, _demonstrate]:
		preview_buttons.add_child(button)
	var stats_column := VBoxContainer.new()
	stats_column.custom_minimum_size.x = 360
	columns.add_child(stats_column)
	stats_column.add_child(MenuStyle.label("BASE → FITTED   /   CHANGE", 14, MenuStyle.MUTED))
	_stat_scroll = ScrollContainer.new()
	_stat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stat_scroll.follow_focus = true
	_stat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_stat_scroll.focus_mode = Control.FOCUS_ALL
	_stat_scroll.gui_input.connect(_scroll_input)
	stats_column.add_child(_stat_scroll)
	_stats = GridContainer.new()
	_stats.columns = 4
	_stats.add_theme_constant_override("h_separation", 10)
	_stats.add_theme_constant_override("v_separation", 8)
	_stat_scroll.add_child(_stats)
	stats_column.add_child(MenuStyle.label("Focus stats: Left/Right scrolls", 12, MenuStyle.MUTED))
	_status = MenuStyle.label("Choose a weapon and attachments. Save applies the loadout.", 14, MenuStyle.MUTED)
	rows.add_child(_status)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	rows.add_child(footer)
	save_button = MenuStyle.button("Save & Back", save)
	cancel_button = MenuStyle.button("Cancel", func() -> void: cancelled.emit())
	footer.add_child(save_button)
	footer.add_child(cancel_button)
	footer.add_child(MenuStyle.label("D-pad / arrows: navigate   A / Enter: select   B / Esc: cancel", 14, MenuStyle.MUTED))
	refresh()
	weapon_picker.grab_focus()


func select_role(value: WeaponTypes.Role) -> void:
	role = value
	refresh()
	weapon_picker.grab_focus()


func select_weapon(definition: WeaponData) -> bool:
	if not draft.select(role, definition):
		return false
	refresh()
	return true


func set_attachment(slot: WeaponTypes.Slot, attachment: AttachmentData) -> bool:
	if not draft.set_attachment(draft.selection(role), slot, attachment):
		return false
	refresh()
	return true


func _weapon_selected(index: int) -> void:
	select_weapon(weapon_picker.get_item_metadata(index) as WeaponData)


func _attachment_selected(index: int, slot: int) -> void:
	set_attachment(slot as WeaponTypes.Slot, attachment_pickers[slot].get_item_metadata(index) as AttachmentData)


func refresh() -> void:
	var definition: WeaponData = draft.selection(role)
	var build: WeaponBuild = draft.get_build(definition)
	_loadout_label.text = "%s  /  %s" % [draft.primary.display_name, draft.secondary.display_name]
	_primary.text = "● Primary" if role == WeaponTypes.Role.PRIMARY else "Primary"
	_secondary.text = "● Secondary" if role == WeaponTypes.Role.SECONDARY else "Secondary"
	weapon_picker.clear()
	for choice: WeaponData in draft.choices(role):
		var index: int = weapon_picker.item_count
		weapon_picker.add_item(choice.display_name)
		weapon_picker.set_item_metadata(index, choice)
		if choice == definition:
			weapon_picker.select(index)
	for slot: int in attachment_pickers.size():
		var picker: OptionButton = attachment_pickers[slot]
		picker.clear()
		picker.disabled = not WeaponTypes.allows_slot(definition.weapon_class, slot as WeaponTypes.Slot)
		picker.add_item("Unavailable" if picker.disabled else "None (native)")
		picker.set_item_metadata(0, null)
		for attachment: AttachmentData in draft.attachment_catalog().for_slot(slot as WeaponTypes.Slot, definition.weapon_class):
			var index: int = picker.item_count
			picker.add_item(attachment.display_name)
			picker.set_item_metadata(index, attachment)
			if attachment == build.get_attachment(slot as WeaponTypes.Slot):
				picker.select(index)
	for child: Node in _stats.get_children():
		child.free()
	for row: Dictionary in StatComparison.rows(definition, build.get_stats()):
		_stats.add_child(MenuStyle.label(row.label, 14))
		_stats.add_child(MenuStyle.label(StatComparison.format_value(row.base, row.unit), 14, MenuStyle.MUTED))
		_stats.add_child(MenuStyle.label(StatComparison.format_value(row.fitted, row.unit), 14))
		var delta: float = row.delta
		var color: Color = MenuStyle.MUTED
		if not is_zero_approx(delta):
			color = Color(0.5, 0.82, 0.64) if ((delta < 0.0) == bool(row.lower_better)) else Color(0.95, 0.61, 0.48)
		_stats.add_child(MenuStyle.label(StatComparison.format_value(delta, row.unit, true), 14, color))
	preview.show_build(build)
	var focusables: Array[Control] = [_primary, _secondary, weapon_picker]
	for picker: OptionButton in attachment_pickers:
		if not picker.disabled:
			focusables.append(picker)
	focusables.append_array([_rotate_left, _rotate_right, _demonstrate, _stat_scroll, save_button, cancel_button])
	SettingsPanel.wire_focus(focusables)


func save() -> void:
	var error: Error = draft.save_to_disk(save_path)
	if error != OK:
		_status.text = "Could not save the loadout. Please try again or cancel."
		return
	saved.emit(draft.copy())


func _scroll_input(event: InputEvent) -> void:
	if get_viewport().gui_get_focus_owner() == _stat_scroll:
		if event.is_action_pressed("ui_right"):
			_stat_scroll.scroll_vertical += 80
			_stat_scroll.accept_event()
		elif event.is_action_pressed("ui_left"):
			_stat_scroll.scroll_vertical -= 80
			_stat_scroll.accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		cancelled.emit()
		get_viewport().set_input_as_handled()
