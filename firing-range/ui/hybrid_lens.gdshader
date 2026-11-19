shader_type canvas_item;
render_mode unshaded;
uniform sampler2D lens_image : repeat_disable, filter_linear;
uniform float radius = 187.2;
uniform float unit = 1.0;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * (radius + 40.0 * unit) * 2.0;
	vec2 q = p / unit;
	float d = length(p);
	float r = radius / unit;
	vec3 ink = vec3(0.055, 0.065, 0.07);
	vec3 body = vec3(0.16, 0.19, 0.21);
	vec3 edge = vec3(0.34, 0.38, 0.39);
	if (d <= radius) {
		vec2 sample_uv = vec2(0.5) + p / (radius * 2.0);
		vec3 scene = textureLod(lens_image, sample_uv, 0.0).rgb;
		bool cross = (abs(q.y) <= 1.0 && abs(q.x) >= 8.0 && abs(q.x) <= 80.0)
			|| (abs(q.x) <= 1.0 && abs(q.y) >= 8.0 && abs(q.y) <= 80.0);
		float tx = abs(mod(abs(q.x) - 25.0 + 10.0, 20.0) - 10.0);
		float ty = abs(mod(abs(q.y) - 25.0 + 10.0, 20.0) - 10.0);
		bool ticks = (abs(q.y) <= 4.0 && abs(q.x) >= 24.5 && abs(q.x) <= 65.5 && tx <= 0.5)
			|| (abs(q.x) <= 4.0 && abs(q.y) >= 24.5 && abs(q.y) <= 65.5 && ty <= 0.5);
		COLOR = vec4((cross || ticks || length(q) < 1.5) ? ink : scene, 1.0);
	} else if (d <= radius + 20.0 * unit) {
		float ring = (d - radius) / unit;
		vec3 color = (ring >= 5.0 && ring <= 17.0) ? body : ink;
		if (abs(ring - 18.0) <= 1.0 || ring <= 2.0) { color = edge; }
		COLOR = vec4(color, 1.0);
	} else if ((abs(q.x) <= 24.0 && q.y >= -r-27.0 && q.y <= -r-5.0)
		|| (q.x >= r+6.0 && q.x <= r+28.0 && abs(q.y) <= 20.0)
		|| (abs(q.x) <= 28.0 && q.y >= r+9.0 && q.y <= r+37.0)) {
		COLOR = vec4(body, 1.0);
	} else { discard; }
}
