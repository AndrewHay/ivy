shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform vec2 pg_wind_dir;
uniform float pg_wind_strength;
uniform vec2 pg_wind_scroll;
uniform float pg_wind_flutter_phase;
uniform float pg_gust_tile_m;
uniform float pg_sim_time;
uniform int pg_variant;

uniform float pg_gust_edge_lo;
uniform float pg_gust_edge_hi;
uniform float pg_lean_base;
uniform float pg_lean_gust_gain;
uniform float pg_flutter_amp;
uniform float pg_flutter_gust_base;
uniform float pg_flutter_space_freq;
uniform float pg_height_exp;
uniform bool pg_droop_on;

uniform float pg_wave_length_m;
uniform float pg_wave_speed_m_s;
uniform float pg_wave_sharpness;

uniform float pg_spring_freq_hz;
uniform float pg_spring_damping;
uniform float pg_overshoot_gain;
uniform float pg_phase_spread;

uniform float pg_front_width_m;
uniform float pg_front_speed_m_s;
uniform float pg_front_spacing_m;
uniform float pg_front_peak;

uniform float pg_flutter_period_sec = 1.7;

uniform sampler2D pg_gust_noise : filter_linear_mipmap, repeat_enable;

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

float pg_gust_at(vec2 world_xz) {
	vec2 uv = (world_xz - pg_wind_scroll) / pg_gust_tile_m;
	float n = textureLod(pg_gust_noise, uv, 0.0).r;
	return smoothstep(pg_gust_edge_lo, pg_gust_edge_hi, n);
}

float pg_wave_g(vec2 root_world_xz, vec2 dir_xz) {
	float phase_w = dot(root_world_xz, dir_xz) * (TAU / pg_wave_length_m)
			- pg_sim_time * (TAU * pg_wave_speed_m_s / pg_wave_length_m);
	return pow(0.5 + 0.5 * sin(phase_w), pg_wave_sharpness);
}

float pg_front_g(vec2 root_world_xz, vec2 dir_xz) {
	float s = dot(root_world_xz, dir_xz);
	float f = mod(pg_sim_time * pg_front_speed_m_s, pg_front_spacing_m);
	float d1 = mod(s - f, pg_front_spacing_m);
	float d = min(d1, pg_front_spacing_m - d1);
	return pg_front_peak * exp(-d * d / (2.0 * pg_front_width_m * pg_front_width_m));
}

vec3 pg_apply_droop(vec3 vertex_model, vec3 offset_model, float h, float H) {
	if (!pg_droop_on) {
		return vertex_model + offset_model;
	}
	float droop = (dot(offset_model, offset_model) / (2.0 * H)) * h;
	return vertex_model + offset_model - vec3(0.0, droop, 0.0);
}

vec3 pg_displace_v0(vec3 vertex_model, float h, float H, mat4 model_matrix, vec2 root_world_xz, float blade_hash_01, float g) {
	if (pg_wind_strength < 0.001) {
		return vertex_model;
	}
	h = clamp(h, 0.0, 1.0);
	vec2 dir_xz = normalize(pg_wind_dir);
	vec3 dir_world = normalize(vec3(dir_xz.x, 0.0, dir_xz.y));
	mat3 inv_model = inverse(mat3(model_matrix));
	vec3 dir_model = normalize(inv_model * dir_world);
	float h_pow = pow(h, pg_height_exp);
	float lean = pg_wind_strength * H * (pg_lean_base + pg_lean_gust_gain * g) * h_pow;
	vec3 offset_model = dir_model * lean;
	float flutter = pg_wind_strength * H * pg_flutter_amp * (pg_flutter_gust_base + g)
			* sin(pg_wind_flutter_phase + blade_hash_01 * TAU + dot(root_world_xz, dir_xz) * pg_flutter_space_freq)
			* h_pow;
	offset_model += dir_model * flutter;
	return pg_apply_droop(vertex_model, offset_model, h, H);
}

vec3 pg_displace_v2(vec3 vertex_model, float h, float H, mat4 model_matrix, vec2 root_world_xz, float g) {
	if (pg_wind_strength < 0.001) {
		return vertex_model;
	}
	h = clamp(h, 0.0, 1.0);
	vec2 dir_xz = normalize(pg_wind_dir);
	vec3 dir_world = normalize(vec3(dir_xz.x, 0.0, dir_xz.y));
	mat3 inv_model = inverse(mat3(model_matrix));
	vec3 dir_model = normalize(inv_model * dir_world);
	float h_pow = pow(h, pg_height_exp);
	float lean = pg_wind_strength * H * (pg_lean_base + pg_lean_gust_gain * g) * h_pow;
	vec3 offset_model = dir_model * lean;
	return pg_apply_droop(vertex_model, offset_model, h, H);
}

vec3 pg_displace_v3(vec3 vertex_model, float h, float H, mat4 model_matrix, vec2 root_world_xz, float blade_hash_01, float g) {
	if (pg_wind_strength < 0.001) {
		return vertex_model;
	}
	h = clamp(h, 0.0, 1.0);
	vec2 dir_xz = normalize(pg_wind_dir);
	vec3 dir_world = normalize(vec3(dir_xz.x, 0.0, dir_xz.y));
	mat3 inv_model = inverse(mat3(model_matrix));
	vec3 dir_model = normalize(inv_model * dir_world);
	float h_pow = pow(h, pg_height_exp);
	float target = pg_wind_strength * H * (pg_lean_base + pg_lean_gust_gain * g) * h_pow;
	float frac = fract(pg_sim_time / max(pg_flutter_period_sec, 1e-6));
	float ring = pg_overshoot_gain * target * exp(-pg_spring_damping * frac)
			* sin(TAU * pg_spring_freq_hz * pg_sim_time + blade_hash_01 * TAU * pg_phase_spread);
	vec3 offset_model = dir_model * (target + ring);
	return pg_apply_droop(vertex_model, offset_model, h, H);
}

vec3 pg_tip_displace(vec3 vertex_model, float h, float blade_height_h, mat4 model_matrix, vec2 root_world_xz, float blade_hash_01) {
	float H = max(blade_height_h, 1e-4);
	vec2 dir_xz = normalize(pg_wind_dir);
	float g = pg_gust_at(root_world_xz);
	if (pg_variant == 1) {
		g = pg_wave_g(root_world_xz, dir_xz);
		return pg_displace_v0(vertex_model, h, H, model_matrix, root_world_xz, blade_hash_01, g);
	}
	if (pg_variant == 2) {
		return pg_displace_v2(vertex_model, h, H, model_matrix, root_world_xz, g);
	}
	if (pg_variant == 3) {
		return pg_displace_v3(vertex_model, h, H, model_matrix, root_world_xz, blade_hash_01, g);
	}
	if (pg_variant == 4) {
		g = pg_front_g(root_world_xz, dir_xz);
		return pg_displace_v0(vertex_model, h, H, model_matrix, root_world_xz, blade_hash_01, g);
	}
	return pg_displace_v0(vertex_model, h, H, model_matrix, root_world_xz, blade_hash_01, g);
}

void vertex() {
	v_uv = UV;
	v_h = 1.0 - UV.y;
	v_hash = COLOR.r;
	vec2 root_world_xz = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz;
	float blade_H = (v_h > 1e-3) ? (VERTEX.y / v_h) : VERTEX.y;
	vec3 pos = pg_tip_displace(VERTEX, v_h, blade_H, MODEL_MATRIX, root_world_xz, COLOR.r);
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
	float g = pg_gust_at(v_world_pos.xz);
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
