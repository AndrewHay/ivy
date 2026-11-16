## ivy-82zn.14.8: terrain playground knob ranges are wide enough to experiment past the gentle
## limits, the HUD names the limits the current settings exceed, and maxing base amplitude with the
## hero disc released really does add relief near the hero (with the remaining limiters named).
extends GutTest

const VillageTerrainParams = preload("res://src/playground/village_terrain_params.gd")
const VillageTerrainKnobSpec = preload("res://src/playground/village_terrain_knob_spec.gd")
const VillageTerrain = preload("res://src/playground/village_terrain.gd")

## Acceptance 3: minimum experimentation range per relief-shaping knob.
const WIDE_RANGES := {
	"base_amplitude_m": [0.0, 6.0],
	"max_rise_m": [0.0, 8.0],
	"max_depression_m": [0.0, 6.0],
	"knoll_height_m": [0.0, 6.0],
	"swell_amp_m": [0.0, 5.0],
	"hero_flat_r_m": [0.0, 12.0],
	"hero_skirt_m": [0.0, 10.0],
	"open_lawn_pad_quiet_m": [0.0, 40.0],
	## ivy-82zn.14.10 (AC 3): relief fades are floored at 1 m (a 0 m fade was a C0 cliff that the
	## lawn mesh drew as a dark contour line); the sampler floors them too (RELIEF_FADE_FLOOR_M).
	"open_lawn_pad_fade_m": [1.0, 40.0],
	"hero_relief_fade_m": [1.0, 40.0],
	"plaza_relief_fade_m": [1.0, 40.0],
	"pond_relief_fade_m": [1.0, 40.0],
	"swell_hero_fade_m": [0.0, 40.0],
	"swell_rim_fade_m": [0.0, 40.0],
	"pad_skirt_m": [0.0, 8.0],
	"pad_edge_slope_max_deg": [0.0, 45.0],
	"max_path_slope_deg": [0.0, 45.0],
	"pond_depth_m": [-4.0, 0.0],
	"plaza_relief_m": [-2.0, 2.0],
	"center_bias_gain": [0.0, 4.0],
	"knoll_count": [0.0, 12.0],
}

## Hard-coded limiters in VillageTerrain that still flatten the centre with every relief knob
## released (base_amplitude_m 6, hero_flat_r_m 0, hero_relief_fade_m 0, hero_skirt_m 0, caps open,
## pad / plaza / pond fades 0). Measured by test_hero_span_limiter_breakdown; listed in the notes.
const REMAINING_CENTRE_LIMITERS := [
	"hero blend (_apply_hero): the stoop itself stays at the hero datum (the hill crest)",
	"path corridor (_PATH_CORRIDOR_OUTER_M 5 m): graded path spine as a correction faded over 5 m",
	"path quiet floor 0.38 / 0.52 on the stones, full noise from 5 m out (path_quiet_gain)",
	"cottage pad stamp + skirt: the hero cottage pad is flat by design (pad_skirt_m only widens it)",
	"plaza stamp: plaza rect flattened to its centre height + plaza_relief_m (plaza_skirt_m)",
]

const HERO_SPAN_R_M := 10.0
const HERO_SPAN_STEP_M := 1.0


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
		assert_true(float(row["min"]) <= float(want[0]) + 1e-6,
			"%s min %s must reach %s" % [name, row["min"], want[0]])
		assert_true(float(row["max"]) >= float(want[1]) - 1e-6,
			"%s max %s must reach %s" % [name, row["max"], want[1]])


func test_gentle_limits_are_the_previous_ranges_and_hold_defaults() -> void:
	## Every widened row keeps its old range as gentle_min / gentle_max; production sits inside.
	var p := VillageTerrainParams.production()
	for name: String in WIDE_RANGES:
		var row := _row(name)
		assert_true(row.has("gentle_min") and row.has("gentle_max"), "%s has gentle limits" % name)
		if not row.has("gentle_min"):
			continue
		var v := float(p.get(name))
		assert_true(v >= float(row["gentle_min"]) - 1e-6 and v <= float(row["gentle_max"]) + 1e-6,
			"production %s = %s inside gentle %s..%s" % [name, v, row["gentle_min"], row["gentle_max"]])
	var amp := _row("base_amplitude_m")
	assert_almost_eq(float(amp["gentle_max"]), 2.0, 1e-6, "old base amplitude cap is the gentle cap")


