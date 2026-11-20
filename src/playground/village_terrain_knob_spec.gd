## VillageTerrainKnobSpec — knob table for the village terrain playground (schema v2).
## Exactly the SD-VILLAGE-TERRAIN-22 knobs, defaults == VillageTerrainParams.production(), each with
## a regen class (AR-LF-D11): "material" (uniforms only), "consumer" (nothing rebuilt), "terrain"
## (field + meshes rebuilt, same layout), "layout" (VillageLayout.generate(seed, params) again).
class_name VillageTerrainKnobSpec
extends RefCounted

const VARIANT_LABELS := [
	"0 — Landscape (production)",
	"1 — Flat (A/B)",
]

const VARIANT_DESCRIPTIONS := [
	"Broad rolling landform, village fitted into it; lawn and far hills are one field.",
	"Flat lawn (sample_y ≡ 0) and flat legacy hills — the A/B baseline (INV-15).",
]

## landform_noise selector (structurally different algorithms inside variant 0).
const NOISE_LABELS := [
	"fbm (production)",
	"billow",
	"derivative-damped",
	"ridged (comparison only)",
]

const OFFSET_MODE_LABELS := ["auto (search)", "manual"]

const VARIANT_HELP := "Variant: Landscape (production) vs Flat (A/B)."
const PRESET_HELP := "Preset = full recipe; Reset restores production defaults."

const ALL_VARIANTS := [0, 1]
const LANDSCAPE := [0]

const REGEN_MATERIAL := "material"
const REGEN_CONSUMER := "consumer"
const REGEN_TERRAIN := "terrain"
const REGEN_LAYOUT := "layout"


