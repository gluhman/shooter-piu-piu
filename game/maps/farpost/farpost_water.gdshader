shader_type spatial;
render_mode cull_disabled;

varying vec2 ground_position;

void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = ground_position;
	float a = sin(dot(p, vec2(5.4, 2.9)) + TIME * 0.74);
	float b = sin(dot(p, vec2(-3.0, 6.5)) - TIME * 0.60 + a * 0.41);
	float silt = 0.5 + 0.5 * sin(p.x * 1.9 + cos(p.y * 2.1));
	ALBEDO = mix(vec3(0.026, 0.037, 0.032), vec3(0.057, 0.066, 0.049), silt);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(a * 0.075, 0.0, b * 0.06, 0.0)).xyz);
	ROUGHNESS = 0.17;
	SPECULAR = 0.67;
}
