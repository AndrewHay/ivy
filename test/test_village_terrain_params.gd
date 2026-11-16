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
	## ivy-82zn.14.10 / ivy-sx7x: 0.56 → 0.30 (path-quiet un-inverted; same open-lawn amplitude).
	assert_almost_eq(p.base_amplitude_m, 0.30, 0.001, "base_amplitude_m=0.30 (ivy-82zn.14.10)")
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
	assert_almost_eq(p.max_rise_m, 1.6, 0.001, "max_rise_m=1.6 (ivy-82zn.14.1)")
	assert_almost_eq(p.max_depression_m, 0.9, 0.001, "max_depression_m=0.9 (ivy-82zn.14.1)")
	assert_almost_eq(p.max_path_slope_deg, 18.0, 0.001, "max_path_slope_deg=18.0 (ivy-82zn.14.10 hill)")


func test_production_defaults_pond_fields() -> void:
	var p := VillageTerrainParams.production()
	assert_almost_eq(p.pond_depth_m, -0.6, 0.001, "pond_depth_m=-0.6")
	assert_almost_eq(p.pond_lip_rise_m, 0.12, 0.001, "pond_lip_rise_m=0.12")
	assert_almost_eq(p.pond_water_inset_m, 0.10, 0.001, "pond_water_inset_m=0.10")


func test_production_defaults_knoll_fields() -> void:
	var p := VillageTerrainParams.production()
	assert_eq(p.knoll_count, 2, "knoll_count=2")
	assert_almost_eq(p.knoll_height_m, 0.95, 0.001,
		"knoll_height_m=0.95 (ivy-82zn.14.1 1.00, trimmed in ivy-82zn.14.5 for the rim-inclusive 8° sweep)")
	assert_almost_eq(p.knoll_radius_m, 18.0, 0.001, "knoll_radius_m=18.0 (ivy-82zn.14.1)")
	assert_almost_eq(p.knoll_min_sep_m, 28.0, 0.001, "knoll_min_sep_m=28.0 (ivy-82zn.14.1)")
	assert_almost_eq(p.knoll_hero_clear_m, 26.0, 0.001, "knoll_hero_clear_m=26.0 (ivy-82zn.14.1)")
	assert_almost_eq(p.knoll_path_clear_m, 18.0, 0.001, "knoll_path_clear_m=18.0 (ivy-82zn.14.1)")
	assert_almost_eq(p.knoll_pad_clear_m, 18.0, 0.001, "knoll_pad_clear_m=18.0 (ivy-82zn.14.1)")
	assert_almost_eq(p.knoll_sun_corridor_half_deg, 35.0, 0.001, "knoll_sun_corridor_half_deg=35.0")


func test_production_defaults_swell_fields() -> void:
	## ivy-82zn.14.1 village swell (architect plan ivy-82zn.14.4); every field is a G7 knob.
	var p := VillageTerrainParams.production()
	assert_almost_eq(p.swell_amp_m, 0.25, 0.001, "swell_amp_m=0.25 (ivy-82zn.14.10: the hill carries the anchors)")
	assert_almost_eq(p.swell_feature_m, 80.0, 0.001, "swell_feature_m=80")
	assert_almost_eq(p.swell_hero_fade_m, 10.0, 0.001, "swell_hero_fade_m=10")
	assert_almost_eq(p.swell_rim_fade_m, 12.0, 0.001, "swell_rim_fade_m=12")
	assert_almost_eq(p.swell_sun_corridor_gain, 1.0, 0.001, "swell_sun_corridor_gain=1 (no effect)")


## ivy-82zn.14.10 contract change: the pre-swell golden table (_PRE_SWELL_SEED7, fixer tree
## ivy-82zn.14.5) is retired. The swell moved from the detail layer to the large layer, the path
## corridor became a correction and ivy-sx7x was fixed, so no knob combination reproduces the
## pre-hill heights any more. The off switches are pinned per layer instead.
const _SWELL_PROBE_SEED7: Array[Vector2] = [
	Vector2(21.794, -5.704), Vector2(-11.682, -21.949), Vector2(0.0, -18.0), Vector2(-13.978, -46.532),
	Vector2(-40.0, -17.0), Vector2(-22.0, 3.0), Vector2(-9.0, 24.0), Vector2(13.0, -38.0), Vector2(31.0, 3.0),
]


