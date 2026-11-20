## ivy-82zn.14.8 → ivy-82zn.14.14 (schema v2): experiment ranges for the surviving relief knobs
## reach past their gentle (SD-22) ranges; production sits inside the gentle ranges; the HUD names
## knobs beyond them. The removed caps / fades / knolls / swell rows and their cap notes are gone
## (AR-LF-KEEP). The ivy-35zj characterisation moves to the plaza test in WP2.
extends GutTest

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrainKnobSpec = preload("res://src/playground/village_terrain_knob_spec.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")

const WIDE_RANGES := {
	"landform_height_m": [0.0, 50.0],
	"base_amplitude_m": [0.0, 3.0],
	"max_path_slope_deg": [0.0, 45.0],
	"hero_flat_r_m": [0.0, 12.0],
	"pond_depth_m": [-4.0, 0.0],
	"pond_lip_rise_m": [0.0, 1.0],
	"pond_skirt_m": [0.0, 10.0],
}


func _row(name: String) -> Dictionary:
	for row: Dictionary in VillageTerrainKnobSpec.all_knobs():
		if row["name"] == name:
			return row
	return {}


func test_relief_knob_ranges_are_wide() -> void:
	for name: String in WIDE_RANGES:
		var row := _row(name)
		assert_false(row.is_empty(), "knob row exists: %s" % name)
		if row.is_empty():
			continue
		var want: Array = WIDE_RANGES[name]
		assert_true(float(row["min"]) <= float(want[0]) + 1e-6, "%s min reaches %s" % [name, want[0]])
		assert_true(float(row["max"]) >= float(want[1]) - 1e-6, "%s max reaches %s" % [name, want[1]])
		assert_true(row.has("gentle_min") and row.has("gentle_max"), "%s keeps its gentle range" % name)


func test_gentle_ranges_are_the_sd22_ranges() -> void:
	assert_almost_eq(float(_row("landform_height_m")["gentle_max"]), 30.0, 1e-6, "SD-22 height range 0–30")
	assert_almost_eq(float(_row("base_amplitude_m")["gentle_max"]), 0.8, 1e-6, "SD-22 detail range 0–0.8")
	assert_almost_eq(float(_row("max_path_slope_deg")["gentle_min"]), 8.0, 1e-6, "SD-22 path cap 8–20")


func test_gentle_limit_violations_name_exceeded_knobs() -> void:
	var p := VillageTerrainParams.production()
	assert_eq(VillageTerrainKnobSpec.gentle_limit_violations(p).size(), 0, "defaults exceed nothing")
	p.landform_height_m = 40.0
	p.hero_flat_r_m = 0.0
	var v: PackedStringArray = VillageTerrainKnobSpec.gentle_limit_violations(p)
	assert_eq(v.size(), 2, "two knobs beyond gentle limits: %s" % str(v))
	var joined := " | ".join(v)
	assert_string_contains(joined, "landform_height_m")
	assert_string_contains(joined, "hero_flat_r_m")


func test_removed_rows_are_gone() -> void:
	for name in ["max_rise_m", "knoll_height_m", "swell_amp_m", "hero_skirt_m", "pad_skirt_m",
			"hero_relief_fade_m", "hill_rise_m", "rim_blend_m", "center_bias_gain"]:
		assert_true(_row(name).is_empty(), "%s row removed" % name)
	assert_false((VillageTerrainKnobSpec as GDScript).get_script_method_list().any(
		func(m): return m["name"] == "relief_cap_notes"), "cap notes removed with the caps")


func test_taller_landform_adds_relief_at_the_experiment_end() -> void:
	## The widened height range is real: 40 m of landform makes a taller village than production.
	var layout := VillageLayout.generate(7)
	var p := VillageTerrainParams.production()
	var span := func(params: VillageTerrainParams) -> float:
		var f = VillageTerrain.field(layout, params)
		var lo := INF
		var hi := -INF
		for i in range(400):
			var a := float(i) * 2.399
			var xz: Vector2 = layout.hamlet_centre_xz + Vector2(cos(a), sin(a)) * 40.0 * sqrt(i / 400.0)
			lo = minf(lo, f.sample_y(xz))
			hi = maxf(hi, f.sample_y(xz))
		return hi - lo
	var s0: float = span.call(p)
	var tall := p.duplicate_params()
	tall.landform_height_m = 40.0
	var s1: float = span.call(tall)
	assert_gt(s1, s0 * 1.5, "40 m landform span %.2f vs production %.2f" % [s1, s0])
