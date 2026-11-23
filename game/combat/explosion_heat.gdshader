shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform float age = 0.0;
void vertex() {
	float size = length(MODELVIEW_MATRIX[0].xyz);
	MODELVIEW_MATRIX[0] = vec4(size, 0.0, 0.0, 0.0);
	MODELVIEW_MATRIX[1] = vec4(0.0, size, 0.0, 0.0);
	MODELVIEW_MATRIX[2] = vec4(0.0, 0.0, size, 0.0);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float ring = exp(-pow((radius - age * 3.2) * 14.0, 2.0));
	float fade = (1.0 - smoothstep(0.12, 0.32, age)) * smoothstep(0.0, 0.02, age);
	float raw_depth = texture(scene_depth, SCREEN_UV).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		raw_depth = raw_depth * 2.0 - 1.0;
	#endif
	vec4 surface = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	float edge = smoothstep(0.0, 0.4, VERTEX.z - surface.z / surface.w);
	vec2 offset = p * ring * fade * 0.012;
	ALBEDO = textureLod(screen_texture, clamp(SCREEN_UV + offset, vec2(0.001), vec2(0.999)), 0.0).rgb;
	ALPHA = ring * fade * edge * 0.60;
}
