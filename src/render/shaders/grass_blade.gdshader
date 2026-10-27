shader_type spatial;
render_mode cull_disabled, specular_disabled;

#include "res://src/render/shaders/wind_gust.gdshaderinc"

varying float v_h;
varying float v_hash;
varying vec3 v_world_pos;
varying vec2 v_uv;

vec3 srgb_to_linear(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}

const vec3 GROUND_MEAN = pow(vec3(0.36, 0.52, 0.26), vec3(2.2));


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
	vec3 root_col = srgb_to_linear(vec3(0.18, 0.30, 0.14));
	vec3 mid_col = srgb_to_linear(vec3(0.36, 0.52, 0.26));
	vec3 tip_col = srgb_to_linear(vec3(0.62, 0.72, 0.38));
	vec3 col = h < 0.5
			? mix(root_col, mid_col, h * 2.0)
			: mix(mid_col, tip_col, (h - 0.5) * 2.0);
	col *= 1.0 + (v_hash - 0.5) * 0.07;
	float patch_n = patch_noise_world(v_world_pos.xz);
	col = mix(col, col * vec3(1.01, 1.02, 0.98), (patch_n - 0.5) * 0.12);
	float ao = mix(0.62, 1.0, smoothstep(0.0, 0.5, h));
	col *= ao;
	float g = ivy_gust_at(v_world_pos.xz);
	vec3 sheen_col = col * vec3(1.03, 1.04, 0.99);
	col = mix(col, sheen_col, min(g * h * 0.10, 0.05));
	col = min(col, vec3(0.78));
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = distance(v_world_pos, cam);
	col = mix(col, GROUND_MEAN, smoothstep(10.0, 18.0, dist));
	ALBEDO = col;
	ROUGHNESS = 0.94;
	vec3 up = normalize((MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 face_n = normalize(mat3(MODEL_MATRIX) * NORMAL);
	float bend = (v_uv.x - 0.5) * 0.3 * PI;
	vec3 bent_n = normalize(mat3(MODEL_MATRIX) * (cos(bend) * NORMAL + sin(bend) * cross(up, NORMAL)));
	NORMAL = normalize(mix(face_n, bent_n, 0.55));
	BACKLIGHT = vec3(0.07, 0.05, 0.015);
}
