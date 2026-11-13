## VillageTerrainKnobSpec — knob table for the village terrain playground panel.
## Covers every field in SD-VILLAGE-TERRAIN-2; reuses knob_panel.gd row format.
## AR-VT-FILES / SD-VILLAGE-TERRAIN-9.
class_name VillageTerrainKnobSpec
extends RefCounted

const VARIANT_LABELS := [
	"0 — Rolling lawn (production)",
	"1 — Flat legacy (INV-15)",
	"2 — High relief (A/B only)",
]

const VARIANT_DESCRIPTIONS := [
	"Domain-warped fBm lawn with knolls, pond basin, cottage pads.",
	"Pre-terrain flat lawn — byte-identical to today (INV-15).",
	"Higher amplitude and more knolls for A/B feel comparison.",
]

const VARIANT_HELP := "Variant selects flat-legacy parity vs rolling vs high-relief."
const PRESET_HELP := "Preset = full recipe; Reset restores production defaults."

## All variants (used for stage knobs visible in all modes).
const ALL_VARIANTS := [0, 1, 2]
## Rolling variants only (knobs that don't apply to flat legacy).
const ROLLING := [0, 2]


static func all_knobs() -> Array[Dictionary]:
	## Returns the ordered knob table for KnobPanel / VillageTerrainPlayground.
	var rows: Array[Dictionary] = []

	# Stage
	_add_int(rows, "layout_seed", "Layout seed", "Stage", 1, 999999999, 1, ALL_VARIANTS,
		"VillageLayout.generate(seed); drives terrain + knoll LCG.")
	_add_int(rows, "variant", "Variant", "Stage", 0, 2, 1, ALL_VARIANTS, VARIANT_HELP)

	# Base noise
	_add_float(rows, "base_amplitude_m", "Base amplitude (m)", "Base noise",
		0.0, 1.0, 0.01, ROLLING, "Peak h; 0 = flat base field.")
	_add_float(rows, "base_feature_m", "Base wavelength (m)", "Base noise",
		12.0, 48.0, 0.5, ROLLING)
	_add_int(rows, "noise_octaves", "fBm octaves", "Base noise",
		1, 5, 1, ROLLING)
	_add_float(rows, "noise_persistence", "Persistence", "Base noise",
		0.3, 0.7, 0.02, ROLLING)
	_add_float(rows, "warp_strength", "Domain warp", "Base noise",
		0.0, 0.6, 0.02, ROLLING)
	_add_float(rows, "center_bias_gain", "Centre bias", "Base noise",
		0.5, 1.6, 0.05, ROLLING, ">1 lifts relief toward G.")
	_add_float(rows, "dir_bias_gain", "Dir bias gain", "Base noise",
		0.0, 0.5, 0.02, ROLLING)
	_add_float(rows, "dir_bias_phi_deg", "Dir bias azimuth (°)", "Base noise",
		0.0, 360.0, 5.0, ROLLING)

	# Seam
	_add_float(rows, "rim_blend_m", "Rim blend (m)", "Seam",
		3.0, 8.0, 0.25, ROLLING, "C0 rim taper width.")
	_add_float(rows, "rim_eps_m", "Rim eps (m)", "Seam",
		0.02, 0.12, 0.01, ROLLING, "AC-VT8 rim parity tolerance vs hills domain.")

	# Caps
	_add_float(rows, "max_rise_m", "Max rise (m)", "Caps",
		0.2, 1.2, 0.05, ROLLING)
	_add_float(rows, "max_depression_m", "Max depression (m)", "Caps",
		0.2, 1.0, 0.05, ROLLING)
	_add_float(rows, "max_path_slope_deg", "Max path slope (°)", "Caps",
		4.0, 12.0, 0.5, ROLLING)

	# Hero
	_add_float(rows, "hero_flat_r_m", "Hero flat radius (m)", "Hero",
		5.0, 9.0, 0.25, ROLLING, "Flat disc around stoop (ivy sim / planting unchanged).")
	_add_float(rows, "hero_skirt_m", "Hero skirt (m)", "Hero",
		1.5, 5.0, 0.25, ROLLING)

	# Pads
	_add_float(rows, "pad_margin_m", "Pad margin (m)", "Pads",
		0.2, 1.5, 0.1, ROLLING)
	_add_float(rows, "pad_skirt_m", "Pad skirt (m)", "Pads",
		0.8, 3.0, 0.1, ROLLING)
	_add_float(rows, "pad_edge_slope_max_deg", "Pad edge slope max (°)", "Pads",
		4.0, 12.0, 0.5, ROLLING)

	# Pond
	_add_float(rows, "pond_depth_m", "Pond depth (m)", "Pond",
		-1.0, -0.2, 0.05, ROLLING, "Basin floor relative to local field (negative).")
	_add_float(rows, "pond_floor_scale", "Pond floor scale", "Pond",
		0.6, 1.4, 0.05, ROLLING)
	_add_float(rows, "pond_rim_extra_m", "Pond rim extra (m)", "Pond",
		0.5, 3.5, 0.1, ROLLING)
	_add_float(rows, "pond_lip_rise_m", "Pond lip rise (m)", "Pond",
		0.0, 0.3, 0.01, ROLLING)
	_add_float(rows, "pond_lip_sigma_m", "Pond lip sigma (m)", "Pond",
		0.5, 2.5, 0.1, ROLLING)
	_add_float(rows, "pond_skirt_m", "Pond skirt (m)", "Pond",
		1.0, 4.0, 0.25, ROLLING)
	_add_float(rows, "pond_water_inset_m", "Pond water inset (m)", "Pond",
		0.03, 0.30, 0.01, ROLLING)

	# Plaza
	_add_float(rows, "plaza_relief_m", "Plaza relief (m)", "Plaza",
		-0.3, 0.3, 0.02, ROLLING, "0 = gentle flatten; must not block CamSun.")
	_add_float(rows, "plaza_skirt_m", "Plaza skirt (m)", "Plaza",
		1.0, 4.0, 0.25, ROLLING)

	# Knolls
	_add_int(rows, "knoll_count", "Knoll count", "Knolls",
		0, 5, 1, ROLLING)
	_add_float(rows, "knoll_height_m", "Knoll height (m)", "Knolls",
		0.1, 1.0, 0.05, ROLLING)
	_add_float(rows, "knoll_radius_m", "Knoll radius (m)", "Knolls",
		4.0, 12.0, 0.5, ROLLING)
	_add_float(rows, "knoll_min_sep_m", "Knoll min sep (m)", "Knolls",
		6.0, 20.0, 0.5, ROLLING)
	_add_float(rows, "knoll_hero_clear_m", "Knoll hero clear (m)", "Knolls",
		8.0, 20.0, 0.5, ROLLING)
	_add_float(rows, "knoll_sun_corridor_half_deg", "Sun corridor half (°)", "Knolls",
		15.0, 60.0, 1.0, ROLLING, "Reject knolls whose azimuth is within this of E/W sun horizons.")

	# Mesh
	_add_float(rows, "terrain_mesh_step_m", "Mesh cell (m)", "Mesh",
		1.0, 3.5, 0.25, ROLLING, "Cell size; 2 m ≈ 5k tris.")
	_add_float(rows, "normal_eps_m", "Normal eps (m)", "Mesh",
		0.1, 0.6, 0.05, ROLLING)

	# Consumer
	_add_bool(rows, "wanderer_follow_terrain", "Wanderer follows terrain", "Consumer",
		ROLLING, "A1: path-polyline vertices use sample_y.")
	_add_float(rows, "camera_ground_clearance_m", "Camera clearance (m)", "Consumer",
		0.1, 1.0, 0.05, ROLLING)

	# Material
	_add_bool(rows, "rim_tint_match_on", "Rim tint match", "Material",
		ALL_VARIANTS, "Match outer-hill albedo at rim (pairs with ivy-ska0.1).")

	return rows


# ── Row builders (mirror HillsKnobSpec helpers) ────────────────────────────────

static func _add_float(
		rows: Array[Dictionary], name: String, label: String, group: String,
		lo: float, hi: float, step: float, variants: Array,
		tip: String = "") -> void:
	rows.append({
		"name": name, "type": "float", "label": label, "group": group,
		"min": lo, "max": hi, "step": step, "variants": variants, "tip": tip,
	})


static func _add_int(
		rows: Array[Dictionary], name: String, label: String, group: String,
		lo: int, hi: int, step: int, variants: Array,
		tip: String = "") -> void:
	rows.append({
		"name": name, "type": "float", "label": label, "group": group,
		"min": float(lo), "max": float(hi), "step": float(step),
		"variants": variants, "tip": tip, "is_int": true,
	})


static func _add_bool(
		rows: Array[Dictionary], name: String, label: String, group: String,
		variants: Array, tip: String = "") -> void:
	rows.append({
		"name": name, "type": "bool", "label": label, "group": group,
		"variants": variants, "tip": tip,
	})
