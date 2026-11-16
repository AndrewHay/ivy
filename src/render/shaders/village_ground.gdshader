shader_type spatial;

// Stylized lawn read at distance — broad patches aligned with blade mid tone (SD-GRASS-2 far tier).
// WP2 / SD-VILLAGE-TERRAIN-8: slope/height shading added for terrain relief readability.
// Flat-parity contract: when v_world_normal.y = 1.0 (flat mesh) slope_mix = 0 and with the default
// terrain_height_tint = 0 the height factor is 1.0 → col unchanged
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
// ivy-82zn.14.1: slope (deg) at which the full terrain_slope_dark applies. 0 = legacy
// (1 − normal.y) ramp, which is ~0.01 at 8° and so invisible on the village lawn.
// Production sets this from VillageTerrainParams.ground_slope_full_deg.
uniform float terrain_slope_full_deg : hint_range(0.0, 90.0) = 0.0;
// ivy-82zn.14.1: height tint. Albedo × (1 + terrain_height_tint × t), t = clamp(local y /
// terrain_height_range_m, −1, 1): rises read lighter, hollows darker. 0 = off (default),
// so flat meshes and any material that does not set it are unchanged (INV-15).
uniform float terrain_height_tint : hint_range(0.0, 0.5) = 0.0;
// ivy-82zn.14.10: range up to 20 m (production 8.5 m = the village hill rise; rim datum is y 0).
uniform float terrain_height_range_m : hint_range(0.1, 20.0) = 1.0;

varying vec3 v_world_pos;
// World-space normal for slope shading. Computed in vertex() so it follows displaced vertices.
varying vec3 v_world_normal;
// Mesh-local height (VillageTerrain builds Y_BASE + h, so this is h).
varying float v_local_y;

void vertex() {
	v_local_y = VERTEX.y;
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
	// Interpolated varyings are shorter than unit between vertices; renormalise so flat ground
	// does not read as ~0.5° of slope under the acos ramp (ivy-82zn.14.5).
	float ny = clamp(normalize(v_world_normal).y, 0.0, 1.0);
	float slope_mix = 1.0 - ny;
	if (terrain_slope_full_deg > 0.0) {
		slope_mix = clamp(degrees(acos(ny)) / terrain_slope_full_deg, 0.0, 1.0);
	}
	float slope_dim = 1.0 - terrain_slope_dark * slope_mix;
	col *= slope_dim;

	// Height tint (ivy-82zn.14.1). terrain_height_tint = 0 ⇒ factor 1.0 exactly.
	float t_h = clamp(v_local_y / max(terrain_height_range_m, 0.01), -1.0, 1.0);
	col *= 1.0 + terrain_height_tint * t_h;

	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
