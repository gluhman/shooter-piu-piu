shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

uniform float density : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint : source_color = vec4(0.67, 0.70, 0.69, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}

void vertex() {
	// Face the camera while preserving the puff's animated size.
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), 1.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz * scale.x, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * scale.y, 0.0),
		INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float seed = fract(NODE_POSITION_WORLD.x * 0.81 + NODE_POSITION_WORLD.z * 0.77);
	vec2 flow = p * 3.8 + vec2(seed * 18.0, -TIME * 0.29);
	float billows = noise(flow) * 0.62 + noise(flow * 2.13 + TIME * 0.1) * 0.26 + noise(flow * 4.28) * 0.12;
	float edge = 1.0 - smoothstep(0.12, 0.91, length(p) + (billows - 0.5) * 0.30);
	ALBEDO = tint.rgb * mix(0.55, 1.20, billows);
	ALPHA = density * edge * mix(0.32, 0.81, billows);
}
