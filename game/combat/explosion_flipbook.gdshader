// Adapted from Duarte David's Godot Explosion VFX and memo1918's Godot 4 port.
// License and source are in res://assets/explosion_vfx/LICENSE.txt.
shader_type spatial;
render_mode blend_mix, diffuse_lambert, specular_disabled, shadows_disabled;

const float ATLAS_COLUMNS = 8.0;
const float ATLAS_FRAMES = 64.0;

uniform sampler2D smoke_flipbook : filter_linear, repeat_disable;
uniform sampler2D normal_positive : filter_linear, repeat_disable;
uniform sampler2D normal_negative : filter_linear, repeat_disable;
uniform sampler2D flame_ramp : source_color, filter_linear, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 smoke_tint : source_color = vec3(0.66, 0.62, 0.57);

varying float age;

void vertex() {
	// Keep particle scale and position while aligning each quad to the camera.
	vec3 size = vec3(length(MODELVIEW_MATRIX[0].xyz),
		length(MODELVIEW_MATRIX[1].xyz), length(MODELVIEW_MATRIX[2].xyz));
	MODELVIEW_MATRIX[0] = vec4(size.x, 0.0, 0.0, 0.0);
	MODELVIEW_MATRIX[1] = vec4(0.0, size.y, 0.0, 0.0);
	MODELVIEW_MATRIX[2] = vec4(0.0, 0.0, size.z, 0.0);
	MODELVIEW_NORMAL_MATRIX = mat3(1.0);

	age = INSTANCE_CUSTOM.y;
	// Skip the tiny opening frames so the fireball appears with the blast light.
	float frame = clamp(floor(age * ATLAS_FRAMES) + 3.0, 0.0, ATLAS_FRAMES - 1.0);
	vec2 tile = vec2(mod(frame, ATLAS_COLUMNS), floor(frame / ATLAS_COLUMNS));
	vec2 inset = 0.5 * ATLAS_COLUMNS / vec2(textureSize(smoke_flipbook, 0));
	UV = (tile + mix(inset, 1.0 - inset, UV)) / ATLAS_COLUMNS;
}

void fragment() {
	vec4 smoke = texture(smoke_flipbook, UV);
	if (smoke.a < 0.004) {
		discard;
	}
	float density = max(max(smoke.r, smoke.g), smoke.b);
	float depth = texture(scene_depth, SCREEN_UV).r;
	vec2 ndc_xy = SCREEN_UV * 2.0 - 1.0;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		depth = depth * 2.0 - 1.0;
	#endif
	vec4 surface = INV_PROJECTION_MATRIX * vec4(ndc_xy, depth, 1.0);
	float separation = VERTEX.z - surface.z / surface.w;
	float soft_distance = mix(0.36, 0.16, density);
	float soft_edge = smoothstep(0.0, soft_distance, separation);

	float cooling = 0.48 * smoothstep(0.0, 0.23, age);
	vec3 flame = texture(flame_ramp, vec2(density + cooling, 0.5)).rgb;
	vec3 smoke_normal = texture(normal_positive, UV).rgb - texture(normal_negative, UV).rgb;
	NORMAL = normalize(smoke_normal + vec3(0.0, 0.0, 0.001));
	ALBEDO = smoke_tint * mix(0.35, 1.0, density);
	EMISSION = flame * 5.0 * (1.0 - smoothstep(0.12, 0.26, age));
	ALPHA = smoke.a * soft_edge * (1.0 - smoothstep(0.68, 1.0, age));
}
