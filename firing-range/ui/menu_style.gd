class_name MenuStyle
extends RefCounted
## Shared text-only front-end theme and layout helpers.
const INK: Color = Color(0.90, 0.92, 0.89)
const MUTED: Color = Color(0.57, 0.64, 0.65)
const ACCENT: Color = Color(0.93, 0.76, 0.36)


static func theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	result.set_color("font_color", "Label", INK)
	for type: String in ["Button", "OptionButton", "CheckButton"]:
		for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color(0.14, 0.18, 0.19) if state != "hover" else Color(0.22, 0.27, 0.27)
			box.content_margin_left = 12
			box.content_margin_right = 12
			box.content_margin_top = 10
			box.content_margin_bottom = 10
			if state == "focus":
				box.bg_color = Color.TRANSPARENT
				box.set_border_width_all(2)
				box.border_color = ACCENT
			result.set_stylebox(state, type, box)
		result.set_color("font_color", type, INK)
		result.set_color("font_hover_color", type, Color.WHITE)
		result.set_color("font_focus_color", type, ACCENT)
		result.set_color("font_disabled_color", type, MUTED)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.set_border_width_all(2)
	focus.border_color = ACCENT
	result.set_stylebox("focus", "ScrollContainer", focus)
	result.set_color("font_color", "PopupMenu", INK)
	return result


static func label(text: String, size: int = 16, color: Color = INK) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	return result


static func button(text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.pressed.connect(action)
	return result


static func backdrop(parent: Control) -> MarginContainer:
	parent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.theme = theme()
	var background := ColorRect.new()
	background.color = Color(0.045, 0.06, 0.065)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	parent.add_child(margin)
	return margin
