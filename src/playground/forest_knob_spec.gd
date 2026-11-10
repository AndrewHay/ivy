class_name ForestKnobSpec
extends RefCounted

const VARIANT_LABELS := [
	"0 — Tree backdrop (production)",
	"1 — Deep wedge",
	"2 — Arc ring behind hero",
	"3 — Wedge + CamSun gap flanks",
	"4 — Tree backdrop (tune)",
	"5 — Old: behind the camera",
]

const VARIANT_DESCRIPTIONS := [
	"Lawn band 40–55 m from CamSun: village in front of visible trees.",
	"Extends the +Z wedge to R+25 with bias toward the outer trees.",
	"Samples a wide arc on an annulus R+6..R+16 behind the hero.",
	"CamSun corridor clear; dense strips frame left and right.",
	"Same backdrop algorithm as production — live tuning.",
	"Legacy +Z wedge behind the camera (empty CamSun horizon).",
]

const VARIANT_HELP := "Variant = different placement algorithm (not just slider values)."
const PRESET_HELP := "Preset = full recipe: resets to production, then applies the preset (may also set variant)."


static func all_knobs() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var all := [0, 1, 2, 3, 4, 5]
	var backdrop := [0, 4]
	_add_int(rows, "layout_seed", "Layout seed", "Stage", 1, 999999999, 1, all,
		"VillageLayout.generate(seed) for cottages, paths, and R.")
	_add_int(rows, "tree_count", "Tree count (−1=layout)", "Stage", -1, 80, 1, all,
		"−1 uses layout.pine_count (40). Otherwise overrides target count.")
	_add_int(rows, "lcg_seed", "LCG seed", "A", 0, 999999, 1, [0, 1, 3],
		"Knuth LCG stream start (production 7).")
	_add_float(rows, "min_sep_m", "Min separation (m)", "A", 1.0, 8.0, 0.1, all,
		"Minimum trunk spacing.")
	_add_float(rows, "w_max", "Weight cap", "A", 0.5, 2.5, 0.01, all,
		"Maximum accept weight for probabilistic passes.")
	_add_float(rows, "wedge_phi_half_rad", "Wedge half-angle (rad)", "B", 0.2, 1.6, 0.01, [1, 3, 5],
		"Half-width of the +Z wedge behind G (production 0.62).")
	_add_float(rows, "wedge_r_inset_m", "Wedge inner inset (m)", "B", 0.0, 12.0, 0.25, [1, 3, 5],
		"Inner radius = R − inset.")
	_add_float(rows, "wedge_r_outset_m", "Wedge outer outset (m)", "B", 4.0, 40.0, 0.5, [0, 1, 3],
		"Outer radius = R + outset.")
	_add_float(rows, "wedge_sample_frac", "Wedge sample frac", "B", 0.0, 1.0, 0.01, [0, 1, 3],
		"Probability of wedge/collar sampling vs scatter box.")
	_add_float(rows, "wedge_quota_frac", "Wedge quota frac", "B", 0.0, 1.0, 0.01, [0, 1, 3],
		"Fraction of trees forced into wedge before collar fill.")
	_add_int(rows, "wedge_min_before_collar", "Min wedge before collar", "B", 0, 60, 1, [0, 1, 3],
		"Top-up to this many wedge trees before collar phase.")
	_add_float(rows, "back_yard_z_max", "Back yard Z max", "B", 0.0, 12.0, 0.1, [0, 1, 3],
		"Suppress low-Z accept inside lawn.")
	_add_float(rows, "collar_inset_m", "Collar inner (m)", "C", 0.0, 8.0, 0.25, [0, 1, 3],
		"G-centred collar band inner offset.")
	_add_float(rows, "collar_outer_m", "Collar outer (m)", "C", 4.0, 24.0, 0.25, [0, 1, 3],
		"Collar outer offset from R.")
	_add_float(rows, "collar_weight_lo", "Collar weight lo", "C", 0.0, 1.5, 0.01, [0, 1, 3])
	_add_float(rows, "collar_weight_hi", "Collar weight hi", "C", 0.0, 1.5, 0.01, [0, 1, 3])
	_add_float(rows, "scatter_weight", "Scatter weight", "C", 0.0, 0.5, 0.01, [0, 1, 3])
	_add_float(rows, "scatter_box_x_half", "Scatter box X", "C", 20.0, 90.0, 1.0, [0, 1, 3])
	_add_float(rows, "scatter_box_z_back", "Scatter box Z back", "C", 20.0, 80.0, 1.0, [0, 1, 3])
	_add_float(rows, "scatter_box_z_front", "Scatter box Z front", "C", 20.0, 80.0, 1.0, [0, 1, 3])
	_add_bool(rows, "camsun_corridor_on", "CamSun corridor on", "D", [1, 2, 3, 5],
		"Reject trunks in the south approach sight line.")
	_add_float(rows, "camsun_x_half", "CamSun X half (m)", "D", 1.0, 12.0, 0.25, [0, 1, 2, 3])
	_add_float(rows, "camsun_z_min", "CamSun Z min", "D", -2.0, 8.0, 0.1, [0, 1, 2, 3])
	_add_float(rows, "camsun_z_max", "CamSun Z max", "D", 4.0, 20.0, 0.1, [0, 1, 2, 3])
	_add_float(rows, "camsun_corridor_y_slack", "CamSun Y slack", "D", 2.0, 16.0, 0.5, [0, 1, 2, 3])
	_add_float(rows, "wedge_weight", "Wedge weight", "E", 0.5, 2.0, 0.01, [0, 1, 3])
	_add_float(rows, "deep_outer_bias", "Deep outer bias", "E", 0.0, 2.0, 0.05, [1],
		"Variant 1 only: boost accept weight toward outer radius.")
	_add_float(rows, "arc_phi_half_rad", "Arc φ half (rad)", "F", 0.3, 1.6, 0.01, [2])
	_add_float(rows, "arc_r_inner_offset_m", "Arc R inner +", "F", 2.0, 20.0, 0.5, [2])
	_add_float(rows, "arc_r_outer_offset_m", "Arc R outer +", "F", 6.0, 40.0, 0.5, [2])
	_add_float(rows, "flank_x_offset_m", "Flank X offset", "G", 4.0, 14.0, 0.25, [3])
	_add_float(rows, "flank_weight", "Flank weight", "G", 0.5, 2.0, 0.05, [3])
	_add_float(rows, "backdrop_cam_dist_lo_m", "Cam dist inner (m)", "V", 32.0, 52.0, 0.5, backdrop,
		"Horizontal distance from CamSun camera.")
	_add_float(rows, "backdrop_cam_dist_hi_m", "Cam dist outer (m)", "V", 40.0, 65.0, 0.5, backdrop)
	_add_float(rows, "backdrop_phi_half_rad", "Backdrop width (rad)", "V", 0.25, 1.0, 0.01, backdrop)
	_add_float(rows, "backdrop_tree_scale_mul", "Tree scale mul", "V", 1.0, 1.8, 0.02, backdrop)
	_add_float(rows, "backdrop_min_sep_m", "Backdrop spacing (m)", "V", 1.5, 4.0, 0.1, backdrop)
	_add_float(rows, "scale_min", "Scale min", "H", 0.5, 1.5, 0.05, all)
	_add_float(rows, "scale_max", "Scale max", "H", 0.8, 2.5, 0.05, all)
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
