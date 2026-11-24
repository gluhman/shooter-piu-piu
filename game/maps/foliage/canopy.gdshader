shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform sampler2D needles : source_color, filter_linear_mipmap_anisotropic;
uniform vec3 tint : source_color = vec3(0.67,0.75,0.53);
varying vec3 canopy_normal;
void vertex() {
	// Light the crown as a soft volume, rather than exposing every crossed card.
	canopy_normal = normalize(MODEL_NORMAL_MATRIX * normalize(vec3(VERTEX.x,0.38,VERTEX.z)));
}
void fragment() {
	vec4 leaf = texture(needles,UV);
	ALBEDO = leaf.rgb * tint;
	ALPHA = leaf.a;
	ALPHA_SCISSOR_THRESHOLD = 0.34;
	NORMAL = normalize(mat3(VIEW_MATRIX) * canopy_normal);
	ROUGHNESS = 1.0;
	BACKLIGHT = ALBEDO * 0.10;
}
