shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled;

void fragment() {
	float radius = length(UV * 2.0 - 1.0);
	float core = 1.0 - smoothstep(0.55, 0.82, radius);
	float halo = 1.0 - smoothstep(0.15, 1.0, radius);
	ALBEDO = mix(vec3(1.0, 0.045, 0.022), vec3(1.0, 0.20, 0.13), core);
	ALPHA = max(core * 0.70, halo * 0.20);
}
