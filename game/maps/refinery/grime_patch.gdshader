shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
uniform vec4 stain : source_color = vec4(0.055,0.045,0.031,0.36);
void fragment() {
	vec2 p=UV*2.0-1.0;
	float noise=sin(p.x*31.0+sin(p.y*17.0))*sin(p.y*27.0-p.x*13.0);
	float edge=1.0-smoothstep(0.40,1.0,length(p)+noise*0.07);
	ALBEDO=stain.rgb;
	ROUGHNESS=0.85;
	SPECULAR=0.0;
	ALPHA=edge*stain.a*(0.68+0.32*noise);
}
