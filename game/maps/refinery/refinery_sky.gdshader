shader_type sky;

uniform sampler2D hilltop : source_color, filter_linear, repeat_enable;

void sky() {
	vec3 hdr = texture(hilltop, SKY_COORDS).rgb;
	vec3 haze = vec3(0.37, 0.51, 0.62);
	float sky_weight = smoothstep(0.105, 0.25, EYEDIR.y);
	COLOR = AT_CUBEMAP_PASS ? hdr * 0.78 : mix(haze, hdr * 1.12, sky_weight);
}