static func all_knobs() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var L := REGEN_LAYOUT
	var T := REGEN_TERRAIN

	# Stage
	_add_int(rows, "layout_seed", "Layout seed", "Stage", 1, 999999999, 1, ALL_VARIANTS, L,
		"VillageLayout.generate(seed, params).")
	_add_int(rows, "variant", "Variant", "Stage", 0, 1, 1, ALL_VARIANTS, L, VARIANT_HELP)

	# Landform (SD-17 §1)
	_add_int(rows, "landform_noise", "Noise type", "Landform", 0, 3, 1, LANDSCAPE, L,
		"0 fbm (production), 1 billow, 2 derivative-damped, 3 ridged (comparison only).")
	_add_float(rows, "landform_wavelength_m", "Wavelength (m)", "Landform", 120.0, 400.0, 5.0, LANDSCAPE, L,
		"Hill footprint; bigger than the 92 m village disc.")
	_add_float(rows, "landform_height_m", "Height (m)", "Landform", 0.0, 30.0, 0.5, LANDSCAPE, L,
		"Full 0..1 noise scale; 0 = no landform (detail + far ridges only).")
	_add_int(rows, "landform_octaves", "Octaves", "Landform", 1, 4, 1, LANDSCAPE, L)
	_add_float(rows, "landform_persistence", "Persistence", "Landform", 0.3, 0.7, 0.02, LANDSCAPE, L)
	_add_float(rows, "landform_warp", "Domain warp", "Landform", 0.0, 0.4, 0.01, LANDSCAPE, L)
	_add_float(rows, "landform_ddf_k", "DDF damping k", "Landform", 0.0, 2.0, 0.05, LANDSCAPE, L,
		"Derivative-damped noise only.")

	# Placement / offset search (SD-18)
	_add_int(rows, "landform_offset_mode", "Offset mode", "Placement", 0, 1, 1, LANDSCAPE, L,
		"0 auto (search), 1 manual (uses the offset / rotation below).")
	_add_float(rows, "landform_offset_x", "Offset x (m)", "Placement", -2000.0, 2000.0, 1.0, LANDSCAPE, L,
		"Manual mode; auto writes the chosen offset back for copy-out.")
	_add_float(rows, "landform_offset_z", "Offset z (m)", "Placement", -2000.0, 2000.0, 1.0, LANDSCAPE, L)
	_add_float(rows, "landform_rot_deg", "Rotation (°)", "Placement", 0.0, 360.0, 1.0, LANDSCAPE, L)
	_add_int(rows, "landform_offset_candidates", "Candidates", "Placement", 16, 256, 1, LANDSCAPE, L)
	_add_float(rows, "storey_ground_m", "Storey ground (m)", "Placement", 2.0, 6.0, 0.25, LANDSCAPE, L,
		"Height off the hero pad that counts as 'a storey up or down' (SD-28 storey rule).")
	_add_float(rows, "storey_ground_frac_min", "Storey ground min share", "Placement", 0.0, 0.4, 0.01, LANDSCAPE, L,
		"Offsets with at least this share of buildable ground a storey off the hero are tried first. 0 = off.")
	_add_float(rows, "hero_site_slope_min_deg", "Hero slope min (°)", "Placement", 0.0, 6.0, 0.25, LANDSCAPE, L)
	_add_float(rows, "hero_site_slope_max_deg", "Hero slope max (°)", "Placement", 4.0, 14.0, 0.25, LANDSCAPE, L)
	_add_float(rows, "hero_not_crest_m", "Not a crest (m)", "Placement", 0.0, 5.0, 0.1, LANDSCAPE, L,
		"Land must rise this much somewhere within 40 m of the hero.")
	_add_float(rows, "hero_not_hollow_m", "Not a hollow (m)", "Placement", 0.0, 5.0, 0.1, LANDSCAPE, L,
		"Land must fall this much somewhere within 40 m of the hero.")
	_add_float(rows, "relief_span_min_m", "Village span min (m)", "Placement", 0.0, 15.0, 0.1, LANDSCAPE, L)
	_add_float(rows, "relief_span_target_m", "Village span target (m)", "Placement", 0.0, 15.0, 0.1, LANDSCAPE, L)
	_add_float(rows, "relief_span_max_m", "Village span max (m)", "Placement", 0.0, 15.0, 0.1, LANDSCAPE, L)
	_add_float(rows, "village_slope_p95_max_deg", "Village slope p95 max (°)", "Placement",
		8.0, 20.0, 0.5, LANDSCAPE, L)

	# Detail (SD-17 §2)
	_add_float(rows, "base_amplitude_m", "Detail amplitude (m)", "Detail", 0.0, 0.8, 0.01, LANDSCAPE, L)
	_add_float(rows, "base_feature_m", "Detail wavelength (m)", "Detail", 12.0, 80.0, 1.0, LANDSCAPE, L)
	_add_int(rows, "noise_octaves", "Detail octaves", "Detail", 1, 5, 1, LANDSCAPE, L)
	_add_float(rows, "noise_persistence", "Detail persistence", "Detail", 0.3, 0.7, 0.02, LANDSCAPE, L)
	_add_float(rows, "warp_strength", "Detail warp", "Detail", 0.0, 0.6, 0.02, LANDSCAPE, L)

	# Far ridges (SD-17 §3)
	_add_float(rows, "far_ridge_start_m", "Ridge start (m)", "Far ridges", 56.0, 120.0, 1.0, LANDSCAPE, T,
		"North ridge Rg ramps in from here (ridge shape: hills playground).")
	_add_float(rows, "far_ridge_full_m", "Ridge full (m)", "Far ridges", 80.0, 160.0, 1.0, LANDSCAPE, T)

	# Sun corridor (SD-17 §4)
	_add_float(rows, "sun_corridor_half_deg", "Sun corridor half (°)", "Sun", 10.0, 45.0, 1.0, LANDSCAPE, L,
		"About the Solar sunrise / sunset azimuths.")
	_add_float(rows, "sun_corridor_fade_deg", "Sun corridor fade (°)", "Sun", 5.0, 20.0, 0.5, LANDSCAPE, L)
	_add_float(rows, "sun_clear_deg", "Horizon clear angle (°)", "Sun", 0.0, 4.0, 0.1, LANDSCAPE, L)
	_add_float(rows, "sun_eye_height_m", "Eye height (m)", "Sun", 1.0, 4.0, 0.1, LANDSCAPE, L)
	_add_float(rows, "sun_cap_soft_m", "Cap softness (m)", "Sun", 0.5, 5.0, 0.1, LANDSCAPE, L)

	# Fit (SD-19)
	_add_float(rows, "ring_max_slope_deg", "Ring max slope (°)", "Fit", 12.0, 35.0, 0.5, LANDSCAPE, L)
	_add_float(rows, "max_site_slope_deg", "Cottage site max (°)", "Fit", 4.0, 16.0, 0.5, LANDSCAPE, L,
		"Cottage site rejection (plot sampler, WP2).")
	_add_float(rows, "hero_flat_r_m", "Hero flat radius (m)", "Fit", 5.0, 9.0, 0.25, LANDSCAPE, L)
	_add_float(rows, "hero_ring_min_m", "Hero ring min (m)", "Fit", 2.0, 8.0, 0.25, LANDSCAPE, L)
	_add_float(rows, "hero_ring_max_m", "Hero ring max (m)", "Fit", 6.0, 14.0, 0.25, LANDSCAPE, L)
	_add_float(rows, "pad_margin_m", "Pad margin (m)", "Fit", 0.2, 1.5, 0.1, LANDSCAPE, L)
	_add_float(rows, "pad_ring_min_m", "Pad ring min (m)", "Fit", 2.0, 6.0, 0.25, LANDSCAPE, L)
	_add_float(rows, "pad_ring_max_m", "Pad ring max (m)", "Fit", 6.0, 14.0, 0.25, LANDSCAPE, L)
	_add_float(rows, "pond_max_site_slope_deg", "Pond site max (°)", "Fit", 2.0, 10.0, 0.25, LANDSCAPE, L,
		"Pond site rejection (WP2).")
	_add_float(rows, "plaza_max_tilt_deg", "Plaza max tilt (°)", "Fit", 0.0, 10.0, 0.25, LANDSCAPE, L)
	_add_float(rows, "plaza_ring_m", "Plaza ring min (m)", "Fit", 2.0, 8.0, 0.25, LANDSCAPE, L)
	_add_float(rows, "plaza_ring_max_m", "Plaza ring max (m)", "Fit", 6.0, 14.0, 0.25, LANDSCAPE, L,
		"Plaza ring ladder maximum (offset search plaza_ring_ok).")

	# Pond basin (terrain class: same layout, field rebuilt)
	_add_float(rows, "pond_freeboard_m", "Pond freeboard (m)", "Pond", 0.05, 0.4, 0.01, LANDSCAPE, T,
		"Water level = lowest bank point − this.")
	_add_float(rows, "pond_depth_m", "Pond depth (m)", "Pond", -1.0, -0.2, 0.05, LANDSCAPE, T)
	_add_float(rows, "pond_floor_scale", "Pond floor scale", "Pond", 0.6, 1.4, 0.05, LANDSCAPE, T)
	_add_float(rows, "pond_rim_extra_m", "Pond rim extra (m)", "Pond", 0.5, 3.5, 0.1, LANDSCAPE, T)
	_add_float(rows, "pond_lip_rise_m", "Pond lip rise (m)", "Pond", 0.0, 0.3, 0.01, LANDSCAPE, T)
	_add_float(rows, "pond_lip_sigma_m", "Pond lip sigma (m)", "Pond", 0.5, 2.5, 0.1, LANDSCAPE, T)
	_add_float(rows, "pond_skirt_m", "Pond skirt (m)", "Pond", 1.0, 4.0, 0.25, LANDSCAPE, T)
	_add_float(rows, "pond_water_inset_m", "Pond water inset (m)", "Pond", 0.03, 0.30, 0.01, LANDSCAPE, T,
		"Kept from v1; the water level now follows the freeboard.")

	# Paths (SD-20)
	_add_float(rows, "max_path_slope_deg", "Max path slope (°)", "Paths", 8.0, 20.0, 0.5, LANDSCAPE, L,
		"Open-land path cap (in fit rings the ring rule applies).")
	_add_float(rows, "door_approach_m", "Door approach (m)", "Paths", 1.0, 5.0, 0.25, LANDSCAPE, L)
	_add_float(rows, "path_steep_accept_deg", "Path accept max (°)", "Paths", 14.0, 24.0, 0.5, LANDSCAPE, L,
		"Keep a rank's best over-cap layout (flagged) if its open-land max is at or under this.")
	_add_float(rows, "path_near_miss_deg", "Path near miss (°)", "Paths", 0.0, 4.0, 0.1, LANDSCAPE, L,
		"Accept at once (flagged) within this of the cap. 0 = no near-miss accept.")

	# Village (SD-21; consumed by the generator from WP3)
	_add_float(rows, "cottage_min_sep_m", "Cottage min spacing (m)", "Village", 8.0, 22.0, 0.5, LANDSCAPE, L,
		"Cottage centre spacing (SD-21, 16 m). Above ~18 m the path network runs out of sites.")
	_add_float(rows, "village_centre_r_max_m", "Village reach (m)", "Village", 37.0, 50.0, 0.5, LANDSCAPE, L,
		"Max cottage centre distance from G (WP3).")
	_add_float(rows, "sep_ladder_floor_m", "Spacing relax floor (m)", "Village", 8.0, 22.0, 0.5, LANDSCAPE, L,
		"If 8 do not fit, relax spacing 1 m at a time down to this (every attempt; clamped to the spacing).")
	_add_float(rows, "path_len_scale", "Path length scale", "Village", 0.8, 1.5, 0.05, LANDSCAPE, L,
		"Multiplies primary, branch and capacity path lengths (1.0 = production; longer = more sites, slower).")

	# Mesh
	_add_float(rows, "terrain_mesh_step_m", "Mesh cell (m)", "Mesh", 1.0, 3.5, 0.25, LANDSCAPE, T,
		"Lawn mesh cell; the join loop follows it. Coarsened in 0.25 m steps to fit the 16k tri cap (1 m -> 1.25 m at r_j 56).")
	_add_float(rows, "normal_eps_m", "Normal eps (m)", "Mesh", 0.1, 0.6, 0.05, LANDSCAPE, T)

	# Consumer
	_add_bool(rows, "wanderer_follow_terrain", "Wanderer follows terrain", "Consumer", LANDSCAPE,
		REGEN_CONSUMER, "Path-polyline vertices use sample_y.")
	_add_float(rows, "camera_ground_clearance_m", "Camera clearance (m)", "Consumer", 0.1, 1.0, 0.05,
		LANDSCAPE, REGEN_CONSUMER)

	# Material (terrain_tint.gdshaderinc, lawn + far hills)
	_add_float(rows, "ground_slope_dark", "Slope shading", "Material", 0.0, 1.0, 0.01, LANDSCAPE,
		REGEN_MATERIAL, "Albedo dim on slopes at the full-dim angle (0 = off).")
	_add_float(rows, "ground_slope_full_deg", "Slope full-dim (°)", "Material", 2.0, 40.0, 0.5, LANDSCAPE,
		REGEN_MATERIAL)
	_add_float(rows, "ground_height_tint", "Height tint", "Material", 0.0, 0.5, 0.01, LANDSCAPE,
		REGEN_MATERIAL, "Rises lighter / hollows darker, relative to the hero pad.")
	_add_float(rows, "ground_height_range_m", "Height tint range (m)", "Material", 0.2, 20.0, 0.1, LANDSCAPE,
		REGEN_MATERIAL, "Height above / below y_hero where the tint saturates.")

	# Ground look (ground_look.gdshaderinc, lawn + lit meadow ring; ivy-82zn.17.1)
	_add_bool(rows, "ground_tex_on", "Grass textures", "Ground look", LANDSCAPE, REGEN_MATERIAL,
		"Off = procedural colour only (production today). On = Grass005 lawn, Grass004 under trees.")
	_add_float(rows, "ground_tex_scale_m", "Texture tile (m)", "Ground look", 0.5, 12.0, 0.1, LANDSCAPE,
		REGEN_MATERIAL, "Ground size of one texture tile.")
	_add_float(rows, "ground_tex_strength", "Texture strength", "Ground look", 0.0, 1.0, 0.01, LANDSCAPE,
		REGEN_MATERIAL, "0 = procedural colour, 1 = texture colour.")
	_add_float(rows, "ground_tex_brightness", "Texture brightness", "Ground look", 0.3, 2.5, 0.01, LANDSCAPE,
		REGEN_MATERIAL)
	_add_float(rows, "ground_macro", "Large patches", "Ground look", 0.0, 1.5, 0.01, LANDSCAPE,
		REGEN_MATERIAL, "Procedural large-scale patches kept as brightness variation on the texture.")
	_add_float(rows, "ground_saturation", "Saturation", "Ground look", 0.0, 1.5, 0.01, LANDSCAPE,
		REGEN_MATERIAL, "Lawn, lit ring and far hills. 1 = as authored.")
	_add_float(rows, "ground_normal_strength", "Texture relief", "Ground look", 0.0, 2.0, 0.01, LANDSCAPE,
		REGEN_MATERIAL, "Normal-map strength.")
	_add_float(rows, "ground_shade_strength", "Under-tree texture", "Ground look", 0.0, 1.0, 0.01, LANDSCAPE,
		REGEN_MATERIAL, "Grass004 weight under a canopy.")
	_add_float(rows, "ground_shade_edge_lo", "Under-tree edge start", "Ground look", 0.0, 1.0, 0.01,
		LANDSCAPE, REGEN_MATERIAL, "Tree closeness (0 open, 1 trunk) where Grass004 starts.")
	_add_float(rows, "ground_shade_edge_hi", "Under-tree edge full", "Ground look", 0.0, 1.0, 0.01,
		LANDSCAPE, REGEN_MATERIAL, "Tree closeness where Grass004 is full.")

	_widen_experiment_ranges(rows)
	return rows


