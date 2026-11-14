shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D panorama : filter_linear_mipmap, repeat_enable;
uniform float reflection_strength = 0.12;
uniform float surface_roughness = 0.45;

void fragment() {
	vec3 normal = normalize(NORMAL);
	vec3 reflected = normalize(mat3(INV_VIEW_MATRIX) * reflect(-normalize(VIEW), normal));
	vec2 uv = vec2(atan(reflected.x, -reflected.z) / TAU + 0.5,
		acos(clamp(reflected.y, -1.0, 1.0)) / PI);
	vec3 radiance = textureLod(panorama, uv, surface_roughness * 7.0).rgb;
	float fresnel = pow(1.0 - max(dot(normal, normalize(VIEW)), 0.0), 3.0);
	ALBEDO = radiance / (vec3(1.0) + radiance);
	ALPHA = reflection_strength * mix(0.13, 0.45, fresnel);
}
