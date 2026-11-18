shader_type spatial;
render_mode cull_disabled;

uniform sampler2D yarn_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D yarn_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D yarn_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 yarn_tint : source_color = vec4(0.5, 0.48, 0.42, 1.0);

void fragment() {
	// Preserve the 4K yarn variation while replacing the source's pink dye.
	vec3 source_yarn = texture(yarn_color, UV).rgb;
	float luminance = dot(source_yarn, vec3(0.2126, 0.7152, 0.0722));
	ALBEDO = yarn_tint.rgb * COLOR.rgb * mix(0.65, 1.2, luminance);
	vec3 arm = texture(yarn_arm, UV).rgb;
	AO = arm.r;
	ROUGHNESS = clamp(arm.g, 0.75, 1.0);
	METALLIC = 0.0;
	NORMAL_MAP = texture(yarn_normal, UV).rgb;
	NORMAL_MAP_DEPTH = 0.45;
}
