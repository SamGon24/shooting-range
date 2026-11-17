// Sniper scope overlay: black outside a circular lens, with a thin
// crosshair and a soft dark ring near the lens edge.
shader_type canvas_item;

// Viewport width divided by height; set from script.
uniform int reticle_kind = 4;
uniform float aspect = 1.7778;
// Lens radius as a fraction of the screen height.
uniform float radius : hint_range(0.1, 0.6) = 0.46;
uniform float edge_softness : hint_range(0.0, 0.05) = 0.006;
// Crosshair line half-width and centre gap, as fractions of screen height.
uniform float line_half_width : hint_range(0.0, 0.01) = 0.0011;
uniform float centre_gap : hint_range(0.0, 0.1) = 0.012;
uniform float centre_dot_radius : hint_range(0.0, 0.01) = 0.0022;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	float distance_from_centre = length(p);

	float outside = smoothstep(radius, radius + edge_softness, distance_from_centre);
	float ring = smoothstep(radius * 0.72, radius, distance_from_centre) * 0.4;

	float lines = 0.0;
	if (abs(p.y) < line_half_width && abs(p.x) > centre_gap) {
		lines = 0.85;
	}
	if (abs(p.x) < line_half_width && abs(p.y) > centre_gap) {
		lines = 0.85;
	}
	if (distance_from_centre < centre_dot_radius) {
		lines = 0.85;
	}

	if (reticle_kind == 1) {
		float dot_alpha = 1.0 - smoothstep(centre_dot_radius, centre_dot_radius + 0.001, distance_from_centre);
		COLOR = vec4(1.0, 0.12, 0.08, dot_alpha);
	} else {
		if (reticle_kind == 2) {
			lines = (abs(p.x) < line_half_width || abs(p.y) < line_half_width) ? 0.85 : 0.0;
		} else if (reticle_kind == 3) {
			float tick_x = abs(mod(abs(p.x) + 0.025, 0.05) - 0.025);
			float tick_y = abs(mod(abs(p.y) + 0.025, 0.05) - 0.025);
			if ((tick_x < line_half_width && abs(p.y) < 0.008) || (tick_y < line_half_width && abs(p.x) < 0.008)) {
				lines = 0.85;
			}
		}
		// Kind 4 retains the original MVP sniper reticle exactly.
		COLOR = vec4(0.0, 0.0, 0.0, max(outside, max(lines, ring)));
	}
}
