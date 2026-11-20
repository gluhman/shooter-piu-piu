shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}

float billows(vec2 p) {
	return noise(p) * 0.57 + noise(p * 2.13 + 4.7) * 0.29 + noise(p * 4.37 + 9.3) * 0.14;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float distance = COLOR.g * 2.0;
	float seed = COLOR.r * 31.0;
	float gas = billows(vec2(p.x * 2.7 + seed, p.y * 2.8 - TIME * 10.0));
	float curl = (noise(vec2(p.y * 3.0 - TIME * 7.0, seed)) - 0.5) * 0.65;
	float radius = length(vec2(p.x + curl, p.y * 0.85));
	float edge = 1.0 - smoothstep(0.25, 0.95, radius + (gas - 0.5) * 0.65);
	float tongues = smoothstep(0.28, 0.66, gas);
	float breakup = mix(1.0, tongues, smoothstep(0.12, 1.2, distance));
	float core = (1.0 - smoothstep(0.05, 0.26, distance)) * max(0.0, 1.0 - radius * 1.4);
	float heat = max(core, smoothstep(0.35, 0.8, gas) * 0.7);
	vec3 flame = mix(vec3(1.0, 0.045, 0.003), vec3(1.0, 0.46, 0.045), heat);
	flame = mix(flame, vec3(1.0, 0.9, 0.5), core);
	ALBEDO = flame;
	EMISSION = flame * mix(900.0, 4500.0, heat) * (1.0 + core);
	ALPHA = COLOR.a * edge * (0.3 + 0.7 * tongues) * breakup;
}
