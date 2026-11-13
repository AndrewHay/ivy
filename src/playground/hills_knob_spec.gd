class_name HillsKnobSpec
extends RefCounted

const VARIANT_LABELS := [
	"0 — Rolling hills (production)",
	"1 — Flat legacy",
	"2 — High ridges",
]

const VARIANT_DESCRIPTIONS := [
	"Domain-warped fBm meadows; production generated villages.",
	"Old flat HillRing ramp (no forest on classic layout).",
	"Taller height scale and denser copses on rolling algorithm.",
]

const VARIANT_HELP := "Variant = flat legacy vs rolling vs high ridges."
const PRESET_HELP := "Preset = full recipe; Reset restores production defaults."

const ALL_VARIANTS := [0, 1, 2]
const ROLLING := [0, 2]


static func all_knobs() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	_add_int(rows, "layout_seed", "Layout seed", "Stage", 1, 999999999, 1, ALL_VARIANTS,
		"VillageLayout.generate(seed); drives terrain + forest LCG.")
	_add_int(rows, "variant", "Variant", "Stage", 0, 2, 1, ALL_VARIANTS)
	_add_float(rows, "r_inner_m", "Inner radius (m)", "Annulus", 50.0, 130.0, 0.5, ROLLING)
	_add_float(rows, "r_outer_m", "Outer radius (m)", "Annulus", 100.0, 400.0, 1.0, ROLLING)
	_add_int(rows, "grid_cells", "Radial cells", "Annulus", 32, 160, 4, ROLLING)
	_add_int(rows, "azimuth_segs", "Azimuth segs", "Annulus", 32, 160, 4, ROLLING)
	_add_float(rows, "toe_width_m", "Toe width (m)", "Seam", 2.0, 16.0, 0.25, ROLLING)
	_add_float(rows, "toe_max_lift_m", "Toe max lift (m)", "Seam", 0.0, 0.5, 0.01, ROLLING)
	_add_float(rows, "base_feature_m", "Base feature (m)", "Noise", 60.0, 250.0, 1.0, ROLLING)
	_add_int(rows, "noise_octaves", "fBm octaves", "Noise", 2, 4, 1, ROLLING)
	_add_float(rows, "noise_persistence", "Persistence", "Noise", 0.30, 0.7, 0.02, ROLLING)
	_add_float(rows, "warp_strength", "Domain warp", "Noise", 0.1, 0.55, 0.02, ROLLING)
	_add_float(rows, "height_scale_m", "Height scale (m)", "Noise", 20.0, 100.0, 0.5, ROLLING)
	_add_int(rows, "layer_count", "Layer count", "Ridge", 2, 4, 1, ROLLING)
	_add_float(rows, "layer_dist_0", "Layer 0 dist (m)", "Ridge", 60.0, 210.0, 1.0, ROLLING)
	_add_float(rows, "layer_dist_1", "Layer 1 dist (m)", "Ridge", 70.0, 250.0, 1.0, ROLLING)
	_add_float(rows, "layer_dist_2", "Layer 2 dist (m)", "Ridge", 85.0, 290.0, 1.0, ROLLING)
	_add_float(rows, "layer_dist_3", "Layer 3 dist (m)", "Ridge", 100.0, 330.0, 1.0, ROLLING)
	_add_float(rows, "layer_amp_scale_0", "Layer 0 amp", "Ridge", 0.55, 1.45, 0.05, ROLLING)
	_add_float(rows, "layer_amp_scale_1", "Layer 1 amp", "Ridge", 0.55, 1.45, 0.05, ROLLING)
	_add_float(rows, "layer_amp_scale_2", "Layer 2 amp", "Ridge", 0.55, 1.45, 0.05, ROLLING)
	_add_float(rows, "layer_amp_scale_3", "Layer 3 amp", "Ridge", 0.35, 1.25, 0.05, ROLLING)
	_add_float(rows, "radial_bias_power", "Outer fade power", "Ridge", 0.8, 2.0, 0.05, ROLLING)
	_add_int(rows, "tree_count", "Hill tree count", "Forest", 0, 500, 5, ROLLING)
	_add_float(rows, "forest_r_min_m", "Forest R min (m)", "Forest", 55.0, 130.0, 0.5, ROLLING)
	_add_float(rows, "forest_r_max_m", "Forest R max (m)", "Forest", 100.0, 330.0, 1.0, ROLLING)
	_add_float(rows, "min_sep_m", "Min trunk sep (m)", "Forest", 2.0, 6.0, 0.1, ROLLING)
	_add_float(rows, "slope_max_deg", "Slope max (°)", "Forest", 20.0, 50.0, 1.0, ROLLING)
	_add_float(rows, "slope_prefer_deg", "Slope prefer (°)", "Forest", 8.0, 30.0, 1.0, ROLLING)
	_add_float(rows, "copse_scale_m", "Copse scale (m)", "Forest", 12.0, 45.0, 0.5, ROLLING)
	_add_float(rows, "copse_threshold", "Copse threshold", "Forest", 0.2, 0.65, 0.01, ROLLING)
	_add_float(rows, "lone_tree_rate", "Lone tree rate", "Forest", 0.0, 0.2, 0.005, ROLLING)
	_add_float(rows, "forest_green_darken", "Forest darken", "Forest", 0.0, 0.35, 0.01, ROLLING)
	_add_float(rows, "hemisphere_boost_phi", "Hemisphere φ half", "Forest", 0.3, 1.2, 0.01, ROLLING)
	_add_float(rows, "hemisphere_boost", "CamSun boost", "Forest", 0.8, 1.6, 0.02, ROLLING)
	_add_float(rows, "hemisphere_lo", "Other hemisphere", "Forest", 0.6, 1.2, 0.02, ROLLING)
	_add_float(rows, "backdrop_exclusion_m", "Backdrop exclusion (m)", "Forest", 1.0, 5.0, 0.1, ROLLING)
	_add_int(rows, "lcg_seed", "Forest LCG (−1=derive)", "Forest", -1, 999999, 1, ROLLING)
	_add_float(rows, "scale_min", "Tree scale min", "Forest", 0.6, 2.5, 0.02, ROLLING)
	_add_float(rows, "scale_max", "Tree scale max", "Forest", 0.8, 3.0, 0.02, ROLLING)
	_add_bool(rows, "ridge_fog_tint_on", "Fog tint on", "Tint", ROLLING)
	_add_float(rows, "ridge_near_albedo_mul", "Near albedo mul", "Tint", 0.7, 1.2, 0.02, ROLLING)
	_add_float(rows, "ridge_near_green_bias", "Near green bias", "Tint", 0.0, 0.2, 0.005, ROLLING)
	_add_float(rows, "ridge_far_albedo_mul", "Far albedo mul", "Tint", 0.5, 0.9, 0.02, ROLLING)
	_add_float(rows, "ridge_far_tint_blue", "Far blue tint", "Tint", 0.0, 0.2, 0.005, ROLLING)
	_add_float(rows, "sun_warmth", "Sun warmth", "Tint", 0.0, 0.45, 0.01, ROLLING)
	_add_float(rows, "fog_begin_m", "Fog begin (−1=layout)", "Fog", -1.0, 150.0, 0.5, ROLLING)
	_add_float(rows, "fog_end_m", "Fog end (−1=layout)", "Fog", 60.0, 400.0, 1.0, ROLLING)
	_add_float(rows, "azimuth_centre_deg", "Wedge centre (°)", "Azimuth", 0.0, 360.0, 5.0, ROLLING,
		"0=north(−Z), 90=east(+X). Hills only appear within ±half-width of this bearing.")
	_add_float(rows, "azimuth_half_width_deg", "Wedge half-width (°)", "Azimuth", 10.0, 180.0, 5.0, ROLLING,
		"Angular half-width of the hill wedge. 180=full circle.")
	_add_float(rows, "azimuth_fade_width_deg", "Wedge fade width (°)", "Azimuth", 0.0, 45.0, 2.0, ROLLING,
		"Smooth taper width at each edge of the wedge (prevents sharp cutoff).")
	return rows


static func _add_float(
		rows: Array[Dictionary], name: String, label: String, group: String,
		min_v: float, max_v: float, step: float, variants: Array, tip: String = "") -> void:
	rows.append({
		"name": name, "label": label, "group": group, "type": "float",
		"min": min_v, "max": max_v, "step": step, "variants": variants, "tip": tip,
	})


static func _add_int(
		rows: Array[Dictionary], name: String, label: String, group: String,
		min_v: int, max_v: int, step: int, variants: Array, tip: String = "") -> void:
	rows.append({
		"name": name, "label": label, "group": group, "type": "float",
		"min": float(min_v), "max": float(max_v), "step": float(step),
		"variants": variants, "tip": tip, "is_int": true,
	})


static func _add_bool(
		rows: Array[Dictionary], name: String, label: String, group: String,
		variants: Array, tip: String = "") -> void:
	rows.append({
		"name": name, "label": label, "group": group, "type": "bool",
		"variants": variants, "tip": tip,
	})
