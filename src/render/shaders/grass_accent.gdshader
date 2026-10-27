shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, blend_mix;

#include "res://src/render/shaders/wind_gust.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float accent_height : hint_range(0.01, 4.0, 0.001) = 1.0;
uniform float alpha_scissor_threshold = 0.5;
uniform float alpha_edge_soft = 0.04;

varying float v_h;
varying float v_hash;
varying vec2 v_root_world_xz;

void vertex() {
	v_h = clamp(VERTEX.y / accent_height, 0.0, 1.0);
	v_hash = COLOR.r;
	v_root_world_xz = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz;
	float H = accent_height;
	VERTEX = ivy_wind_tip_displace_model(
			VERTEX, v_h, H, MODEL_MATRIX, v_root_world_xz, v_hash);
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	float edge = smoothstep(
			alpha_scissor_threshold - alpha_edge_soft,
			alpha_scissor_threshold + alpha_edge_soft,
			tex.a);
	if (edge < 0.01) {
		discard;
	}
	ALBEDO = tex.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
