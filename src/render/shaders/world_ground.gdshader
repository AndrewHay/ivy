// World/Ground procedural lawn (main.tscn plane) — SD-GRASS-2 far read + SD-WIND-2 gust sheen.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

#include "res://src/render/shaders/wind_gust.gdshaderinc"

uniform vec3 color_lo : source_color = vec3(0.22, 0.34, 0.16);
uniform vec3 color_hi : source_color = vec3(0.30, 0.42, 0.21);
uniform float noise_scale : hint_range(0.01, 1.0) = 0.08;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;

varying vec3 v_world_pos;

float hash(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i + vec2(0, 0));
	float b = hash(i + vec2(1, 0));
	float c = hash(i + vec2(0, 1));
	float d = hash(i + vec2(1, 1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 world_xz = v_world_pos.xz;
	float n = noise(world_xz * noise_scale);
	n = mix(n, noise(world_xz * noise_scale * 3.1 + vec2(5.7, 2.3)), 0.35);
	vec3 col = mix(color_lo, color_hi, n);
	float g = ivy_gust_at(world_xz);
	col *= 1.0 + (g - 0.5) * 0.10 * ivy_wind_strength;
	ALBEDO = col;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
