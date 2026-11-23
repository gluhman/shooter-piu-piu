// Original implementation of the tutorial's flipbook/flow/temperature approach.
// CC0 input assets and technique references: assets/explosion_vfx/aerial/CREDITS.md.
shader_type spatial;
render_mode blend_mix, diffuse_lambert, specular_disabled, shadows_disabled, cull_disabled;
uniform sampler2D explosion_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D flow_texture : filter_linear, repeat_disable;
uniform sampler2D mask_texture : filter_linear, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform float age : hint_range(0.0, 1.0) = 0.0;
uniform float opacity = 1.0;
uniform float flame_fade = 1.0;
uniform float emission_strength = 90000.0;
uniform float flow_strength = 0.015;
uniform float soft_distance = 0.42;
varying float frame_number;

vec2 tile_uv(vec2 local, float frame) {
	vec2 inset = vec2(1.0) / vec2(textureSize(explosion_texture, 0));
	vec2 tile = vec2(mod(frame, 5.0), floor(frame / 5.0));
	return (tile + clamp(local, inset * 5.0, vec2(1.0) - inset * 5.0)) / 5.0;
}
vec4 flow_sample(sampler2D tex, vec2 local) {
	float current = floor(frame_number);
	float next = min(current + 1.0, 24.0);
	float blend = fract(frame_number);
	vec2 uv_a = tile_uv(local, current);
	vec2 uv_b = tile_uv(local, next);
	vec2 flow = texture(flow_texture, uv_a).rg * 2.0 - 1.0;
	vec2 a = clamp(local - flow * blend * flow_strength * 5.0, vec2(0.001), vec2(0.999));
	vec2 b = clamp(local + flow * (1.0 - blend) * flow_strength * 5.0, vec2(0.001), vec2(0.999));
	return mix(texture(tex, tile_uv(a, current)), texture(tex, tile_uv(b, next)), blend);
}
// Smooth red-to-white thermal ramp at plausible incandescent temperatures.
vec3 thermal_color(float heat) {
	float kelvin = mix(1100.0, 6500.0, pow(clamp(heat, 0.0, 1.0), 0.7));
	float t = kelvin / 100.0;
	float green = clamp(0.39008 * log(t) - 0.63184, 0.0, 1.0);
	float blue = t <= 19.0 ? 0.0 : clamp(0.54321 * log(t - 10.0) - 1.19625, 0.0, 1.0);
	return pow(vec3(1.0, green, blue), vec3(2.2));
}
void vertex() {
	vec3 size = vec3(length(MODELVIEW_MATRIX[0].xyz), length(MODELVIEW_MATRIX[1].xyz), length(MODELVIEW_MATRIX[2].xyz));
	MODELVIEW_MATRIX[0] = vec4(size.x, 0.0, 0.0, 0.0);
	MODELVIEW_MATRIX[1] = vec4(0.0, size.y, 0.0, 0.0);
	MODELVIEW_MATRIX[2] = vec4(0.0, 0.0, size.z, 0.0);
	MODELVIEW_NORMAL_MATRIX = mat3(1.0);
	// Rapid initial expansion followed by a slower smoke roll; never wraps.
	float progress = age < 0.2 ? age * 1.6 : 0.32 + (age - 0.2) * 0.85;
	frame_number = clamp(progress * 24.0, 0.0, 24.0);
}
void fragment() {
	vec4 color = flow_sample(explosion_texture, UV);
	vec4 masks = flow_sample(mask_texture, UV);
	if (color.a < 0.003) { discard; }
	vec2 pixel = 5.0 / vec2(textureSize(mask_texture, 0));
	float dx = flow_sample(mask_texture, UV + vec2(pixel.x, 0.0)).g - masks.g;
	float dy = flow_sample(mask_texture, UV + vec2(0.0, pixel.y)).g - masks.g;
	NORMAL = normalize(vec3(-dx * 7.0, dy * 7.0, 1.0));
	float raw_depth = texture(scene_depth, SCREEN_UV).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		raw_depth = raw_depth * 2.0 - 1.0;
	#endif
	vec4 surface = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	float separation = VERTEX.z - surface.z / surface.w;
	float soft_edge = smoothstep(0.0, soft_distance, separation);
	float heat = pow(masks.r, 1.6) * (1.0 - smoothstep(0.28, 0.65, age)) * flame_fade;
	float smoke = mix(0.07, 0.34, masks.b);
	ALBEDO = vec3(smoke) * vec3(1.0, 0.95, 0.88) * (1.0 - heat);
	EMISSION = thermal_color(heat) * heat * emission_strength;
	BACKLIGHT = vec3(0.12) * (1.0 - masks.g) * color.a;
	ROUGHNESS = 1.0;
	ALPHA = color.a * soft_edge * opacity;
}
