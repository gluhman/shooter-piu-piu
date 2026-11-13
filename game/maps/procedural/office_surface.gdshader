shader_type spatial;

// Wall paint, acoustic ceiling panels, ceramic tiles and carpet squares.
uniform int finish : hint_enum("Paint","Acoustic tile","Ceramic","Carpet") = 0;
uniform sampler2D detail_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.8);
uniform float detail_scale = 1.0;
uniform float bump_strength = 0.25;

varying vec3 world_position;
varying vec3 world_normal;

float hash_cell(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float grain(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = smoothstep(vec2(0.0), vec2(1.0), fract(p));
	return mix(mix(hash_cell(cell), hash_cell(cell + vec2(1, 0)), f.x),
		mix(hash_cell(cell + vec2(0, 1)), hash_cell(cell + vec2(1)), f.x), f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 plane = world_position.xz;
	vec3 axis_u = vec3(1, 0, 0);
	vec3 axis_v = vec3(0, 0, 1);
	if (n.x > max(n.y, n.z)) {
		plane = world_position.zy;
		axis_u = vec3(0, 0, 1);
		axis_v = vec3(0, 1, 0);
	} else if (n.z > n.y) {
		plane = world_position.xy;
		axis_v = vec3(0, 1, 0);
	}

	vec2 uv = plane * detail_scale;
	float tile_size = finish == 2 ? 0.60 : (finish == 3 ? 0.50 : 1.0);
	vec2 tile_uv = plane / tile_size;
	vec2 cell = floor(tile_uv);
	vec2 border = min(fract(tile_uv), 1.0 - fract(tile_uv));
	float edge = min(border.x, border.y);
	float pixel = max(fwidth(edge), 0.001);
	float joint = 1.0 - smoothstep(0.009 - pixel, 0.020 + pixel, edge);
	float tile_tone = hash_cell(cell);
	bool rotate_weave = finish == 3 && mod(cell.x + cell.y, 2.0) == 0.0;
	vec2 texture_uv = rotate_weave ? uv.yx : uv;
	vec2 uv_dx = dFdx(uv);
	vec2 uv_dy = dFdy(uv);
	vec2 texture_dx = rotate_weave ? uv_dx.yx : uv_dx;
	vec2 texture_dy = rotate_weave ? uv_dy.yx : uv_dy;

	vec3 photo = textureGrad(detail_color, texture_uv, texture_dx, texture_dy).rgb;
	float rough = textureGrad(detail_roughness, texture_uv, texture_dx, texture_dy).r;
	vec2 bump = textureGrad(detail_normal, texture_uv, texture_dx, texture_dy).rg * 2.0 - 1.0;
	if (rotate_weave) {
		bump = bump.yx;
	}
	vec3 color = tint;
	if (finish == 0) {
		float patches = grain(plane * 2.4);
		float scuffs = (1.0 - smoothstep(0.12, 1.15, world_position.y)) * grain(plane * vec2(9.0, 30.0));
		color *= mix(vec3(0.76), vec3(1.16), photo) * (0.88 + 0.21 * patches - 0.13 * scuffs);
		rough = 0.72 + 0.24 * rough;
	} else if (finish == 1) {
		float pores = smoothstep(0.60, 0.89, grain(plane * 145.0));
		float pore_detail = 1.0 - smoothstep(0.32, 0.80, length(fwidth(plane)) * 145.0);
		color *= (0.91 + 0.13 * tile_tone) * (1.0 - 0.28 * pores * pore_detail);
		rough = 0.91;
	} else if (finish == 2) {
		color *= mix(vec3(0.62), vec3(1.13), photo) * (0.88 + tile_tone * 0.21);
		color = mix(color, tint * 0.29, joint * 0.86);
		rough = mix(0.29 + rough * 0.26, 0.94, joint);
	} else {
		color *= photo * (0.85 + tile_tone * 0.27);
		color *= 1.0 - joint * 0.30;
		rough = 0.83 + rough * 0.15;
	}
	vec3 gradient = (VIEW_MATRIX * vec4(axis_u * bump.x - axis_v * bump.y, 0.0)).xyz;
	NORMAL = normalize(NORMAL + gradient * bump_strength);
	ALBEDO = color;
	ROUGHNESS = rough;
}