static func regen_class(name: String) -> String:
	for row: Dictionary in all_knobs():
		if row["name"] == name:
			return String(row["regen"])
	return REGEN_LAYOUT


## Experiment ranges (ivy-82zn.14.8) for the surviving relief knobs: the SD-22 range stays as
## gentle_min / gentle_max; the slider may go past it and the HUD lists every knob that does.
const EXPERIMENT_RANGES := {
	"landform_height_m": [0.0, 50.0],
	"base_amplitude_m": [0.0, 3.0],
	"max_path_slope_deg": [0.0, 45.0],
	"hero_flat_r_m": [0.0, 12.0],
	"pond_depth_m": [-4.0, 0.0],
	"pond_lip_rise_m": [0.0, 1.0],
	"pond_skirt_m": [0.0, 10.0],
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


## Knobs whose current value lies outside their gentle range. Empty at production defaults.
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


static func _fmt(v: float) -> String:
	return "%.2f" % v


# ── Row builders (mirror HillsKnobSpec helpers; + regen class) ─────────────────

static func _add_float(
		rows: Array[Dictionary], name: String, label: String, group: String,
		lo: float, hi: float, step: float, variants: Array, regen: String,
		tip: String = "") -> void:
	rows.append({
		"name": name, "type": "float", "label": label, "group": group,
		"min": lo, "max": hi, "step": step, "variants": variants, "tip": tip, "regen": regen,
	})


static func _add_int(
		rows: Array[Dictionary], name: String, label: String, group: String,
		lo: int, hi: int, step: int, variants: Array, regen: String,
		tip: String = "") -> void:
	rows.append({
		"name": name, "type": "float", "label": label, "group": group,
		"min": float(lo), "max": float(hi), "step": float(step),
		"variants": variants, "tip": tip, "is_int": true, "regen": regen,
	})


static func _add_bool(
		rows: Array[Dictionary], name: String, label: String, group: String,
		variants: Array, regen: String, tip: String = "") -> void:
	rows.append({
		"name": name, "type": "bool", "label": label, "group": group,
		"variants": variants, "tip": tip, "regen": regen,
	})
