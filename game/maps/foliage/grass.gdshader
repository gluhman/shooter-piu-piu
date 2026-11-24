shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, specular_disabled;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_roughness : filter_linear_mipmap_anisotropic;
uniform float wind_strength = 0.055;
varying vec4 tuft_color;
varying vec3 volume_normal;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float tip = pow(clamp(VERTEX.y / 0.7, 0.0, 1.0), 1.6);
	float breeze = sin(TIME * 1.7 + world.x * 0.8 + world.z * 0.6);
	VERTEX.x += breeze * wind_strength * tip;
	VERTEX.z += sin(TIME * 1.15 + world.z * 1.1) * wind_strength * tip * 0.45;
	volume_normal = normalize(MODEL_NORMAL_MATRIX * vec3(VERTEX.x * 0.30, 1.0, VERTEX.z * 0.30));
	tuft_color = COLOR;
}

void fragment() {
	vec4 texel = texture(grass_albedo, UV);
	ALBEDO = texel.rgb * tuft_color.rgb;
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.42;
	NORMAL = normalize(mat3(VIEW_MATRIX) * volume_normal);
	ROUGHNESS = max(0.85, texture(grass_roughness, UV).r);
	BACKLIGHT = ALBEDO * 0.22;
}
