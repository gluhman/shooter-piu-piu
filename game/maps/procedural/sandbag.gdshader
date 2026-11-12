shader_type spatial;

void fragment() {
	vec2 thread = sin(UV * vec2(830.0, 410.0));
	float weave = thread.x * thread.y;
	float stain = sin(UV.x * 87.0 + UV.y * 43.0) * sin(UV.y * 31.0) * 0.065;
	float seam = smoothstep(0.028, 0.012, abs(UV.y - 0.5));
	ALBEDO = vec3(0.46, 0.38, 0.23) * (0.92 + weave * 0.085 + stain - seam * 0.23);
	NORMAL_MAP = vec3(0.5 + thread.x * 0.18, 0.5 + thread.y * 0.18, 1.0);
	NORMAL_MAP_DEPTH = 0.64;
	ROUGHNESS = 0.92;
}
