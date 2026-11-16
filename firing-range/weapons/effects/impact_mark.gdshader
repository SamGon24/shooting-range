// Bullet impact mark: a soft dark disc drawn on a quad that sits just off
// the surface. Used by one MultiMesh for every mark in the world.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

uniform vec4 mark_color : source_color = vec4(0.04, 0.04, 0.045, 0.9);
// Where the solid centre ends and the soft edge begins, 0 to 1.
uniform float core : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	float distance_from_centre = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = mark_color.rgb;
	ALPHA = mark_color.a * (1.0 - smoothstep(core, 1.0, distance_from_centre));
}
