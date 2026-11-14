shader_type spatial;

uniform sampler2D floor_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D floor_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D floor_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D trail_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D trail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D trail_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 ground_position;
varying float upness;

void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	upness = NORMAL.y;
	TANGENT = normalize(vec3(1.0, 0.0, 0.0) - NORMAL * NORMAL.x);
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

void fragment() {
	vec2 p = ground_position.xz;
	vec2 uv = vec2(p.x, -p.y) * 0.39;
	float breakup = sin(p.x * 1.6 + p.y * 2.1) * cos(p.y * 1.7 - p.x * 0.3) * 0.065;
	float patch = 0.5 + 0.27 * sin(p.x * 0.25 + sin(p.y * 0.31)) + 0.19 * sin(p.y * 0.22);
	float footpath = smoothstep(0.07, 0.91, COLOR.r + breakup);
	float stone = smoothstep(0.08, 0.35, 1.0 - upness) * smoothstep(3.5, 8.0, ground_position.y);
	float exposed = max(footpath, max(stone * 0.82, COLOR.g * 0.55));
	vec3 forest = texture(floor_color, uv).rgb * mix(vec3(0.74, 1.18, 0.52), vec3(0.48, 0.93, 0.32), patch);
	vec3 gravel = texture(trail_color, uv * 0.81).rgb * mix(vec3(1.13, 1.07, 0.91), vec3(0.9, 0.93, 0.88), stone);
	ALBEDO = mix(forest, gravel, exposed) * mix(1.0, 0.60, COLOR.g);
	NORMAL_MAP = mix(texture(floor_normal, uv).rgb, texture(trail_normal, uv * 0.81).rgb, exposed);
	NORMAL_MAP_DEPTH = 0.60;
	vec2 arm = mix(texture(floor_arm, uv).rg, texture(trail_arm, uv * 0.81).rg, exposed);
	AO = arm.r;
	ROUGHNESS = arm.g;
}
