shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, alpha_to_coverage;

uniform sampler2D albedo_tex : source_color;
uniform float alpha_scissor_threshold = 0.5;
uniform vec3 weathered_tint = vec3(0.82, 0.98, 0.86);
uniform vec3 backlight = vec3(0.30, 0.45, 0.18);

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
	vec3 albedo = tex.rgb * COLOR.rgb;
	// Weathered atlas rects (b,d,f) sit in the right half of the atlas (rect_uv.x > 0.5).
	if (rect_uv.x > 0.5) {
		albedo *= weathered_tint;
	}
	ALBEDO = albedo;
	ALPHA = tex.a;
	BACKLIGHT = backlight * tex.a;
}
