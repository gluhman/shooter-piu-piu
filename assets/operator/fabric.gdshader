shader_type spatial;
render_mode cull_disabled;
// UV-aligned garment folds plus independently tiled 4K weave, kept at true
// texture resolution rather than enlarging the original 2K macro albedo.
uniform sampler2D macro_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D weave_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D weave_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D weave_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 fabric_tint : source_color = vec4(1.0);
uniform float weave_repeat = 24.0;
void fragment() {
	vec2 detail_uv = UV * weave_repeat;
	float yarn = dot(texture(weave_color, detail_uv).rgb, vec3(0.2126, 0.7152, 0.0722));
	ALBEDO = texture(macro_color, UV).rgb * fabric_tint.rgb * mix(0.82, 1.12, yarn);
	vec3 folds = texture(macro_normal, UV).xyz * 2.0 - 1.0;
	vec3 weave = texture(weave_normal, detail_uv).xyz * 2.0 - 1.0;
	folds.xy *= 0.65;
	weave.xy *= 0.24;
	NORMAL_MAP = normalize(vec3(folds.xy + weave.xy, folds.z * weave.z)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = clamp(texture(macro_roughness, UV).r * 0.88 + texture(weave_arm, detail_uv).g * 0.12, 0.68, 1.0);
	AO = texture(macro_ao, UV).r;
	METALLIC = 0.0;
}
