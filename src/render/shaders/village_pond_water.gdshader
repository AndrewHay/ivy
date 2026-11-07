shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// Village pond — smoothed polygon fill with stylized depth + sun glints (ivy-86l).

#include "res://src/render/shaders/wind_gust.gdshaderinc"

uniform vec3 shallow_color : source_color = vec3(0.38, 0.68, 0.58);
uniform vec3 deep_color : source_color = vec3(0.06, 0.28, 0.38);
uniform vec3 sky_tint : source_color = vec3(0.55, 0.72, 0.82);
uniform vec2 pond_center_xz = vec2(-6.5, 10.5);
uniform float pond_radius_m : hint_range(0.5, 6.0, 0.01) = 2.625;
uniform float ripple_scale : hint_range(0.05, 2.0, 0.01) = 0.85;
uniform float ripple_speed : hint_range(0.0, 2.0, 0.01) = 0.28;
uniform float ripple_normal_strength : hint_range(0.0, 0.4, 0.01) = 0.12;

varying vec3 v_world_pos;
varying vec2 v_pond_uv;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_pond_uv = UV;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float ripple_height(vec2 xz) {
	vec2 p = xz * ripple_scale + vec2(TIME * ripple_speed, TIME * ripple_speed * 0.71);
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 world_xz = v_world_pos.xz;
	vec2 to_c = world_xz - pond_center_xz;
	float r = length(to_c) / pond_radius_m;
	float depth = smoothstep(0.15, 1.05, r);

	float rip = ripple_height(world_xz);
	vec3 col = mix(deep_color, shallow_color, rip * (1.0 - depth * 0.35) + 0.15);
	col = mix(col, sky_tint, depth * 0.22);

	float eps = 0.04;
	float hx = ripple_height(world_xz + vec2(eps, 0.0)) - ripple_height(world_xz - vec2(eps, 0.0));
	float hz = ripple_height(world_xz + vec2(0.0, eps)) - ripple_height(world_xz - vec2(0.0, eps));
	vec3 n = normalize(vec3(-hx, 1.0, -hz) * ripple_normal_strength + vec3(0.0, 1.0, 0.0));

	vec3 view_dir = normalize(VIEW);
	float fresnel = pow(1.0 - max(dot(n, view_dir), 0.0), 3.0);
	col = mix(col, sky_tint, fresnel * 0.35);

	float g = ivy_gust_at(world_xz);
	col *= 1.0 + (g - 0.5) * 0.05 * ivy_wind_strength;

	ALBEDO = col;
	ROUGHNESS = mix(0.04, 0.14, depth);
	METALLIC = 0.0;
	SPECULAR = mix(0.55, 0.25, depth);
	NORMAL = n;
}
