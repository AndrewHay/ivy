shader_type spatial;
render_mode cull_disabled;

#include "res://src/render/shaders/wind_gust.gdshaderinc"

varying float v_h;
varying float v_hash;
varying vec3 v_world_pos;
varying vec2 v_uv;

const vec3 GROUND_MEAN = vec3(0.36, 0.52, 0.26);


float patch_hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}


float patch_noise_world(vec2 xz) {
	const float CELL = 2.5;
	vec2 p = xz / CELL;
	vec2 i0 = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = patch_hash21(i0);
	float b = patch_hash21(i0 + vec2(1.0, 0.0));
	float c = patch_hash21(i0 + vec2(0.0, 1.0));
	float d = patch_hash21(i0 + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


void vertex() {
	v_uv = UV;
	v_h = 1.0 - UV.y;
	v_hash = COLOR.r;
	vec2 root_world_xz = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz;
	float blade_H = (v_h > 1e-3) ? (VERTEX.y / v_h) : VERTEX.y;
	vec3 pos = ivy_wind_tip_displace_model(
			VERTEX, v_h, blade_H, MODEL_MATRIX, root_world_xz, COLOR.r);
	VERTEX = pos;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	float h = clamp(v_h, 0.0, 1.0);
	vec3 root_col = vec3(0.18, 0.30, 0.14);
	vec3 mid_col = vec3(0.36, 0.52, 0.26);
	vec3 tip_col = vec3(0.62, 0.72, 0.38);
	vec3 col = h < 0.5
			? mix(root_col, mid_col, h * 2.0)
			: mix(mid_col, tip_col, (h - 0.5) * 2.0);
	col *= 1.0 + (v_hash - 0.5) * 0.12;
	float patch_n = patch_noise_world(v_world_pos.xz);
	col = mix(col, col * vec3(0.92, 1.04, 0.88), (patch_n - 0.5) * 0.35);
	float ao = mix(0.55, 1.0, smoothstep(0.0, 0.4, h));
	col *= ao;
	float g = ivy_gust_at(v_world_pos.xz);
	vec3 sheen_col = col * vec3(1.06, 1.08, 0.96);
	col = mix(col, sheen_col, g * h * 0.12);
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = distance(v_world_pos, cam);
	col = mix(col, GROUND_MEAN, smoothstep(10.0, 18.0, dist));
	ALBEDO = col;
	ROUGHNESS = 0.88;
	vec3 up = normalize((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float bend = (v_uv.x - 0.5) * 0.3 * PI;
	NORMAL = normalize(mat3(MODEL_MATRIX) * (cos(bend) * NORMAL + sin(bend) * cross(up, NORMAL)));
	BACKLIGHT = vec3(0.25, 0.32, 0.12);
}
