## Tests for VillageTerrainParams schema, defaults, round-trips, and presets.
## Maps to AR-VT-TESTS / SD-VILLAGE-TERRAIN-2.
extends GutTest

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrainKnobSpec = preload("res://src/playground/village_terrain_knob_spec.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")
const VillageLayout = preload("res://src/world/village_layout.gd")


func test_production_defaults_variant() -> void:
	var p := VillageTerrainParams.production()
	assert_not_null(p, "production() returns non-null")
	assert_eq(p.variant, 0, "default variant=0 (rolling)")


func test_production_defaults_layout_seed() -> void:
	var p := VillageTerrainParams.production()
	assert_eq(p.layout_seed, 7, "default layout_seed=7")


func test_production_defaults_base_fields() -> void:
	var p := VillageTerrainParams.production()
	assert_almost_eq(p.base_amplitude_m, 0.64, 0.001, "base_amplitude_m=0.64")
	assert_almost_eq(p.base_feature_m, 48.0, 0.001, "base_feature_m=48.0")
	assert_eq(p.noise_octaves, 2, "noise_octaves=2")
	assert_almost_eq(p.noise_persistence, 0.4, 0.001, "noise_persistence=0.4")
	assert_almost_eq(p.warp_strength, 0.16, 0.001, "warp_strength=0.16")
	assert_almost_eq(p.center_bias_gain, 1.10, 0.001, "center_bias_gain=1.10")
	assert_almost_eq(p.dir_bias_gain, 0.0, 0.001, "dir_bias_gain=0.0")


func test_production_defaults_hero_fields() -> void:
	var p := VillageTerrainParams.production()
	assert_almost_eq(p.hero_flat_r_m, 7.0, 0.001, "hero_flat_r_m=7.0")
	assert_almost_eq(p.hero_skirt_m, 3.0, 0.001, "hero_skirt_m=3.0")


func test_production_defaults_caps() -> void:
	var p := VillageTerrainParams.production()
	assert_almost_eq(p.max_rise_m, 0.8, 0.001, "max_rise_m=0.8")
	assert_almost_eq(p.max_depression_m, 0.6, 0.001, "max_depression_m=0.6")
	assert_almost_eq(p.max_path_slope_deg, 8.0, 0.001, "max_path_slope_deg=8.0")


func test_production_defaults_pond_fields() -> void:
	var p := VillageTerrainParams.production()
	assert_almost_eq(p.pond_depth_m, -0.6, 0.001, "pond_depth_m=-0.6")
	assert_almost_eq(p.pond_lip_rise_m, 0.12, 0.001, "pond_lip_rise_m=0.12")
	assert_almost_eq(p.pond_water_inset_m, 0.10, 0.001, "pond_water_inset_m=0.10")


func test_production_defaults_knoll_fields() -> void:
	var p := VillageTerrainParams.production()
	assert_eq(p.knoll_count, 2, "knoll_count=2")
	assert_almost_eq(p.knoll_height_m, 0.70, 0.001, "knoll_height_m=0.70")
	assert_almost_eq(p.knoll_radius_m, 12.0, 0.001, "knoll_radius_m=12.0")
	assert_almost_eq(p.knoll_sun_corridor_half_deg, 35.0, 0.001, "knoll_sun_corridor_half_deg=35.0")


func test_schema_constant() -> void:
	assert_eq(VillageTerrainParams.SCHEMA, "village_terrain_playground.v1", "SCHEMA constant")


func test_preset_production_constant() -> void:
	assert_eq(VillageTerrainParams.PRESET_PRODUCTION, "Production", "PRESET_PRODUCTION constant")


func test_to_dict_has_expected_keys() -> void:
	var p := VillageTerrainParams.production()
	var d := p.to_dict()
	assert_true(d.has("variant"), "dict has variant")
	assert_true(d.has("base_amplitude_m"), "dict has base_amplitude_m")
	assert_true(d.has("hero_flat_r_m"), "dict has hero_flat_r_m")
	assert_true(d.has("knoll_count"), "dict has knoll_count")
	assert_true(d.has("pond_depth_m"), "dict has pond_depth_m")


func test_from_dict_round_trip() -> void:
	var p := VillageTerrainParams.production()
	var d := p.to_dict()
	var p2 := VillageTerrainParams.production()
	p2.base_amplitude_m = 0.55  # mutate first
	p2.from_dict(d)
	assert_almost_eq(p2.base_amplitude_m, 0.64, 0.001, "from_dict restores base_amplitude_m")
	assert_eq(p2.variant, 0, "from_dict restores variant")


func test_to_json_block_parses() -> void:
	var p := VillageTerrainParams.production()
	var json_str := p.to_json_block()
	assert_false(json_str.is_empty(), "json block is non-empty")
	var parsed: Variant = JSON.parse_string(json_str)
	assert_not_null(parsed, "JSON parses successfully")
	var parsed_dict := parsed as Dictionary
	assert_not_null(parsed_dict, "JSON parsed as Dictionary")
	assert_eq(parsed_dict.get("schema", ""), VillageTerrainParams.SCHEMA, "schema key in JSON")
	assert_true(parsed_dict.has("knobs"), "JSON has knobs key")


