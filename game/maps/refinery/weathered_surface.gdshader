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
uniform int roughness_channel = 0;
uniform bool moving_cover = false;
uniform mat4 mesh_to_cover;
uniform int hole_count = 0;
uniform vec4 hole_points[32];
uniform vec3 hole_axes[32];

uniform float weathering = 0.35;
uniform float rust_amount = 0.08;
uniform bool packed_arm = true;
uniform bool painted = true;
varying float bevel_wear;
varying vec3 world_position;
varying vec3 world_normal;
varying vec3 cover_position;

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x),f.y),f.z);
}
vec4 tri_sample(sampler2D tex, vec3 p, vec3 w) {
	return texture(tex,p.zy)*w.x+texture(tex,p.xz)*w.y+texture(tex,p.xy)*w.z;
}
vec4 projected(sampler2D tex, vec3 p, vec3 w) {
	// The same two-scale blend is applied to color, normal and ARM maps.
	float patch = smoothstep(0.2,0.8,noise3(world_position*0.17));
	return mix(tri_sample(tex,p,w),tri_sample(tex,p*0.73+vec3(11.7,4.9,8.1),w),patch);
}

void vertex() {
	bevel_wear = clamp(1.0 - COLOR.r,0.0,1.0);
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
	vec3 paint = projected(color_texture,p,w).rgb*tint.rgb;
	float macro = noise3(world_position*0.12);
	float grain = noise3(world_position*7.0);
	float streak = noise3(vec3(world_position.x*2.1,world_position.y*0.10,world_position.z*2.1));
	float dirt = weathering*(0.18+0.45*exp(-max(world_position.y,0.0)*0.65))*smoothstep(0.25,0.72,macro+grain*0.14);
	float rust = rust_amount*smoothstep(0.47,0.76,streak*0.65+macro*0.35);
	float worn = bevel_wear*smoothstep(0.23,0.69,grain)*0.78;
	paint *= mix(0.87,1.10,macro);
	paint = mix(paint,paint*vec3(0.40,0.35,0.28),dirt);
	paint = mix(paint,vec3(0.18,0.065,0.025)*(0.72+grain*0.5),rust);
	paint = mix(paint,vec3(0.30,0.33,0.34),worn*float(painted));
	vec3 edge_color = mix(vec3(0.55,0.30,0.13),vec3(0.52,0.56,0.59),metalness);
	ALBEDO=mix(paint,edge_color,rim*0.92)*(FRONT_FACING?1.0:0.24);
	ALBEDO=mix(ALBEDO,paint*0.37,dent*0.84);
	vec4 arm=projected(roughness_texture,p,w);
	METALLIC=clamp(metalness*(packed_arm?arm.b:1.0)*(1.0-rust*0.9),0.0,0.85);
	METALLIC=mix(METALLIC,0.65,worn*float(painted));
	ROUGHNESS=clamp(mix(arm.g*roughness_factor,0.94,dirt+rust*0.65),0.48,0.98);
	AO=mix(1.0,arm.r,0.7);
	AO_LIGHT_AFFECT=0.25;
	vec3 q=p*0.73+vec3(11.7,4.9,8.1);
	float patch=smoothstep(0.2,0.8,noise3(world_position*0.17));
	vec3 nx=mix(texture(normal_texture,p.zy).rgb,texture(normal_texture,q.zy).rgb,patch)*2.0-1.0;
	vec3 ny=mix(texture(normal_texture,p.xz).rgb,texture(normal_texture,q.xz).rgb,patch)*2.0-1.0;
	vec3 nz=mix(texture(normal_texture,p.xy).rgb,texture(normal_texture,q.xy).rgb,patch)*2.0-1.0;
	vec3 mapped=vec3(nx.z*sign(n.x),-nx.y,nx.x)*w.x+vec3(ny.x,ny.z*sign(n.y),ny.y)*w.y+vec3(nz.x,-nz.y,nz.z*sign(n.z))*w.z;
	vec3 flat_axis=sign(n)*w;
	vec3 normal_world=normalize(n+(mapped-flat_axis)*normal_strength);
	NORMAL=normalize(mat3(VIEW_MATRIX)*normal_world)*(FRONT_FACING?1.0:-1.0);
}
