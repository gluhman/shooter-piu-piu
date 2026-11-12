shader_type canvas_item;

uniform float scan_position = -0.2;
uniform vec4 tint_color : source_color = vec4(0.80, 0.88, 0.55, 1.0);

float horizontal_row_mark(vec2 uv) {
	return (9.0 + fract(uv.y * 36.0)) * 0.1;
}

void fragment() {
	float distance_to_scan = UV.y - scan_position;
	float band = 1.0 / (1.0 + 180.0 * distance_to_scan * distance_to_scan);
	vec2 p = abs(UV - 0.5 + vec2(0.012 * band * sin(UV.y * 80.0), 0.0));
	float ring = 1.0 - smoothstep(0.008, 0.023, abs(length(p) - 0.31));
	float axes = (1.0 - smoothstep(0.008, 0.024, min(p.x, p.y))) *
		smoothstep(0.20, 0.22, max(p.x, p.y)) * (1.0 - smoothstep(0.42, 0.44, max(p.x, p.y)));
	float center = 1.0 - smoothstep(0.022, 0.047, length(p));
	float brightness = horizontal_row_mark(UV) * (0.82 + band * 0.18);
	COLOR *= vec4(tint_color.rgb * brightness, max(max(ring, axes), center));
}
