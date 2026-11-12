shader_type spatial;

uniform sampler2D detail_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 dirt : source_color = vec3(0.37, 0.29, 0.21);
uniform vec3 moss : source_color = vec3(0.32, 0.39, 0.24);
varying vec2 ground_position;

float lattice(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

float patches(vec2 point) {
	vec2 cell = floor(point);
	vec2 blend = fract(point);
	blend = blend * blend * (3.0 - 2.0 * blend);
	return mix(
		mix(lattice(cell), lattice(cell + vec2(1.0, 0.0)), blend.x),
		mix(lattice(cell + vec2(0.0, 1.0)), lattice(cell + vec2(1.0, 1.0)), blend.x),
		blend.y
	);
}

void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 detail_uv = ground_position * 0.56;
	float coverage = patches(ground_position * 0.16) * 0.7 + patches(ground_position * 0.56) * 0.3;
	vec3 detail = texture(detail_color, detail_uv).rgb;
	ALBEDO = mix(dirt, moss, smoothstep(0.25, 0.73, coverage)) * (0.67 + detail * 0.72);
	NORMAL_MAP = texture(detail_normal, detail_uv).rgb;
	NORMAL_MAP_DEPTH = 0.52;
	ROUGHNESS = 0.94;
}
