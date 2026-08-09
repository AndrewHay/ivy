shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, alpha_to_coverage;

uniform sampler2D albedo_tex : source_color;
uniform float alpha_scissor_threshold = 0.5;

varying vec4 rect_uv;


void vertex() {
	rect_uv = INSTANCE_CUSTOM;
}


void fragment() {
	vec2 atlas_uv = rect_uv.xy + UV * rect_uv.zw;
	vec4 tex = texture(albedo_tex, atlas_uv);
	if (tex.a < alpha_scissor_threshold) {
		discard;
	}
	ALBEDO = tex.rgb * COLOR.rgb;
	ALPHA = tex.a;
}
