shader_type spatial;
render_mode cull_disabled;

uniform vec4 stripe_color : source_color = vec4(0.59, 0.19, 0.13, 1.0);
uniform vec4 linen_color : source_color = vec4(0.88, 0.78, 0.57, 1.0);

void vertex() {
	float billow = 1.0 - pow(abs(UV.y * 2.0 - 1.0), 2.0);
	VERTEX.y += billow * (0.15 + 0.018 * sin(TIME * 1.7 + UV.x * 10.0));
	VERTEX.y -= smoothstep(0.74, 1.0, abs(UV.y * 2.0 - 1.0)) * 0.11;
}

void fragment() {
	float band = smoothstep(0.46, 0.54, fract(UV.x * 5.0));
	vec2 weave_uv = UV * vec2(260.0, 150.0) * TAU;
	vec2 thread = sin(weave_uv);
	float weave = thread.x * thread.y;
	ALBEDO = mix(stripe_color.rgb, linen_color.rgb, band) * (0.95 + weave * 0.05);
	NORMAL_MAP = vec3(vec2(0.5) + thread * 0.12, 1.0);
	NORMAL_MAP_DEPTH = 0.32;
	ROUGHNESS = 0.94;
}
