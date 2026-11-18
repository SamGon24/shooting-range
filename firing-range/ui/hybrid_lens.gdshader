shader_type canvas_item;
render_mode unshaded;
void fragment() {
	if (length(UV - vec2(0.5)) > 0.5) { discard; }
	COLOR = texture(TEXTURE, UV);
}
