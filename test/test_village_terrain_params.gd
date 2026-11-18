## ivy-82zn.14.14 (WP1) — VillageTerrainParams schema v2 (SD-VILLAGE-TERRAIN-22, AR-LF-PLAYGROUND):
## defaults == the SD table (G7 parity pin), removed v1 fields gone, v1 JSON loads, presets,
## field_signature ignores material / consumer knobs, every field has a knob row with a regen class.
extends GutTest

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const KnobSpec = preload("res://src/playground/village_terrain_knob_spec.gd")

## SD-VILLAGE-TERRAIN-22 production defaults.
const SD22_DEFAULTS := {
	"variant": 0,
	"landform_noise": 0, "landform_wavelength_m": 260.0, "landform_height_m": 16.0,
	"landform_octaves": 2, "landform_persistence": 0.5, "landform_warp": 0.10, "landform_ddf_k": 0.5,
	"landform_offset_mode": 0, "landform_rot_deg": 0.0, "landform_offset_candidates": 64,
	"hero_site_slope_min_deg": 2.0, "hero_site_slope_max_deg": 9.0,
	"hero_not_crest_m": 1.5, "hero_not_hollow_m": 1.5,
	"relief_span_min_m": 5.0, "relief_span_target_m": 6.5, "relief_span_max_m": 8.0,
	"village_slope_p95_max_deg": 14.0,
	"base_amplitude_m": 0.25, "base_feature_m": 40.0, "noise_octaves": 2, "noise_persistence": 0.40,
	"warp_strength": 0.16,
	"far_ridge_start_m": 70.0, "far_ridge_full_m": 100.0,
	"sun_corridor_half_deg": 25.0, "sun_corridor_fade_deg": 10.0, "sun_clear_deg": 1.5,
	"sun_eye_height_m": 2.0, "sun_cap_soft_m": 2.0,
	"ring_max_slope_deg": 22.0, "max_site_slope_deg": 10.0, "hero_flat_r_m": 7.0,
	"hero_ring_min_m": 4.0, "hero_ring_max_m": 10.0, "pad_margin_m": 0.6,
	"pad_ring_min_m": 3.0, "pad_ring_max_m": 9.0, "pond_max_site_slope_deg": 6.0,
	"pond_freeboard_m": 0.15, "pond_depth_m": -0.6, "pond_floor_scale": 1.0, "pond_rim_extra_m": 1.5,
	"pond_lip_rise_m": 0.12, "pond_lip_sigma_m": 1.2, "pond_skirt_m": 2.0, "pond_water_inset_m": 0.10,
	"plaza_max_tilt_deg": 6.0, "plaza_ring_m": 5.0, "plaza_ring_max_m": 10.0,
	"max_path_slope_deg": 14.0, "door_approach_m": 3.0,
	"path_steep_accept_deg": 18.0, "path_near_miss_deg": 1.0,
	"cottage_min_sep_m": 22.0, "village_centre_r_max_m": 46.0,
	"terrain_mesh_step_m": 2.0, "normal_eps_m": 0.35,
	"wanderer_follow_terrain": true, "camera_ground_clearance_m": 0.35,
	"ground_slope_dark": 0.35, "ground_slope_full_deg": 30.0, "ground_height_tint": 0.12,
	"ground_height_range_m": 8.0,
}

## SD-22 "Removed fields" (plus the v1 hill / knoll / swell groups).
const REMOVED := [
	"hill_rise_m", "hill_shoulder", "hill_falloff_pow", "hill_centre_shift", "hill_crest_extra_m",
	"hill_end_margin_m", "plaza_hill_follow", "hill_bank_max_deg",
	"knoll_count", "knoll_height_m", "knoll_radius_m", "knoll_min_sep_m", "knoll_hero_clear_m",
	"knoll_path_clear_m", "knoll_pad_clear_m", "knoll_sun_corridor_half_deg",
	"swell_amp_m", "swell_feature_m", "swell_hero_fade_m", "swell_rim_fade_m", "swell_sun_corridor_gain",
	"rim_blend_m", "rim_eps_m", "max_rise_m", "max_depression_m", "center_bias_gain", "dir_bias_gain",
	"dir_bias_phi_deg", "hero_skirt_m", "pad_skirt_m", "pad_edge_slope_max_deg",
	"open_lawn_pad_quiet_m", "open_lawn_pad_fade_m", "hero_relief_fade_m", "plaza_relief_fade_m",
	"pond_relief_fade_m", "plaza_relief_m", "plaza_skirt_m", "rim_tint_match_on",
]


func test_schema_is_v2() -> void:
	assert_eq(VillageTerrainParams.SCHEMA, "village_terrain_playground.v2")


func test_production_defaults_match_sd22() -> void:
	var p := VillageTerrainParams.production()
	for key in SD22_DEFAULTS:
		var want: Variant = SD22_DEFAULTS[key]
		if typeof(want) == TYPE_FLOAT:
			assert_almost_eq(float(p.get(key)), float(want), 1e-6, "default %s" % key)
		else:
			assert_eq(p.get(key), want, "default %s" % key)


func test_removed_v1_fields_are_gone() -> void:
	var d := VillageTerrainParams.production().to_dict()
	for key in REMOVED:
		assert_false(d.has(key), "%s removed" % key)


