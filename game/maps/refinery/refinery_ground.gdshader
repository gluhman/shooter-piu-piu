shader_type spatial;

uniform sampler2D soil : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec2 world_xz;
varying float upness;

void vertex() {
	world_xz = VERTEX.xz;
	upness = NORMAL.y;
	TANGENT = normalize(vec3(1.0, 0.0, 0.0) - NORMAL * NORMAL.x);
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

void fragment() {
	vec2 p = vec2(world_xz.x, -world_xz.y);
	float wear = sin(p.x * 1.13 + p.y * 1.39) * cos(p.y * 0.84 - p.x) * 0.10;
	float mottling = sin(p.x * 0.69 + sin(p.y * 0.24)) * 0.18 + 0.5;
	float yard = smoothstep(0.08, 0.9, COLOR.r + wear);
	float stone = smoothstep(0.13, 0.41, 1.0 - upness) * 0.88;
	vec3 meadow = texture(soil, p * 0.47).rgb * mix(vec3(0.43, 0.81, 0.25), vec3(0.73, 1.18, 0.39), mottling);
	vec3 scree = texture(gravel, p * 0.30).rgb * vec3(1.10, 1.02, 0.79);
	vec3 apron = texture(concrete, p * 0.19).rgb * vec3(0.91, 0.90, 0.80);
	ALBEDO = mix(mix(meadow, scree, max(stone, COLOR.g * 0.65)), apron, yard);
	NORMAL_MAP = mix(texture(gravel_normal, p * 0.30).rgb, texture(concrete_normal, p * 0.19).rgb, yard);
	NORMAL_MAP_DEPTH = 0.58;
	vec2 arm = texture(concrete_arm, p * 0.19).rg;
	AO = mix(1.0, arm.r, yard);
	ROUGHNESS = mix(0.96, arm.g, yard);
}
