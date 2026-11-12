shader_type spatial;

uniform sampler2D asphalt_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D slab_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D slab_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D slab_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float layout_scale = 1.0;
varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 plan = world_xz / layout_scale;
	float concrete = smoothstep(7.8, 8.4, abs(plan.x)) * (1.0 - smoothstep(14.2, 14.8, abs(plan.y)));
	vec2 uv = world_xz * 0.42;
	vec3 color = mix(texture(asphalt_color, uv).rgb, texture(slab_color, uv).rgb, concrete);
	vec3 packed = mix(texture(asphalt_orm, uv).rgb, texture(slab_orm, uv).rgb, concrete);
	vec2 joint = abs(fract(world_xz / 2.4 + 0.5) - 0.5) * 2.4;
	float seam = (1.0 - smoothstep(0.009, 0.023, min(joint.x, joint.y))) * concrete;
	float lane = (1.0 - smoothstep(0.06, 0.1, abs(abs(plan.x) - 6.3))) * step(0.25, fract(plan.y / 5.0));
	float wear = smoothstep(0.13, 0.42, texture(asphalt_color, uv * 3.17).r);
	ALBEDO = mix(color * (1.0 - seam * 0.35), vec3(0.74, 0.49, 0.09), lane * (0.36 + 0.5 * wear));
	NORMAL_MAP = mix(texture(asphalt_normal, uv).rgb, texture(slab_normal, uv).rgb, concrete);
	NORMAL_MAP_DEPTH = 1.0;
	AO = packed.r;
	ROUGHNESS = packed.g;
}