func test_swell_off_makes_the_large_layer_the_hill_alone_seed7() -> void:
	## swell_amp_m 0: the large layer (before terraces) is exactly the hill P, and the detail layer is
	## the same as with the swell on (the swell only ever lives in the large layer).
	var layout := VillageLayout.generate(7)
	var p := VillageTerrainParams.production()
	var off := p.duplicate_params()
	off.swell_amp_m = 0.0
	VillageTerrain.clear_knoll_centres_cache()
	var t_seed := VillageTerrain.terrain_seed(layout, p)
	for xz in _SWELL_PROBE_SEED7:
		assert_almost_eq(VillageTerrain._large_raw(xz, layout, off, t_seed),
			VillageTerrain.hill_y(xz, layout, off), 1e-6, "swell off: L == P at %s" % str(xz))
		assert_almost_eq(VillageTerrain.detail_y(xz, layout, off, t_seed),
			VillageTerrain.detail_y(xz, layout, p, t_seed), 1e-6, "detail layer has no swell at %s" % str(xz))
	VillageTerrain.clear_knoll_centres_cache()


func test_hill_and_swell_off_leave_the_detail_layer_seed7() -> void:
	## hill_rise_m 0 + swell_amp_m 0: the large layer is flat (0) except where a terrace levels it
	## (anchors are then 0 too), so sample_y is the detail layer + path correction + hero datum 0.
	var layout := VillageLayout.generate(7)
	var p := VillageTerrainParams.production()
	p.swell_amp_m = 0.0
	p.hill_rise_m = 0.0
	VillageTerrain.clear_knoll_centres_cache()
	var t_seed := VillageTerrain.terrain_seed(layout, p)
	assert_eq(VillageTerrain.hero_datum_y(layout, p), 0.0, "no hill: datum 0")
	for xz in _SWELL_PROBE_SEED7:
		assert_almost_eq(VillageTerrain._large_terraced(xz, layout, p, t_seed), 0.0, 1e-6,
			"no hill, no swell: large layer 0 at %s" % str(xz))
	VillageTerrain.clear_knoll_centres_cache()


func test_path_spine_cache_follows_swell_edit() -> void:
	## The path spine bakes heights; editing a swell knob (no manual clear) must rebuild it.
	var layout := VillageLayout.generate(7)
	var p := VillageTerrainParams.production()
	var t_seed := VillageTerrain.terrain_seed(layout, p)
	var path_pts: Array[Vector2] = []
	for polyline: Variant in layout.path_polylines():
		var pts: Array = polyline
		for i in range(pts.size() - 1):
			path_pts.append((pts[i] as Vector2).lerp(pts[i + 1] as Vector2, 0.5))
	VillageTerrain.clear_knoll_centres_cache()
	for xz: Vector2 in path_pts:
		VillageTerrain.sample_y(xz, layout, p, t_seed)
	p.swell_amp_m = 0.6  # an edit away from the 0.25 default
	var cached: Array[float] = []
	for xz: Vector2 in path_pts:
		cached.append(VillageTerrain.sample_y(xz, layout, p, t_seed))
	VillageTerrain.clear_knoll_centres_cache()
	for i in path_pts.size():
		assert_almost_eq(cached[i], VillageTerrain.sample_y(path_pts[i], layout, p, t_seed), 1e-6,
			"path point %s: cached spine after swell edit == fresh" % str(path_pts[i]))
	VillageTerrain.clear_knoll_centres_cache()


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
	assert_almost_eq(p2.base_amplitude_m, p.base_amplitude_m, 0.001, "from_dict restores base_amplitude_m")
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
	assert_almost_eq(p.base_amplitude_m, VillageTerrainParams.production().base_amplitude_m, 0.001,
		"reset restores base_amplitude_m")


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
	assert_almost_eq(p.base_amplitude_m, VillageTerrainParams.production().base_amplitude_m, 0.001,
		"apply Production resets amplitude")


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