func test_gentle_limit_violations_name_exceeded_knobs() -> void:
	var p := VillageTerrainParams.production()
	assert_eq(VillageTerrainKnobSpec.gentle_limit_violations(p).size(), 0, "defaults exceed nothing")
	p.base_amplitude_m = 5.0
	p.hero_flat_r_m = 0.0
	var v: PackedStringArray = VillageTerrainKnobSpec.gentle_limit_violations(p)
	assert_eq(v.size(), 2, "two knobs beyond gentle limits: %s" % str(v))
	var joined := " | ".join(v)
	assert_string_contains(joined, "base_amplitude_m")
	assert_string_contains(joined, "hero_flat_r_m")


func test_cap_notes_flag_pond_and_plaza_clamped_by_the_caps() -> void:
	## The final sample_y clamp (-max_depression_m .. max_rise_m) also caps pond depth and plaza
	## relief; the HUD says so instead of the knob silently doing nothing.
	var p := VillageTerrainParams.production()
	assert_eq(VillageTerrainKnobSpec.relief_cap_notes(p).size(), 0, "defaults: no cap notes")
	p.pond_depth_m = -3.0
	p.plaza_relief_m = 1.9
	var joined := " | ".join(VillageTerrainKnobSpec.relief_cap_notes(p))
	assert_string_contains(joined, "pond_depth_m")
	assert_string_contains(joined, "max_depression_m")
	assert_string_contains(joined, "plaza_relief_m")
	assert_string_contains(joined, "max_rise_m")
	p.max_depression_m = 4.0
	p.max_rise_m = 3.0
	assert_eq(VillageTerrainKnobSpec.relief_cap_notes(p).size(), 0, "caps opened: no notes")


func test_out_of_limit_values_are_not_blocked_and_stay_finite() -> void:
	## Each knob at its new min and max: the sampler returns finite heights (no NaN / inf).
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var pts: Array[Vector2] = [
		VillageLayout.HERO_DOOR_STOOP, VillageLayout.HERO_DOOR_STOOP + Vector2(4.0, 3.0),
		layout.pond_center, layout.plaza_rect.get_center(), layout.hamlet_centre_xz + Vector2(15.0, -9.0),
	]
	for name: String in WIDE_RANGES:
		var row := _row(name)
		for end in ["min", "max"]:
			var p := VillageTerrainParams.production()
			var val := float(row[end])
			if row.get("is_int", false):
				p.set(name, int(val))
			else:
				p.set(name, val)
			assert_almost_eq(float(p.get(name)), val, 1e-6, "%s=%s is accepted, not clamped" % [name, val])
			VillageTerrain.clear_knoll_centres_cache()
			var t_seed := VillageTerrain.terrain_seed(layout, p)
			for xz in pts:
				var h := VillageTerrain.sample_y(xz, layout, p, t_seed)
				assert_true(is_finite(h), "%s=%s finite at %s (got %s)" % [name, val, xz, h])


func test_pond_depth_response_characterization() -> void:
	## Pond-centre height vs pond_depth_m with the depression cap opened (seed 7). Reports the
	## response so a limiter between the knob and the basin shows up in the log.
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var p := VillageTerrainParams.production()
	p.max_depression_m = 6.0
	for d in [-0.2, -0.6, -1.0, -1.5, -2.0, -3.0, -4.0]:
		p.pond_depth_m = d
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed := VillageTerrain.terrain_seed(layout, p)
		var h := VillageTerrain.sample_y(layout.pond_center, layout, p, t_seed)
		var thru := VillageTerrain._height_through_pond_at(layout.pond_center, layout, p, t_seed,
			VillageTerrain.knoll_centres(layout, p, t_seed))
		var owner: Dictionary = VillageTerrain._min_pad_skirt_owner(layout.pond_center, layout, p)
		gut.p("pond_depth_m %.1f -> sample_y %.3f (through-pond %.3f, pad owner %s sdf %s)" % [
			d, h, thru, owner.get("index", -1), owner.get("sdf", "-")])
		assert_true(is_finite(h))
	# Same depth with the plaza raised: the cottage pads follow the plaza and pull the basin.
	p.pond_depth_m = -3.0
	for pr in [0.0, 0.5, 1.0, 1.5]:
		p.plaza_relief_m = pr
		VillageTerrain.clear_knoll_centres_cache()
		var t_seed2 := VillageTerrain.terrain_seed(layout, p)
		gut.p("pond_depth_m -3 plaza_relief_m %.1f -> pond sample_y %.3f" % [
			pr, VillageTerrain.sample_y(layout.pond_center, layout, p, t_seed2)])


