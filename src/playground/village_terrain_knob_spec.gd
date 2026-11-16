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
		0.0, 2.0, 0.01, ROLLING, "Peak h; 0 = flat base field.")
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
		0.2, 2.5, 0.05, ROLLING)
	_add_float(rows, "max_depression_m", "Max depression (m)", "Caps",
		0.2, 1.5, 0.05, ROLLING)
	## ivy-82zn.14.10: gentle 4-12 → 4-24 (production 18° on the village hill).
	_add_float(rows, "max_path_slope_deg", "Max path slope (°)", "Caps",
		4.0, 24.0, 0.5, ROLLING)

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

	# Open-lawn relief envelope (ivy-82zn.14.1)
	_add_float(rows, "open_lawn_pad_quiet_m", "Pad quiet band (m)", "Relief envelope",
		0.0, 6.0, 0.25, ROLLING, "Relief fully quiet within this of a pad.")
	_add_float(rows, "open_lawn_pad_fade_m", "Pad relief fade (m)", "Relief envelope",
		2.0, 20.0, 0.5, ROLLING, "Relief ramps to full over this beyond the pad quiet band.")
	_add_float(rows, "hero_relief_fade_m", "Hero relief fade (m)", "Relief envelope",
		2.0, 20.0, 0.5, ROLLING, "Relief ramps to full over this beyond the hero flat disc.")
	_add_float(rows, "plaza_relief_fade_m", "Plaza relief fade (m)", "Relief envelope",
		2.0, 20.0, 0.5, ROLLING)
	_add_float(rows, "pond_relief_fade_m", "Pond relief fade (m)", "Relief envelope",
		2.0, 20.0, 0.5, ROLLING)

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
		0.1, 2.5, 0.05, ROLLING)
	_add_float(rows, "knoll_radius_m", "Knoll radius (m)", "Knolls",
		4.0, 24.0, 0.5, ROLLING)
	_add_float(rows, "knoll_min_sep_m", "Knoll min sep (m)", "Knolls",
		6.0, 40.0, 0.5, ROLLING)
	_add_float(rows, "knoll_hero_clear_m", "Knoll hero clear (m)", "Knolls",
		8.0, 40.0, 0.5, ROLLING)
	_add_float(rows, "knoll_path_clear_m", "Knoll path clear (m)", "Knolls",
		2.0, 30.0, 0.5, ROLLING, "Min distance from a mound centre to any path.")
	_add_float(rows, "knoll_pad_clear_m", "Knoll pad clear (m)", "Knolls",
		2.0, 30.0, 0.5, ROLLING, "Min distance from a mound centre to any cottage pad.")
	_add_float(rows, "knoll_sun_corridor_half_deg", "Sun corridor half (°)", "Knolls",
		15.0, 60.0, 1.0, ROLLING, "Reject knolls whose azimuth is within this of E/W sun horizons.")

	# Village hill (ivy-82zn.14.10): ranges are the experiment ranges (no gentle limits).
	_add_float(rows, "hill_rise_m", "Hill rise (m)", "Village hill",
		0.0, 17.0, 0.1, ROLLING,
		"Hero crest above the village edge; tallest cottage ridge 6.84 m (0 = no hill).")
	_add_float(rows, "hill_shoulder", "Hill shoulder", "Village hill",
		0.0, 1.0, 0.05, ROLLING, "0 = straight cone, 1 = smoothstep (flat crest shoulder, soft toe).")
	_add_float(rows, "hill_falloff_pow", "Hill falloff power", "Village hill",
		0.5, 3.0, 0.05, ROLLING, ">1 broad crown then a steep toe, <1 quick drop then a long toe.")
	_add_float(rows, "hill_centre_shift", "Hill centre shift", "Village hill",
		0.0, 0.6, 0.02, ROLLING, "Moves the hill top from the hero toward the hamlet centre.")
	_add_float(rows, "hill_crest_extra_m", "Hill crest extra (m)", "Village hill",
		0.0, 15.0, 0.25, ROLLING, "Flat crest beyond the hero disc + skirt.")
	_add_float(rows, "hill_end_margin_m", "Hill end margin (m)", "Village hill",
		-10.0, 20.0, 0.5, ROLLING, "Where the fall ends past the farthest cottage (negative: inside).")
	_add_float(rows, "plaza_hill_follow", "Plaza follows hill", "Village hill",
		0.0, 1.0, 0.05, ROLLING, "1 = plaza tilts with the hill, 0 = level terrace with banks.")
	_add_float(rows, "hill_bank_max_deg", "Terrace bank max (°)", "Village hill",
		10.0, 45.0, 0.5, ROLLING, "Steepest bank a cottage pad / pond / level plaza cuts into the hill.")

	# Village swell (ivy-82zn.14.1)
	_add_float(rows, "swell_amp_m", "Swell amplitude (m)", "Village swell",
		0.0, 1.5, 0.05, ROLLING, "Gentle field the pads, plaza, pond and paths ride (0 = off).")
	_add_float(rows, "swell_feature_m", "Swell wavelength (m)", "Village swell",
		40.0, 200.0, 5.0, ROLLING, "Longer = gentler; one octave, no warp.")
	_add_float(rows, "swell_hero_fade_m", "Swell hero fade (m)", "Village swell",
		2.0, 30.0, 0.5, ROLLING, "Ramp from the hero disc + skirt to full swell.")
	_add_float(rows, "swell_rim_fade_m", "Swell rim fade (m)", "Village swell",
		2.0, 30.0, 0.5, ROLLING, "Ramp to 0 before the lawn-edge rim band.")
	_add_float(rows, "swell_sun_corridor_gain", "Swell in sun corridors", "Village swell",
		0.0, 1.0, 0.05, ROLLING, "Swell scale inside the E/W sun corridors (1 = no effect).")

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
	_add_float(rows, "ground_slope_dark", "Slope shading", "Material",
		0.0, 1.0, 0.01, ROLLING, "Albedo dim on slopes at the full-dim angle (0 = off).")
	_add_float(rows, "ground_slope_full_deg", "Slope full-dim (°)", "Material",
		2.0, 30.0, 0.5, ROLLING, "Slope angle where the full slope shading applies.")
	_add_float(rows, "ground_height_tint", "Height tint", "Material",
		0.0, 0.5, 0.01, ROLLING, "Rises lighter / hollows darker by this fraction (0 = off).")
	## ivy-82zn.14.10: 0.2-3 → 0.2-17 (production 8.5 = the hill rise).
	_add_float(rows, "ground_height_range_m", "Height tint range (m)", "Material",
		0.2, 17.0, 0.05, ROLLING, "Height above/below the rim datum where the tint saturates.")

	_widen_experiment_ranges(rows)
	return rows