## Params with no playground knob row by design (resource bookkeeping, not feel).
const _NO_KNOB_PARAMS := ["resource_local_to_scene", "resource_name", "script",
	"resource_scene_unique_id"]


func test_every_param_has_a_knob_row() -> void:
	## G7 / ivy-82zn.14.1: every feel-shaping VillageTerrainParams field is a live playground knob.
	var knob_names := {}
	for row: Dictionary in VillageTerrainKnobSpec.all_knobs():
		knob_names[row["name"]] = true
	for key: String in VillageTerrainParams.production().to_dict().keys():
		if key in _NO_KNOB_PARAMS:
			continue
		assert_true(knob_names.has(key), "param %s has no playground knob row" % key)


func test_production_defaults_ground_shading() -> void:
	## ivy-82zn.14.1: lawn slope shading + height tint strengths are params (G7 knobs).
	var p := VillageTerrainParams.production()
	assert_gt(p.ground_slope_dark, 0.0, "slope shading on in production")
	assert_gt(p.ground_slope_full_deg, 0.0, "slope full-dim angle > 0")
	assert_gt(p.ground_height_tint, 0.0, "height tint on in production")
	assert_gt(p.ground_height_range_m, 0.0, "height tint range > 0")


func test_production_caps_raised_for_taller_relief() -> void:
	## ivy-82zn.14.1: rise/depression caps raised to match ≥ 1.5 m open-lawn relief.
	var p := VillageTerrainParams.production()
	assert_gte(p.max_rise_m, 1.2, "max_rise_m raised from 0.8")
	assert_gte(p.max_rise_m + p.max_depression_m, 1.8, "rise + depression caps allow ≥ 1.5 m span")


func test_knoll_cache_key_covers_placement_knobs() -> void:
	## ivy-82zn.14.5 (review MINOR-2): these knobs change knoll placement (_knoll_rejected), so
	## editing one must change the cache key; otherwise knoll_centres returns stale centres.
	var layout := VillageLayout.generate(7)
	var base := VillageTerrainParams.production()
	var k0 := VillageTerrain._knoll_cache_key(layout, base)
	for field: String in ["pad_margin_m", "knoll_path_clear_m", "knoll_pad_clear_m", "rim_blend_m"]:
		var p := base.duplicate_params()
		p.set(field, float(p.get(field)) + 1.25)
		assert_ne(VillageTerrain._knoll_cache_key(layout, p), k0,
			"_knoll_cache_key must change when %s changes" % field)


func test_knoll_centres_cache_invalidates_on_placement_knob_edit() -> void:
	## ivy-82zn.14.5: behavioural form of the key test. After editing a placement knob without a
	## manual clear, knoll_centres must equal a fresh (cleared) computation.
	var edits := {"knoll_path_clear_m": 4.0, "knoll_pad_clear_m": 2.0, "pad_margin_m": 9.0}
	var differed := 0
	for field: String in edits.keys():
		for seed: int in range(1, 13):
			var layout := VillageLayout.generate(seed)
			if layout.fallback:
				continue
			var p := VillageTerrainParams.production()
			var t_seed := VillageTerrain.terrain_seed(layout, p)
			VillageTerrain.clear_knoll_centres_cache()
			var before := VillageTerrain.knoll_centres(layout, p, t_seed).duplicate()
			p.set(field, edits[field])
			var cached := VillageTerrain.knoll_centres(layout, p, t_seed).duplicate()
			VillageTerrain.clear_knoll_centres_cache()
			var fresh := VillageTerrain.knoll_centres(layout, p, t_seed).duplicate()
			assert_eq(cached, fresh, "seed %d %s edit: cached centres must match fresh" % [seed, field])
			if fresh != before:
				differed += 1
	VillageTerrain.clear_knoll_centres_cache()
	assert_gt(differed, 0, "at least one edit must move knolls, or the test proves nothing")


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
