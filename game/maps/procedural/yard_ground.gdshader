shader_type spatial;

uniform sampler2D surface_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_orm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec2 slab_size = vec2(3.6, 4.8);
uniform float joint_strength = 0.6;

varying vec2 ground_position;

void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = ground_position * 0.38;
	vec3 detail = texture(surface_color, uv).rgb;
	vec3 orm = texture(surface_orm, uv).rgb;
	vec2 slab = ground_position / slab_size;
	vec2 fraction = fract(slab);
	vec2 joint = min(fraction, 1.0 - fraction) * slab_size;
	float distance_to_joint = min(joint.x, joint.y);
	float pixel = max(fwidth(distance_to_joint), 0.005);
	float seam = 1.0 - smoothstep(0.012 - pixel, 0.028 + pixel, distance_to_joint);
	float slab_tone = fract(sin(dot(floor(slab), vec2(92.17, 53.11))) * 9411.8);
	ALBEDO = detail * tint * mix(1.0, 0.85 + 0.16 * slab_tone - 0.35 * seam, joint_strength);
	NORMAL_MAP = texture(surface_normal, uv).rgb;
	NORMAL_MAP_DEPTH = 1.12;
	AO = orm.r;
	ROUGHNESS = mix(orm.g, 0.96, seam * joint_strength);
}
