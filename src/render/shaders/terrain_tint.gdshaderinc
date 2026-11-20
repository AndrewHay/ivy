// Shared terrain slope / height tint (AR-LF-D9, ivy-82zn.14.14). Included by village_ground.gdshader
// (lawn) and village_ground_hills.gdshader (far hills) so both sides of the join loop apply the
// same factors. Formulas are the ivy-82zn.14.1 / .14.5 ones, unchanged. CPU mirror:
// VillageTerrain.terrain_tint_factor (tests pin parity).
//
// Flat-parity contract: ny = 1 → slope dim 1; terrain_height_tint = 0 (default) → height factor 1.
// Materials that never set these uniforms render exactly as before (INV-15).

// Slope shading strength: 0 = none; 1 = full dim (vertical faces → black).
uniform float terrain_slope_dark : hint_range(0.0, 1.0) = 0.35;
// Slope (deg) at which the full terrain_slope_dark applies. 0 = legacy (1 − normal.y) ramp.
uniform float terrain_slope_full_deg : hint_range(0.0, 90.0) = 0.0;
// Height tint: albedo × (1 + tint × t), t = clamp((y − terrain_height_ref_y) / range, −1, 1).
uniform float terrain_height_tint : hint_range(0.0, 0.5) = 0.0;
uniform float terrain_height_range_m : hint_range(0.1, 20.0) = 1.0;
// Height reference (mesh-local y): y_hero for generated terrain, 0 otherwise.
uniform float terrain_height_ref_y = 0.0;

// ny: world normal y, renormalised by the caller (interpolated varyings are shorter than unit).
float terrain_slope_dim(float ny) {
	float n = clamp(ny, 0.0, 1.0);
	float slope_mix = 1.0 - n;
	if (terrain_slope_full_deg > 0.0) {
		slope_mix = clamp(degrees(acos(n)) / terrain_slope_full_deg, 0.0, 1.0);
	}
	return 1.0 - terrain_slope_dark * slope_mix;
}

float terrain_height_factor(float local_y) {
	float t_h = clamp((local_y - terrain_height_ref_y) / max(terrain_height_range_m, 0.01), -1.0, 1.0);
	return 1.0 + terrain_height_tint * t_h;
}
