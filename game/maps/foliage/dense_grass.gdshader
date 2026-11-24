// Thin meadow blades with stable volume normals and terrain-scale colour patches.
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform vec3 root_color : source_color = vec3(0.12, 0.17, 0.055);
uniform vec3 tip_color : source_color = vec3(0.29, 0.35, 0.14);
uniform float wind_strength = 0.065;
uniform float fade_start = 65.0;
uniform float fade_end = 90.0;
varying vec3 planting_position;
varying vec3 volume_normal;
varying vec3 instance_tint;
varying float dry_blade;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float patch_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1, 0)), f.x),
		mix(hash(cell + vec2(0, 1)), hash(cell + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	// Colour belongs to the undeformed blade; wind/fade must never resample a hash.
	dry_blade = smoothstep(0.64, 0.94, hash(root.xz + VERTEX.xz * 17.0));
	float fade = 1.0 - smoothstep(fade_start, fade_end, distance(root, CAMERA_POSITION_WORLD));
	planting_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	volume_normal = normalize(MODEL_NORMAL_MATRIX * vec3(VERTEX.x * 0.22, 1.0, VERTEX.z * 0.22));
	// Sink the tips into their matching ground without shrinking each tuft's footprint.
	VERTEX.y *= fade;
	float bend = UV.y * UV.y;
	float travelling = patch_noise(root.xz * 0.11 + vec2(TIME * 0.10, TIME * 0.045));
	float gust = sin(TIME * 1.6 + root.x * 0.42 + root.z * 0.31) * mix(0.45, 1.0, travelling);
	VERTEX.x += gust * wind_strength * bend * fade;
	VERTEX.z += sin(TIME * 1.1 + root.z * 0.55) * wind_strength * 0.48 * bend * fade;
	instance_tint = COLOR.rgb;
}

void fragment() {
	float variation = patch_noise(planting_position.xz * 0.12);
	vec3 gradient = mix(root_color, tip_color, pow(UV.y, 0.75));
	gradient = mix(gradient, vec3(0.43, 0.37, 0.20), dry_blade * smoothstep(0.25, 1.0, UV.y) * 0.35);
	ALBEDO = gradient * mix(0.78, 1.18, variation) * instance_tint;
	// Volume lighting avoids a light/dark flip when viewing the other side of a fine blade.
	NORMAL = normalize(mat3(VIEW_MATRIX) * volume_normal);
	ROUGHNESS = 1.0;
	SPECULAR = 0.06;
	AO = mix(0.62, 1.0, smoothstep(0.0, 0.55, UV.y));
	AO_LIGHT_AFFECT = 0.10;
	BACKLIGHT = ALBEDO * 0.18;
}
