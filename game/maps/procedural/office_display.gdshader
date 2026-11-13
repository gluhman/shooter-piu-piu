shader_type spatial;

uniform vec3 background : source_color = vec3(0.055, 0.10, 0.13);
uniform vec3 accent : source_color = vec3(0.26, 0.51, 0.56);

void fragment() {
	vec2 p = UV;
	float inset = step(0.045, p.x) * step(p.x, 0.955) * step(0.06, p.y) * step(p.y, 0.94);
	float header = step(p.y, 0.17);
	float sidebar = step(p.x, 0.29);
	float text_row = step(0.72, fract(p.y * 17.0));
	float row = floor(p.y * 17.0);
	float column = floor(p.x * 31.0);
	float bars = step(0.30, fract(sin(row * 129.3 + column * 41.7) * 43758.54));
	float fine_detail = 1.0 - smoothstep(0.025, 0.055, fwidth(p.x));
	float content = text_row * bars * step(0.10, p.x) * step(p.x, 0.86) * fine_detail;
	vec3 color = background * (1.0 + sidebar * 0.39);
	color = mix(color, accent * 0.63, header * 0.72 + content * (1.0 - header) * 0.32);
	color = mix(background * 0.34, color, inset);
	ALBEDO = color;
	EMISSION = color * 270.0;
	ROUGHNESS = 0.22;
}