## ivy-82zn.14.8: experimentation ranges for the relief-shaping knobs. The row's previous range
## stays as gentle_min / gentle_max (the limits production was tuned inside); the slider may go
## past them, and the playground HUD lists every knob that does (gentle_limit_violations).
const EXPERIMENT_RANGES := {
	"base_amplitude_m": [0.0, 6.0],
	"center_bias_gain": [0.0, 4.0],
	"max_rise_m": [0.0, 8.0],
	"max_depression_m": [0.0, 6.0],
	"max_path_slope_deg": [0.0, 45.0],
	"hero_flat_r_m": [0.0, 12.0],
	"hero_skirt_m": [0.0, 10.0],
	"pad_skirt_m": [0.0, 8.0],
	"pad_edge_slope_max_deg": [0.0, 45.0],
	"open_lawn_pad_quiet_m": [0.0, 40.0],
	## ivy-82zn.14.10: relief fades floored at 1 m (VillageTerrain.RELIEF_FADE_FLOOR_M); 0 was a cliff.
	"open_lawn_pad_fade_m": [1.0, 40.0],
	"hero_relief_fade_m": [1.0, 40.0],
	"plaza_relief_fade_m": [1.0, 40.0],
	"pond_relief_fade_m": [1.0, 40.0],
	"pond_depth_m": [-4.0, 0.0],
	"pond_lip_rise_m": [0.0, 1.0],
	"pond_skirt_m": [0.0, 10.0],
	"plaza_relief_m": [-2.0, 2.0],
	"plaza_skirt_m": [0.0, 10.0],
	"knoll_count": [0.0, 12.0],
	"knoll_height_m": [0.0, 6.0],
	"knoll_radius_m": [2.0, 40.0],
	"knoll_hero_clear_m": [0.0, 40.0],
	"knoll_path_clear_m": [0.0, 30.0],
	"knoll_pad_clear_m": [0.0, 30.0],
	"swell_amp_m": [0.0, 5.0],
	"swell_hero_fade_m": [0.0, 40.0],
	"swell_rim_fade_m": [0.0, 40.0],
}


static func _widen_experiment_ranges(rows: Array[Dictionary]) -> void:
	for row: Dictionary in rows:
		var name: String = row["name"]
		if not EXPERIMENT_RANGES.has(name):
			continue
		var wide: Array = EXPERIMENT_RANGES[name]
		row["gentle_min"] = row["min"]
		row["gentle_max"] = row["max"]
		row["min"] = minf(float(row["min"]), float(wide[0]))
		row["max"] = maxf(float(row["max"]), float(wide[1]))
		var tip := String(row.get("tip", ""))
		var gentle := "Gentle: %s to %s." % [_fmt(float(row["gentle_min"])), _fmt(float(row["gentle_max"]))]
		row["tip"] = gentle if tip.is_empty() else "%s %s" % [tip, gentle]


## Knobs whose current value lies outside their gentle range, e.g.
## "base_amplitude_m 5.00 > gentle max 2.00". Empty at production defaults.
static func gentle_limit_violations(params: Resource) -> PackedStringArray:
	var out := PackedStringArray()
	for row: Dictionary in all_knobs():
		if not row.has("gentle_min"):
			continue
		var v := float(params.get(row["name"]))
		var lo := float(row["gentle_min"])
		var hi := float(row["gentle_max"])
		if v < lo - 1e-6:
			out.append("%s %s < gentle min %s" % [row["name"], _fmt(v), _fmt(lo)])
		elif v > hi + 1e-6:
			out.append("%s %s > gentle max %s" % [row["name"], _fmt(v), _fmt(hi)])
	return out


## Knobs the final sample_y clamp (-max_depression_m .. max_rise_m, VillageTerrain._apply_stamps)
## cuts short: a pond deeper than max_depression_m or a plaza raised / sunk past the caps.
static func relief_cap_notes(params: Resource) -> PackedStringArray:
	var out := PackedStringArray()
	var depth := -float(params.get("pond_depth_m"))
	var max_dep := float(params.get("max_depression_m"))
	var max_rise := float(params.get("max_rise_m"))
	var plaza := float(params.get("plaza_relief_m"))
	if depth > max_dep + 0.05:
		out.append("pond_depth_m %s clamped by max_depression_m %s" % [_fmt(-depth), _fmt(max_dep)])
	if plaza > max_rise + 0.05:
		out.append("plaza_relief_m %s clamped by max_rise_m %s" % [_fmt(plaza), _fmt(max_rise)])
	elif -plaza > max_dep + 0.05:
		out.append("plaza_relief_m %s clamped by max_depression_m %s" % [_fmt(plaza), _fmt(max_dep)])
	return out


static func _fmt(v: float) -> String:
	return "%.2f" % v


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