func test_v1_json_loads_and_ignores_removed_fields() -> void:
	var v1 := {
		"schema": "village_terrain_playground.v1",
		"variant": 0,
		"knobs": {"hill_rise_m": 8.5, "knoll_count": 2, "base_amplitude_m": 0.4, "hero_flat_r_m": 6.5,
			"rim_blend_m": 5.0, "pond_depth_m": -0.5},
	}
	var p := VillageTerrainParams.production()
	p.from_dict(JSON.parse_string(JSON.stringify(v1)))
	assert_almost_eq(p.base_amplitude_m, 0.4, 1e-6, "surviving field loaded")
	assert_almost_eq(p.hero_flat_r_m, 6.5, 1e-6, "surviving field loaded")
	assert_almost_eq(p.pond_depth_m, -0.5, 1e-6, "surviving field loaded")
	assert_false(p.to_dict().has("hill_rise_m"), "removed field not resurrected")


func test_v2_copy_out_round_trips() -> void:
	var p := VillageTerrainParams.production()
	p.landform_noise = 1
	p.landform_height_m = 12.5
	p.landform_offset_mode = VillageTerrainParams.OFFSET_MANUAL
	p.landform_offset_x = 140.0
	var block := p.to_json_block()
	var parsed: Dictionary = JSON.parse_string(block)
	assert_eq(parsed["schema"], VillageTerrainParams.SCHEMA, "copy-out schema v2")
	var q := VillageTerrainParams.production()
	q.from_dict(parsed)
	assert_true(q.matches_preset(p), "round trip")
	assert_almost_eq(q.landform_offset_x, 140.0, 1e-6, "manual offset round trips")


func test_presets_without_old_hill() -> void:
	var names := VillageTerrainParams.ordered_preset_names()
	for want in ["Production", "Flat (A/B)", "Gentle", "Bold", "Billow", "Derivative-damped",
			"Ridged (comparison)", "Tight village (old spacing)"]:
		assert_true(want in names, "preset %s" % want)
	for n in names:
		assert_false(String(n).to_lower().contains("hill"), "no village-on-a-hill preset (AR-LF-D2)")
	var p := VillageTerrainParams.production()
	p.apply_preset("Bold")
	assert_almost_eq(p.landform_height_m, 22.0, 1e-6, "Bold height")
	assert_almost_eq(p.landform_wavelength_m, 220.0, 1e-6, "Bold wavelength")
	assert_eq(VillageTerrainParams.detect_preset_name(p), "Bold", "detect Bold")
	p.apply_preset("Flat (A/B)")
	assert_eq(p.variant, 1, "Flat (A/B) is variant 1")
	p.apply_preset("Production")
	assert_eq(VillageTerrainParams.detect_preset_name(p), "Production", "back to production")
	p.ground_height_tint = 0.3
	assert_eq(VillageTerrainParams.detect_preset_name(p), "Custom", "edit → Custom")


func test_reset_keeps_layout_seed() -> void:
	var p := VillageTerrainParams.production()
	p.layout_seed = 12
	p.landform_height_m = 3.0
	p.variant = 1
	p.reset_to_production()
	assert_eq(p.layout_seed, 12, "seed kept")
	assert_eq(p.variant, 0, "variant reset")
	assert_almost_eq(p.landform_height_m, 16.0, 1e-6, "field reset")


func test_field_signature_ignores_material_and_consumer() -> void:
	var p := VillageTerrainParams.production()
	var s0 := p.field_signature()
	p.ground_slope_dark = 0.9
	p.ground_height_tint = 0.4
	p.camera_ground_clearance_m = 0.8
	p.wanderer_follow_terrain = false
	p.layout_seed = 99
	assert_eq(p.field_signature(), s0, "material / consumer / seed edits keep the signature")
	p.landform_height_m = 9.0
	assert_ne(p.field_signature(), s0, "terrain edit changes the signature")


func test_every_param_has_a_knob_row_with_regen() -> void:
	var rows := KnobSpec.all_knobs()
	var names := {}
	for row: Dictionary in rows:
		names[row["name"]] = row
		assert_true(String(row.get("regen", "")) in ["material", "consumer", "terrain", "layout"],
			"%s regen class" % row["name"])
	for key in VillageTerrainParams.production().to_dict():
		assert_true(names.has(key), "knob row for %s" % key)
	for key in SD22_DEFAULTS:
		assert_true(names.has(key), "SD-22 knob %s present" % key)
	assert_eq(String(names["ground_slope_dark"]["regen"]), "material", "material class")
	assert_eq(String(names["camera_ground_clearance_m"]["regen"]), "consumer", "consumer class")
	assert_eq(String(names["far_ridge_start_m"]["regen"]), "terrain", "terrain class")
	assert_eq(String(names["landform_height_m"]["regen"]), "layout", "layout class")


func test_production_defaults_inside_slider_ranges() -> void:
	var p := VillageTerrainParams.production()
	for row: Dictionary in KnobSpec.all_knobs():
		if row["type"] != "float":
			continue
		var v := float(p.get(row["name"]))
		var lo := float(row.get("gentle_min", row["min"]))
		var hi := float(row.get("gentle_max", row["max"]))
		assert_between(v, lo, hi, "%s default inside its gentle range" % row["name"])
	assert_eq(KnobSpec.gentle_limit_violations(p).size(), 0, "no gentle-range violations at production")
