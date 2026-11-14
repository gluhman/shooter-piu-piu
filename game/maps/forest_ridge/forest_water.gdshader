shader_type spatial;
render_mode cull_disabled;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = world_xz;
	float drift = sin(p.x * 8.0 + p.y * 5.0 + TIME * 2.0);
	float ripple = sin(p.y * 10.0 - p.x * 2.0 + drift + TIME * 1.3);
	ALBEDO = mix(vec3(0.025, 0.074, 0.050), vec3(0.063, 0.113, 0.070), ripple * 0.5 + 0.5);
	NORMAL += vec3(drift * 0.030, ripple * 0.038, 0.0);
	ROUGHNESS = 0.32;
	SPECULAR = 0.62;
}
