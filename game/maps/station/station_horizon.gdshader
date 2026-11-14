shader_type spatial;
render_mode unshaded;

uniform sampler2D rock_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 p;
varying vec3 world_normal;

void vertex() {
	p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec3 regolith = texture(rock_diff, p.xz * 0.10).rgb;
	float light = 0.22 + max(0.0, dot(normalize(world_normal), normalize(vec3(-0.78, 0.32, 0.28)))) * 0.82;
	float stone = dot(regolith, vec3(0.21, 0.72, 0.07));
	ALBEDO = stone * vec3(0.14, 0.19, 0.28) * light;
}
