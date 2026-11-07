shader_type spatial;

// Muddy damp bank ring around the village pond (ivy-86l).

#include "res://src/render/shaders/wind_gust.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.24, 0.30, 0.18);
uniform vec3 wet_hi : source_color = vec3(0.28, 0.34, 0.20);
uniform float patch_scale : hint_range(0.05, 2.0, 0.01) = 0.45;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 world_xz = v_world_pos.xz;
	float n = hash21(floor(world_xz * patch_scale));
	vec3 col = mix(base_color, wet_hi, n * 0.35);
	float g = ivy_gust_at(world_xz);
	col *= 1.0 + (g - 0.5) * 0.08 * ivy_wind_strength;
	ALBEDO = col;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
}
