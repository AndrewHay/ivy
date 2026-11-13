shader_type spatial;
render_mode fog_disabled, cull_disabled, depth_draw_opaque;

uniform vec3 u_horizon_rgb = vec3(0.78, 0.85, 0.91);

void fragment() {
	vec3 col = COLOR.rgb;
	float hor_lum = dot(u_horizon_rgb, vec3(0.299, 0.587, 0.114));
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	if (lum > hor_lum * 0.82) {
		col *= (hor_lum * 0.78) / max(lum, 1e-4);
	}
	ALBEDO = col;
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
}
