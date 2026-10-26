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
