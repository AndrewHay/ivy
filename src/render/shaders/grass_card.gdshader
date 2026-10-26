shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, alpha_to_coverage;

#include "res://src/render/shaders/foliage_wind.gdshaderinc"

uniform vec3 bottom_color : source_color = vec3(0.22, 0.38, 0.18);
uniform vec3 top_color : source_color = vec3(0.48, 0.62, 0.32);
uniform float alpha_scissor : hint_range(0.0, 1.0, 0.01) = 0.42;


void vertex() {
	float inst_hash = float(INSTANCE_ID) * 0.173;
	foliage_wind_displace(VERTEX, 1.0 - UV.y, inst_hash);
}


void fragment() {
	vec3 col = mix(bottom_color, top_color, 1.0 - UV.y);
	ALBEDO = col;
	float a = smoothstep(alpha_scissor - 0.08, alpha_scissor + 0.08, 1.0 - UV.y);
	ALPHA = a;
	ROUGHNESS = 0.85;
}
