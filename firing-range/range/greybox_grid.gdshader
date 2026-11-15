// Greybox surface: flat colour with a world-space metre grid.
//
// The grid is projected from world position (not UVs), so every box shows
// true 1 m cells regardless of its size, and adjacent boxes line up. Lines
// are anti-aliased and fade to their average tone when they get thinner than
// a pixel, so the 300 m end of the range does not shimmer.
shader_type spatial;
render_mode specular_disabled;

uniform vec3 base_color : source_color = vec3(0.42, 0.44, 0.46);
uniform vec3 line_color : source_color = vec3(0.30, 0.32, 0.34);
// Size of one minor cell in metres.
uniform float cell_size = 1.0;
// A heavier line every N minor cells.
uniform float major_every = 5.0;
// Line widths as a fraction of their cell.
uniform float minor_line_width : hint_range(0.0, 0.5) = 0.03;
uniform float major_line_width : hint_range(0.0, 0.5) = 0.012;
uniform float minor_strength : hint_range(0.0, 1.0) = 0.55;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

// Anti-aliased grid coverage (0 = no line, 1 = line), after Ben Golus's
// "pristine grid". `uv` is in cell units, `width` is a fraction of a cell.
float grid(vec2 uv, float width) {
	vec2 deriv = fwidth(uv);
	vec2 target_width = vec2(width);
	vec2 draw_width = clamp(target_width, deriv, vec2(0.5));
	vec2 line_aa = deriv * 1.5;
	vec2 grid_uv = 1.0 - abs(fract(uv) * 2.0 - 1.0);
	vec2 lines = 1.0 - smoothstep(draw_width - line_aa, draw_width + line_aa, grid_uv);
	lines *= clamp(target_width / draw_width, 0.0, 1.0);
	lines = mix(lines, target_width, clamp(deriv * 2.0 - 1.0, 0.0, 1.0));
	return mix(lines.x, 1.0, lines.y);
}

void fragment() {
	// Pick the projection plane from the dominant axis of the surface normal.
	vec3 n = abs(world_normal);
	vec2 plane = world_position.xz;
	if (n.x > n.y && n.x > n.z) {
		plane = world_position.zy;
	} else if (n.z > n.y) {
		plane = world_position.xy;
	}

	vec2 minor_uv = plane / cell_size;
	float minor = grid(minor_uv, minor_line_width) * minor_strength;
	float major = grid(minor_uv / major_every, major_line_width);

	ALBEDO = mix(base_color, line_color, max(minor, major));
	ROUGHNESS = 1.0;
}