static func hero_span(layout: VillageLayout, p: VillageTerrainParams) -> Dictionary:
	## min / max sample_y on a 1 m grid inside HERO_SPAN_R_M of the stoop.
	VillageTerrain.clear_knoll_centres_cache()
	var t_seed := VillageTerrain.terrain_seed(layout, p)
	var hero := VillageLayout.HERO_DOOR_STOOP
	var lo := INF
	var hi := -INF
	var n := int(HERO_SPAN_R_M / HERO_SPAN_STEP_M)
	for iz in range(-n, n + 1):
		for ix in range(-n, n + 1):
			var off := Vector2(ix, iz) * HERO_SPAN_STEP_M
			if off.length() > HERO_SPAN_R_M:
				continue
			var h := VillageTerrain.sample_y(hero + off, layout, p, t_seed)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return {"min": lo, "max": hi, "span": hi - lo}


static func extreme_params() -> VillageTerrainParams:
	var p := VillageTerrainParams.production()
	p.base_amplitude_m = 6.0
	p.hero_flat_r_m = 0.0
	p.hero_relief_fade_m = 0.0
	return p


func test_max_amplitude_with_hero_released_adds_relief_near_hero() -> void:
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var d := hero_span(layout, VillageTerrainParams.production())
	var e := hero_span(layout, extreme_params())
	gut.p("hero 10 m span: defaults %.3f m (%.3f..%.3f)  extreme %.3f m (%.3f..%.3f)" % [
		d["span"], d["min"], d["max"], e["span"], e["min"], e["max"]])
	assert_gt(float(e["span"]), 2.0 * float(d["span"]) + 0.3,
		"span within 10 m of the hero must be clearly larger at max amplitude with the hero released")


func test_hero_span_limiter_breakdown() -> void:
	## Release the remaining knob limiters one group at a time and report the span, then pin the
	## hard-coded hero edge (0.5 m soft pull) that still holds the stoop itself at datum.
	var layout := VillageLayout.generate(7)
	VillagePondShape.set_active(VillagePondShape.at(layout.pond_center))
	var p := extreme_params()
	var steps := [
		["acceptance (amp 6, hero flat 0, hero fade 0)", {}],
		["+ hero_skirt_m 0", {"hero_skirt_m": 0.0}],
		["+ caps open (rise 8, depression 6)", {"max_rise_m": 8.0, "max_depression_m": 6.0}],
		["+ pad quiet/fade 0", {"open_lawn_pad_quiet_m": 0.0, "open_lawn_pad_fade_m": 0.0}],
		["+ plaza/pond fade 0", {"plaza_relief_fade_m": 0.0, "pond_relief_fade_m": 0.0}],
		["+ path slope 45", {"max_path_slope_deg": 45.0}],
	]
	var last := 0.0
	for s: Array in steps:
		var kv: Dictionary = s[1]
		for k: String in kv:
			p.set(k, kv[k])
		var r := hero_span(layout, p)
		gut.p("limiter breakdown %-45s span %.3f m (%.3f..%.3f)" % [s[0], r["span"], r["min"], r["max"]])
		last = float(r["span"])
	assert_gt(last, 0.0, "fully released terrain has relief near the hero")
	VillageTerrain.clear_knoll_centres_cache()
	var h0 := VillageTerrain.sample_y(VillageLayout.HERO_DOOR_STOOP, layout, p,
		VillageTerrain.terrain_seed(layout, p))
	## ivy-82zn.14.10: the stoop is at the hero datum (the hill crest, hero_datum_y), held by the hero
	## blend (_apply_hero) even with hero_flat_r_m and hero_skirt_m at 0.
	assert_almost_eq(h0, VillageTerrain.hero_datum_y(layout, p), 1e-6,
		"remaining limiter: the hero blend keeps the stoop at the hero datum")
	for name: String in REMAINING_CENTRE_LIMITERS:
		gut.p("remaining centre limiter: " + name)
