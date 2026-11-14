shader_type spatial;

uniform sampler2D soil_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_nor_gl : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_nor_gl : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_arm : filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 ground_position;
varying float slope;

void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	slope = 1.0 - NORMAL.y;
	TANGENT = normalize(vec3(1.0, 0.0, 0.0) - NORMAL * NORMAL.x);
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

void fragment() {
	vec2 point = ground_position.xz;
	vec2 uv = vec2(point.x, -point.y) * 0.45;
	float mottling = sin(point.x * 0.27 + sin(point.y * 0.25)) * cos(point.y * 0.39);
	float grit = sin(point.x * 3.1 + point.y * 1.8) * cos(point.y * 2.7) * 0.09;
	float rock = smoothstep(0.10, 0.29, slope) * COLOR.b;
	float gravel = smoothstep(0.09, 0.87, max(COLOR.r * 1.23, rock) + grit);
	float wet = max(COLOR.g * 0.85, smoothstep(0.47, 0.91, mottling + grit) * COLOR.r * 0.78);
	float tire_ruts = 0.5 + 0.5 * sin((point.x + sin(point.y * 0.18)) * 4.1);
	wet = max(wet, smoothstep(0.59, 0.92, COLOR.r) * tire_ruts * 0.30);
	vec3 soil = texture(soil_diff, uv).rgb * mix(vec3(0.60, 0.83, 0.45), vec3(0.91, 1.05, 0.64), mottling * 0.5 + 0.5);
	vec3 stone = texture(gravel_diff, uv * 0.67).rgb * mix(vec3(1.71, 1.40, 1.09), vec3(0.93, 1.03, 1.11), rock);
	vec2 arm = mix(texture(soil_arm, uv).rg, texture(gravel_arm, uv * 0.67).rg, gravel);
	ALBEDO = mix(soil, stone, gravel) * mix(1.0, 0.54, wet);
	NORMAL_MAP = mix(texture(soil_nor_gl, uv).rgb, texture(gravel_nor_gl, uv * 0.67).rgb, gravel);
	NORMAL_MAP_DEPTH = mix(0.67, 0.38, wet);
	AO = arm.r;
	ROUGHNESS = mix(arm.g, 0.22, wet);
	SPECULAR = mix(0.36, 0.58, wet);
}
