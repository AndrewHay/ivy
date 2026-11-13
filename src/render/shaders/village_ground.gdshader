shader_type spatial;

// Stylized lawn read at distance — broad patches aligned with blade mid tone (SD-GRASS-2 far tier).
// WP2 / SD-VILLAGE-TERRAIN-8: slope/height shading added for terrain relief readability.
// Flat-parity contract: when v_world_normal.y = 1.0 (flat mesh) slope_mix = 0 → col unchanged
// (INV-15 classic / variant-1 output byte-identical). AR-VT-DECIDE-1.

#include "res://src/render/shaders/wind_gust.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.30, 0.44, 0.22);
uniform vec3 patch_hi : source_color = vec3(0.34, 0.46, 0.24);
uniform vec3 patch_lo : source_color = vec3(0.20, 0.32, 0.16);
uniform float patch_scale : hint_range(0.05, 2.0, 0.01) = 0.22;
uniform float patch_contrast : hint_range(0.0, 1.0, 0.01) = 0.26;
// Slope shading strength: 0 = no slope tint; 1 = full dim (vertical faces → black).
// Default 0.35 keeps it subtle (cosy) while making knolls/basins readable.
// Flat meshes (normal = UP) are unaffected (slope_mix = 0), preserving INV-15.
uniform float terrain_slope_dark : hint_range(0.0, 1.0) = 0.35;

varying vec3 v_world_pos;
// World-space normal for slope shading. Computed in vertex() so it follows displaced vertices.
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Normalise so scale on MODEL_MATRIX does not skew the normal.
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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

	// Terrain slope shading (WP2 / SD-VILLAGE-TERRAIN-8).
	// slope_mix = 0 for flat normals (y=1.0) → no change → byte-identical to classic (INV-15).
	// slope_mix > 0 for sloped faces → gentle darkening proportional to slope steepness.
	float slope_mix = 1.0 - clamp(v_world_normal.y, 0.0, 1.0);
	float slope_dim = 1.0 - terrain_slope_dark * slope_mix;
	col *= slope_dim;

	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
