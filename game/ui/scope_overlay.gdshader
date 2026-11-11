shader_type canvas_item;

uniform vec4 reticle : source_color = vec4(0.04, 0.04, 0.037, 1.0);

void fragment() {
	vec2 p = (SCREEN_UV - vec2(0.5)) / SCREEN_PIXEL_SIZE * SCREEN_PIXEL_SIZE.y;
	float r = length(p);
	float edge = smoothstep(0.438, 0.446, r);
	float rim = smoothstep(0.417, 0.443, r);
	vec2 d = abs(p);
	float hair = 1.0 - smoothstep(0.0007, 0.0018, min(d.x, d.y));
	float post = (1.0 - smoothstep(0.002, 0.004, min(d.x, d.y))) * smoothstep(0.113, 0.122, max(d.x, d.y));
	float ticks = (1.0 - smoothstep(0.0007, 0.0018, abs(fract(d.y * 31.0 + 0.5) - 0.5) / 31.0))
		* (1.0 - smoothstep(0.009, 0.011, d.x)) * smoothstep(0.016, 0.018, d.y) * (1.0 - smoothstep(0.10, 0.11, d.y));
	float line = max(hair, max(post, ticks)) * (1.0 - rim);
	COLOR = vec4(mix(reticle.rgb, vec3(0.009, 0.011, 0.011), max(rim, edge)), max(edge, max(rim * 0.76, line)));
}
