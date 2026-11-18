shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D base_color : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D metal_roughness : filter_linear_mipmap_anisotropic;
uniform bool black_uniform = false;
uniform bool gloves = false;
uniform bool cuffs = false;
uniform float normal_strength = 1.0;

void fragment() {
	vec3 source = cuffs ? vec3(0.065, 0.075, 0.052) : texture(base_color, UV).rgb;
	float luminance = dot(source, vec3(0.2126, 0.7152, 0.0722));
	// Region mask excludes helmet and clothes; warm skin pixels exclude straps.
	float skin_hue = smoothstep(1.06, 1.18, source.r / max(source.g, 0.001));
	float skin = gloves ? 0.0 : COLOR.a * skin_hue;
	vec3 charcoal = vec3(0.007, 0.008, 0.010) + luminance * vec3(0.075, 0.082, 0.092);
	ALBEDO = black_uniform ? mix(charcoal, source, skin) : source;
	vec3 packed = texture(metal_roughness, UV).rgb;
	ROUGHNESS = cuffs ? 0.94 : max(packed.g, 0.62);
	METALLIC = cuffs ? 0.0 : min(packed.b, 0.12);
	NORMAL_MAP = cuffs ? vec3(0.5, 0.5 + 0.025 * sin(UV.y * 160.0), 1.0) : texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
}
