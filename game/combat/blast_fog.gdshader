shader_type fog;

uniform float heat = 1.0;
uniform float thickness = 1.35;

float hash_cell(vec3 cell) {
	vec3 p = fract(cell * 0.3183099 + vec3(0.1, 0.27, 0.39)) * 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise_3d(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float lower = mix(mix(hash_cell(cell), hash_cell(cell + vec3(1, 0, 0)), f.x),
		mix(hash_cell(cell + vec3(0, 1, 0)), hash_cell(cell + vec3(1, 1, 0)), f.x), f.y);
	float upper = mix(mix(hash_cell(cell + vec3(0, 0, 1)), hash_cell(cell + vec3(1, 0, 1)), f.x),
		mix(hash_cell(cell + vec3(0, 1, 1)), hash_cell(cell + vec3(1, 1, 1)), f.x), f.y);
	return mix(lower, upper, f.z);
}

void fog() {
	vec3 p = (UVW - 0.5) * 2.0;
	vec3 drift = vec3(0.0, (1.35 - thickness) * -1.0, 0.0);
	float lobes = noise_3d(p * 3.4 + drift);
	float detail = noise_3d(p * 7.8 + drift * 2.0);
	float edge = length(p) + (0.5 - lobes) * 0.42 + (0.5 - detail) * 0.14;
	float falloff = 1.0 - smoothstep(0.28, 0.98, edge);
	float temperature = falloff * heat * mix(0.48, 1.35, lobes);
	DENSITY = falloff * mix(0.55, 1.45, lobes) * thickness;
	ALBEDO = mix(vec3(0.19, 0.16, 0.13), vec3(0.49, 0.26, 0.11), heat);
	vec3 flame = mix(vec3(1.0, 0.11, 0.012), vec3(7.0, 4.1, 1.45), smoothstep(0.12, 0.82, temperature));
	EMISSION = flame * temperature * smoothstep(0.02, 0.22, temperature);
}
