shader_type spatial;
render_mode cull_disabled, depth_draw_always;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float water_time = 0.0;
uniform float wave_amplitude = 0.018;
uniform vec4 ripple_events[8]; // World X/Z, start time, strength.
varying vec3 world_position;
varying float bed_depth;

float surface_height(vec2 p) {
	float t = water_time;
	float height = sin(p.x * 2.7 + p.y * 4.1 - t * 1.7) * 0.006;
	height += sin(p.x * -5.4 + p.y * 6.3 - t * 2.2) * 0.004;
	height += sin(p.x * 10.0 + p.y * 12.0 + t * 3.1) * 0.002;
	for (int i = 0; i < 8; i++) {
		float age = t - ripple_events[i].z;
		if (ripple_events[i].w > 0.0 && age >= 0.0 && age < 2.5) {
			float distance_to_step = distance(p, ripple_events[i].xy);
			float ring = distance_to_step - age * 0.9;
			height += sin(ring * 18.0) * exp(-ring * ring * 14.0 - age * 0.8)
				* ripple_events[i].w * smoothstep(0.0, 0.10, age) * (1.0 - smoothstep(2.0, 2.5, age));
		}
	}
	return clamp(height, -wave_amplitude, wave_amplitude);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	bed_depth = COLOR.r;
	// Keep the clipped shoreline and dry crossings fixed.
	float shore = smoothstep(0.0, 0.12, bed_depth);
	float swell = surface_height(world_position.xz) * shore;
	VERTEX.y += swell;
	world_position.y += swell;
}

void fragment() {
	vec2 p = world_position.xz;
	float shore = smoothstep(0.0, 0.12, bed_depth);
	float h = surface_height(p);
	vec2 slope = vec2(surface_height(p + vec2(0.04, 0.0)) - h,
		surface_height(p + vec2(0.0, 0.04)) - h) / 0.04;
	vec3 normal = normalize(vec3(-slope.x * shore, 1.0, -slope.y * shore));
	NORMAL = normalize((VIEW_MATRIX * vec4(normal, 0.0)).xyz);
	vec2 refract_uv = clamp(SCREEN_UV + NORMAL.xy * 0.006 * shore, vec2(0.001), vec2(0.999));
	float depth_raw = textureLod(depth_texture, refract_uv, 0.0).r;
	vec4 view_sample = INV_PROJECTION_MATRIX * vec4(refract_uv * 2.0 - 1.0, depth_raw, 1.0);
	view_sample /= view_sample.w;
	vec3 behind = (INV_VIEW_MATRIX * view_sample).xyz;
	if (behind.y > world_position.y + 0.01) { refract_uv = SCREEN_UV; }
	vec3 background = textureLod(screen_texture, refract_uv, 0.0).rgb;
	float depth_mix = clamp(bed_depth / 0.30, 0.0, 1.0);
	vec3 water_color = mix(vec3(0.055, 0.14, 0.105), vec3(0.018, 0.07, 0.055), depth_mix);
	float absorption = mix(0.22, 0.65, depth_mix);
	float shore_foam = (1.0 - smoothstep(0.015, 0.07, bed_depth)) * smoothstep(0.0, 0.012, bed_depth);
	float bubbles = smoothstep(0.65, 0.95, sin(p.x * 13.0 + water_time) * sin(p.y * 11.0 - water_time * 0.8));
	float foam = shore_foam * bubbles * 0.30;
	ALBEDO = mix(water_color * absorption, vec3(0.42, 0.48, 0.40), foam);
	EMISSION = background * (1.0 - absorption) * (1.0 - foam);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ROUGHNESS = mix(0.19, 0.09, fresnel) + foam * 0.35;
	SPECULAR = 0.80;
	ALPHA = smoothstep(0.0, 0.012, bed_depth);
}