func test_to_json_block_knobs_has_fields() -> void:
	var p := VillageTerrainParams.production()
	var parsed: Variant = JSON.parse_string(p.to_json_block())
	var parsed_dict := parsed as Dictionary
	var knobs: Dictionary = parsed_dict["knobs"]
	assert_true(knobs.has("base_amplitude_m"), "knobs has base_amplitude_m")
	assert_false(knobs.has("variant"), "variant is top-level, not in knobs")


func test_duplicate_params_copies_values() -> void:
	var p := VillageTerrainParams.production()
	p.base_amplitude_m = 0.55
	var p2 := p.duplicate_params()
	assert_almost_eq(p2.base_amplitude_m, 0.55, 0.001, "duplicate copies values")


func test_duplicate_params_is_independent() -> void:
	var p := VillageTerrainParams.production()
	p.base_amplitude_m = 0.55
	var p2 := p.duplicate_params()
	p.base_amplitude_m = 0.1
	assert_almost_eq(p2.base_amplitude_m, 0.55, 0.001, "duplicate is independent of original")


func test_reset_to_production_restores_defaults() -> void:
	var p := VillageTerrainParams.production()
	p.base_amplitude_m = 0.55
	p.layout_seed = 42
	p.reset_to_production()
	assert_almost_eq(p.base_amplitude_m, 0.64, 0.001, "reset restores base_amplitude_m")


func test_reset_to_production_preserves_layout_seed() -> void:
	var p := VillageTerrainParams.production()
	p.layout_seed = 42
	p.reset_to_production()
	assert_eq(p.layout_seed, 42, "reset preserves layout_seed")


func test_matches_preset_production_matches_itself() -> void:
	var p := VillageTerrainParams.production()
	assert_true(p.matches_preset(VillageTerrainParams.production()), "production matches itself")


func test_matches_preset_detects_mismatch() -> void:
	var p := VillageTerrainParams.production()
	p.base_amplitude_m = 0.55
	assert_false(p.matches_preset(VillageTerrainParams.production()), "modified does not match production")


func test_presets_exist() -> void:
	var ps: Dictionary = VillageTerrainParams.presets()
	assert_true(ps.has("Production"), "Production preset exists")
	assert_true(ps.has("Flat legacy"), "Flat legacy preset exists")
	assert_true(ps.has("High relief"), "High relief preset exists")


func test_apply_preset_flat_legacy() -> void:
	var p := VillageTerrainParams.production()
	p.apply_preset("Flat legacy")
	assert_eq(p.variant, 1, "Flat legacy → variant=1")


func test_apply_preset_high_relief() -> void:
	var p := VillageTerrainParams.production()
	p.apply_preset("High relief")
	assert_eq(p.variant, 2, "High relief → variant=2")
	assert_eq(p.knoll_count, 4, "High relief adds knolls")


func test_apply_preset_production_resets() -> void:
	var p := VillageTerrainParams.production()
	p.base_amplitude_m = 0.55
	p.apply_preset("Production")
	assert_almost_eq(p.base_amplitude_m, 0.64, 0.001, "apply Production resets amplitude")


func test_production_knobs_within_slider_bounds() -> void:
	var p := VillageTerrainParams.production()
	for row: Dictionary in VillageTerrainKnobSpec.all_knobs():
		var prop: String = row["name"]
		if not prop in p:
			continue
		var v: Variant = p.get(prop)
		match row["type"]:
			"float":
				var lo: float = row["min"]
				var hi: float = row["max"]
				var step: float = row["step"]
				var f: float = float(v)
				assert_gte(f, lo - 1e-4, "production %s=%s below knob min %s" % [prop, v, lo])
				assert_lte(f, hi + 1e-4, "production %s=%s above knob max %s" % [prop, v, hi])
				var steps := roundf((f - lo) / step)
				var snapped := lo + steps * step
				assert_almost_eq(f, snapped, step * 0.51,
					"production %s=%s must align to knob step %s" % [prop, v, step])
			"int":
				var lo_i: int = row["min"]
				var hi_i: int = row["max"]
				var i: int = int(v)
				assert_gte(i, lo_i, "production %s below min" % prop)
				assert_lte(i, hi_i, "production %s above max" % prop)


func test_knoll_centres_cache_invalidates_on_knob_edit() -> void:
	var layout := VillageLayout.generate(7)
	var p := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, p)
	var n0 := VillageTerrain.knoll_centres(layout, p, t_seed).size()
	assert_gt(n0, 0, "seed 7 must place knolls for cache test")
	p.knoll_count = 0
	assert_eq(VillageTerrain.knoll_centres(layout, p, t_seed).size(), 0,
		"knoll_count knob must miss cache and return no centres (no manual clear)")
	var xz := layout.hamlet_centre_xz + Vector2(4.0, -2.0)
	VillageTerrain.clear_knoll_centres_cache()
	p.reset_to_production()
	var t0 := Time.get_ticks_usec()
	for _i in 2000:
		VillageTerrain.sample_y(xz, layout, p, t_seed)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("sample_y 2000 calls: %.1f ms (knoll cache on)" % ms)
	VillageTerrain.clear_knoll_centres_cache()
