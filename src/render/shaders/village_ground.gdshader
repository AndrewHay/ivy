shader_type spatial;

// Stylized lawn read at distance — broad patches aligned with blade mid tone (SD-GRASS-2 far tier).

#include "res://src/render/shaders/wind_gust.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.30, 0.44, 0.22);
uniform vec3 patch_hi : source_color = vec3(0.34, 0.46, 0.24);
uniform vec3 patch_lo : source_color = vec3(0.20, 0.32, 0.16);
uniform float patch_scale : hint_range(0.05, 2.0, 0.01) = 0.22;
uniform float patch_contrast : hint_range(0.0, 1.0, 0.01) = 0.26;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float patch_noise(vec2 xz) {
	vec2 p = xz * patch_scale;
	float a = hash21(floor(p));
	float b = hash21(floor(p) + vec2(1.0, 0.0));
	float c = hash21(floor(p) + vec2(0.0, 1.0));
	float d = hash21(floor(p) + vec2(1.0, 1.0));
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 world_xz = v_world_pos.xz;
	float n = patch_noise(world_xz);
	vec3 col = mix(patch_lo, patch_hi, n);
	col = mix(base_color, col, patch_contrast);
	float g = ivy_gust_at(world_xz);
	col *= 1.0 + (g - 0.5) * 0.10 * ivy_wind_strength;
	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
