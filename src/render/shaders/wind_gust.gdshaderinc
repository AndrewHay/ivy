// SD-WIND-2 shared gust field (global uniforms; include once per shader).

global uniform vec2 ivy_wind_dir;
global uniform float ivy_wind_strength;
global uniform vec2 ivy_wind_scroll;
global uniform float ivy_wind_flutter_phase;
global uniform float ivy_wind_gust_tile_m;
global uniform sampler2D ivy_wind_gust_noise : filter_linear_mipmap, repeat_enable;


float ivy_gust_at(vec2 world_xz) {
	vec2 uv = (world_xz - ivy_wind_scroll) / ivy_wind_gust_tile_m;
	float n = textureLod(ivy_wind_gust_noise, uv, 0.0).r;
	return smoothstep(0.38, 0.78, n);
}


vec3 ivy_wind_tip_displace_model(
		vec3 vertex_model,
		float h,
		float blade_height_h,
		mat4 model_matrix,
		vec2 root_world_xz,
		float blade_hash_01) {
	if (ivy_wind_strength < 0.001) {
		return vertex_model;
	}
	h = clamp(h, 0.0, 1.0);
	float H = max(blade_height_h, 1e-4);
	vec2 dir_xz = normalize(ivy_wind_dir);
	float g = ivy_gust_at(root_world_xz);
	vec3 dir_world = normalize(vec3(dir_xz.x, 0.0, dir_xz.y));
	mat3 inv_model = inverse(mat3(model_matrix));
	vec3 dir_model = normalize(inv_model * dir_world);
	float lean = ivy_wind_strength * H * (0.10 + 0.45 * g) * h * h;
	vec3 offset_model = dir_model * lean;
	float flutter = ivy_wind_strength * H * 0.04 * (0.4 + g)
			* sin(ivy_wind_flutter_phase + blade_hash_01 * TAU + dot(root_world_xz, dir_xz) * 1.3)
			* h * h;
	offset_model += dir_model * flutter;
	float droop = (dot(offset_model, offset_model) / (2.0 * H)) * h;
	return vertex_model + offset_model - vec3(0.0, droop, 0.0);
}


const float IVY_LEAF_LEAN = 0.02;
const float IVY_LEAF_GUST_GAIN = 0.08;
const float IVY_LEAF_FLUTTER = 0.035;


float ivy_leaf_wind_weight(float uv_y) {
	if (uv_y > 1.25) {
		// Petiole (UV v 2.5 = stem attachment, 1.5 = blade junction); pinned at stem.
		return max(0.0, (2.5 - uv_y) / 1.0) * 0.12;
	}
	// Blade atlas v: 1 at node attachment, 0 at tip.
	return clamp(1.0 - uv_y, 0.0, 1.0);
}


float ivy_leaf_hash(vec3 root_world) {
	return fract(sin(dot(root_world.xz + root_world.y * 0.17, vec2(12.9898, 78.233))) * 43758.5453);
}


vec3 ivy_leaf_wind_offset_model(
		vec3 vertex_model,
		float uv_y,
		mat4 model_matrix,
		vec3 root_world) {
	float w = ivy_leaf_wind_weight(uv_y);
	if (ivy_wind_strength < 0.001 || w < 1e-5) {
		return vertex_model;
	}
	float wind_e = ivy_wind_strength;
	float leaf_len_m = length(model_matrix[1].xyz);
	float g = ivy_gust_at(root_world.xz);
	vec2 dir_xz = ivy_wind_dir;
	if (dot(dir_xz, dir_xz) < 1e-8) {
		dir_xz = vec2(1.0, 0.0);
	}
	dir_xz = normalize(dir_xz);
	vec3 d = vec3(dir_xz.x, 0.0, dir_xz.y);
	vec3 n_w = normalize(mat3(model_matrix) * vec3(0.0, 0.0, 1.0));
	vec3 d_t = d - n_w * dot(d, n_w);
	float dt_len = length(d_t);
	d_t = dt_len > 1e-5 ? d_t / dt_len : vec3(0.0);
	float w2 = w * w;
	vec3 offset_world = d_t * (wind_e * leaf_len_m * (IVY_LEAF_LEAN + IVY_LEAF_GUST_GAIN * g) * w2);
	float leaf_hash = ivy_leaf_hash(root_world);
	offset_world += n_w * (
			wind_e * leaf_len_m * IVY_LEAF_FLUTTER * (0.3 + g)
			* sin(ivy_wind_flutter_phase * 2.0 + leaf_hash * TAU + dot(root_world.xz, dir_xz) * 1.3)
			* w);
	mat3 inv_model = inverse(mat3(model_matrix));
	return vertex_model + inv_model * offset_world;
}
