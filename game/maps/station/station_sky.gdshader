shader_type sky;

uniform sampler2D night_panorama : source_color, filter_linear, repeat_enable;

float hash(vec3 cell) {
	return fract(sin(dot(cell, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float stars(vec3 ray, float density, float coverage) {
	vec3 grid = ray * density + vec3(0.213, 0.718, 0.452);
	vec3 cell = floor(grid);
	vec3 point = vec3(hash(cell + 17.0), hash(cell + 43.0), hash(cell + 91.0));
	float radius = mix(0.09, 0.22, hash(cell + 23.0));
	float visible = smoothstep(0.0, 0.018, hash(cell) - (1.0 - coverage));
	return visible * (1.0 - smoothstep(radius * 0.16, radius, length(fract(grid) - point)));
}

void sky() {
	vec3 ray = EYEDIR;
	vec3 panorama = texture(night_panorama, SKY_COORDS).rgb;
	float haze = max(0.0, 1.0 - abs(dot(ray, normalize(vec3(-0.33, 0.87, 0.28)))) * 3.1);
	float band = haze * haze * (0.64 + 0.36 * sin(dot(ray, vec3(13.3, 17.0, 6.45))));
	vec3 base = vec3(0.004, 0.009, 0.023) + vec3(0.009, 0.021, 0.051) * band;
	vec3 grade = min(panorama, vec3(0.085)) * vec3(0.30, 0.55, 0.95);
	vec3 points = stars(ray, 96.0, 0.22) * vec3(0.34, 0.51, 0.72)
		+ stars(ray, 180.0, 0.24) * vec3(0.16, 0.22, 0.34);
	COLOR = AT_CUBEMAP_PASS ? base + grade + points : (base + grade) * 9.0 + points * 26.0;
}
