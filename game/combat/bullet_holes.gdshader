shader_type spatial;
render_mode cull_disabled;

uniform sampler2D color_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metallic_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 texture_scale = vec3(1.0);
uniform float blend_sharpness = 1.4;
uniform float metalness = 0.0;
uniform float normal_strength = 1.0;
uniform bool use_mesh_uv = false;
uniform float roughness_factor = 1.0;
uniform bool moving_cover = false;
uniform mat4 mesh_to_cover;
uniform int hole_count = 0;
uniform vec4 hole_points[32];
uniform vec3 hole_axes[32];

varying vec3 world_position;
varying vec3 world_normal;
varying vec3 cover_position;

vec4 projected(sampler2D tex, vec3 p, vec3 w) {
	return texture(tex, p.zy) * w.x + texture(tex, p.xz) * w.y + texture(tex, p.xy) * w.z;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	cover_position = moving_cover ? (mesh_to_cover * vec4(VERTEX, 1.0)).xyz : world_position;
}

void fragment() {
	float rim = 0.0;
	float dent = 0.0;
	for (int i = 0; i < hole_count; i++) {
		vec3 axis = hole_axes[i];
		vec3 offset = cover_position - hole_points[i].xyz;
		float depth = dot(offset, axis);
		vec3 radial = offset - axis * depth;
		float radius = hole_points[i].w;
		float distance_sq = dot(radial, radial);
		if (radius < 0.0) {
			// Entry marks on the struck face only. The rendered pane is inside the collision box.
			float spot = 1.0 - smoothstep(-radius * 0.25, -radius, sqrt(distance_sq));
			if (depth > -0.045 && depth < 0.018) {
				dent = max(dent, spot);
			}
			continue;
		}
		if (distance_sq < radius * radius * 2.25) {
			vec3 tangent = normalize(cross(axis, abs(axis.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
			float angle = atan(dot(radial, cross(axis, tangent)), dot(radial, tangent) + 0.000001);
			float edge = radius * (1.0 + 0.12 * sin(angle * 7.0) + 0.09 * cos(angle * 11.0));
			float distance = sqrt(distance_sq);
			if (distance < edge) {
				discard;
			}
			rim = max(rim, 1.0 - smoothstep(edge + radius * 0.16, edge + radius * 0.53, distance));
		}
	}

	vec3 n = normalize(world_normal);
	vec3 p = world_position * texture_scale * vec3(1.0, -1.0, 1.0);
	vec3 w = pow(abs(n), vec3(blend_sharpness));
	w /= w.x + w.y + w.z;
	vec3 paint = (use_mesh_uv ? texture(color_texture, UV).rgb : projected(color_texture, p, w).rgb) * tint.rgb;
	vec3 edge_color = mix(vec3(0.55, 0.30, 0.13), vec3(0.52, 0.56, 0.59), metalness);
	ALBEDO = mix(paint, edge_color, rim * 0.92) * (FRONT_FACING ? 1.0 : 0.24);
	ALBEDO = mix(ALBEDO, paint * 0.37, dent * 0.84);
	METALLIC = metalness * projected(metallic_texture, p, w).r;
	ROUGHNESS = mix((use_mesh_uv ? texture(roughness_texture, UV).r : projected(roughness_texture, p, w).r) * roughness_factor, 0.8, rim);
	AO = projected(ao_texture, p, w).r;
	NORMAL_MAP = use_mesh_uv ? texture(normal_texture, UV * texture_scale.xy).rgb : projected(normal_texture, p, w).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
