shader_type spatial;

uniform sampler2D steel_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D steel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D steel_rough : filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 p;
varying float horizontal;

void vertex() {
	p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	horizontal = abs(NORMAL.y);
	if (horizontal > 0.9) {
		TANGENT = vec3(1.0, 0.0, 0.0);
		BINORMAL = normalize(cross(NORMAL, TANGENT));
	}
}

void fragment() {
	vec2 uv = vec2(p.x, -p.z) * 0.72;
	vec2 grid = abs(fract(p.xz / 1.58) - 0.5);
	float seam = smoothstep(0.482, 0.496, max(grid.x, grid.y));
	float variation = fract(sin(dot(floor(p.xz / 1.58), vec2(87.5, 47.2))) * 41758.53);
	vec3 steel = texture(steel_diff, uv).rgb * mix(vec3(0.69, 0.78, 0.88), vec3(0.91, 0.98, 1.06), variation);
	ALBEDO = mix(steel * mix(1.0, 0.33, seam), vec3(0.067, 0.095, 0.123), 1.0 - horizontal);
	NORMAL_MAP = texture(steel_normal, uv).rgb;
	NORMAL_MAP_DEPTH = 0.66 * horizontal;
	ROUGHNESS = clamp(texture(steel_rough, uv).r * 0.69 + 0.21, 0.27, 0.91);
	METALLIC = 0.38;
}
